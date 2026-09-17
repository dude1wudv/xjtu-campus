import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/cache/snapshot_cache.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/network/imported_campus_cookie.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/logging/app_logger.dart';
import '../data/dean_notices_parser.dart';
import '../data/dean_public_challenge.dart';
import '../data/dean_webview_stealth.dart';
import '../domain/school_notice.dart';

/// Result of the embedded (non-headless) dean notices WebView load.
enum LiveDeanNoticesStatus { idle, loading, success, failed }

class LiveDeanNoticesState {
  const LiveDeanNoticesState({
    this.status = LiveDeanNoticesStatus.idle,
    this.notices = const [],
    this.baseUrl,
    this.fromCache = false,
    this.cachedAt,
    this.fetchedAt,
  });

  final LiveDeanNoticesStatus status;
  final List<SchoolNotice> notices;
  final String? baseUrl;
  final bool fromCache;
  final DateTime? cachedAt;
  final DateTime? fetchedAt;

  bool get isLoading =>
      status == LiveDeanNoticesStatus.loading ||
      status == LiveDeanNoticesStatus.idle;

  bool get isSuccess =>
      status == LiveDeanNoticesStatus.success && notices.isNotEmpty;

  bool get isFailed => status == LiveDeanNoticesStatus.failed;

  /// Cached list available while WebView still loading / failed.
  bool get hasCachedNotices => notices.isNotEmpty && fromCache;

  LiveDeanNoticesState copyWith({
    LiveDeanNoticesStatus? status,
    List<SchoolNotice>? notices,
    String? baseUrl,
    bool? fromCache,
    DateTime? cachedAt,
    DateTime? fetchedAt,
  }) {
    return LiveDeanNoticesState(
      status: status ?? this.status,
      notices: notices ?? this.notices,
      baseUrl: baseUrl ?? this.baseUrl,
      fromCache: fromCache ?? this.fromCache,
      cachedAt: cachedAt ?? this.cachedAt,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }
}

class LiveDeanNoticesNotifier extends Notifier<LiveDeanNoticesState> {
  @override
  LiveDeanNoticesState build() {
    Future.microtask(_hydrateFromCache);
    return const LiveDeanNoticesState(
      status: LiveDeanNoticesStatus.loading,
    );
  }

  Future<void> _hydrateFromCache() async {
    final envelope = await ref
        .read(snapshotCacheProvider)
        .readEnvelope(SnapshotCache.notices, NoticesSnapshot.fromJson);
    if (envelope == null) return;
    // Do not clobber a live success that arrived first.
    if (state.isSuccess && !state.fromCache) return;
    if (state.status == LiveDeanNoticesStatus.failed) {
      state = LiveDeanNoticesState(
        status: LiveDeanNoticesStatus.failed,
        notices: envelope.payload.notices,
        fromCache: true,
        cachedAt: envelope.savedAt,
      );
      return;
    }
    state = LiveDeanNoticesState(
      status: state.isLoading
          ? LiveDeanNoticesStatus.loading
          : state.status,
      notices: envelope.payload.notices,
      fromCache: true,
      cachedAt: envelope.savedAt,
    );
  }

  void markLoading() {
    // Keep prior cache visible under loading if we had one.
    final prior = state;
    state = LiveDeanNoticesState(
      status: LiveDeanNoticesStatus.loading,
      notices: prior.fromCache || prior.isSuccess ? prior.notices : const [],
      fromCache: prior.fromCache || (prior.isSuccess && prior.notices.isNotEmpty),
      cachedAt: prior.cachedAt ?? prior.fetchedAt,
    );
  }

  void markSuccess(List<SchoolNotice> notices, {required String baseUrl}) {
    final now = DateTime.now();
    state = LiveDeanNoticesState(
      status: LiveDeanNoticesStatus.success,
      notices: notices,
      baseUrl: baseUrl,
      fromCache: false,
      fetchedAt: now,
    );
    // Persist live-only; never log full notice bodies here.
    Future.microtask(() async {
      final snap = NoticesSnapshot(
        notices: notices,
        live: true,
        banner: AppStrings.noticesLiveBanner,
      );
      await ref.read(snapshotCacheProvider).write(
            SnapshotCache.notices,
            snap.toJson(),
          );
    });
  }

  void markFailed() {
    final prior = state;
    if (prior.notices.isNotEmpty) {
      state = LiveDeanNoticesState(
        status: LiveDeanNoticesStatus.failed,
        notices: prior.notices,
        fromCache: true,
        cachedAt: prior.cachedAt ?? prior.fetchedAt,
      );
      return;
    }
    state = const LiveDeanNoticesState(status: LiveDeanNoticesStatus.failed);
  }
}

final liveDeanNoticesProvider =
    NotifierProvider<LiveDeanNoticesNotifier, LiveDeanNoticesState>(
  LiveDeanNoticesNotifier.new,
);

/// Bump to ask the embedded WebView to reload().
class DeanNoticesReloadTick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final deanNoticesReloadTickProvider =
    NotifierProvider<DeanNoticesReloadTick, int>(DeanNoticesReloadTick.new);

UserScript get _stealthUserScript => UserScript(
      source: DeanWebViewStealth.script,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    );

/// Real [InAppWebView] (not Headless) mounted Offstage / Opacity-0 so page JS
/// and CookieManager work reliably on device. Parses list HTML when ready.
class DeanNoticesWebViewLoader extends ConsumerStatefulWidget {
  const DeanNoticesWebViewLoader({super.key});

  @override
  ConsumerState<DeanNoticesWebViewLoader> createState() =>
      _DeanNoticesWebViewLoaderState();
}

class _DeanNoticesWebViewLoaderState
    extends ConsumerState<DeanNoticesWebViewLoader> {
  static const _timeout = Duration(seconds: 40);

  InAppWebViewController? _controller;
  Timer? _timeoutTimer;
  Timer? _pollTimer;
  var _finished = false;
  var _triedDue = false;
  var _currentUrl = CampusUrls.deanNotices;
  ProviderSubscription<int>? _reloadSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(liveDeanNoticesProvider.notifier).markLoading();
      _armTimeout();
      _reloadSub = ref.listenManual<int>(deanNoticesReloadTickProvider, (
        previous,
        next,
      ) {
        if (previous != null && next != previous) {
          unawaited(refresh());
        }
      });
    });
  }

  @override
  void dispose() {
    _reloadSub?.close();
    _timeoutTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _armTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_timeout, () {
      unawaited(_onTimeout());
    });
  }

  Future<void> _onTimeout() async {
    if (_finished || !mounted) return;
    if (!_triedDue) {
      _triedDue = true;
      _currentUrl = CampusUrls.dueNotices;
      AppLogger.warn('教务通知 WebView 超时，改试 due.xjtu.edu.cn');
      try {
        await _controller?.loadUrl(
          urlRequest: URLRequest(url: WebUri(ref.read(campusSessionProvider).resolveUrl(_currentUrl))),
        );
        _armTimeout();
      } on Object catch (error) {
        AppLogger.warn('due 通知页加载失败: $error');
        _fail();
      }
      return;
    }
    AppLogger.warn('教务通知 WebView 二次超时，回退 Dio');
    _fail();
  }

  void _fail() {
    if (_finished) return;
    _finished = true;
    _timeoutTimer?.cancel();
    _pollTimer?.cancel();
    if (mounted) {
      ref.read(liveDeanNoticesProvider.notifier).markFailed();
    }
  }

  Future<void> refresh() async {
    _finished = false;
    _triedDue = false;
    _currentUrl = CampusUrls.deanNotices;
    _pollTimer?.cancel();
    if (mounted) {
      ref.read(liveDeanNoticesProvider.notifier).markLoading();
    }
    _armTimeout();
    try {
      await _controller?.loadUrl(
        urlRequest: URLRequest(url: WebUri(ref.read(campusSessionProvider).resolveUrl(_currentUrl))),
      );
    } on Object catch (error) {
      AppLogger.warn('教务通知 WebView reload 失败: $error');
      _fail();
    }
  }

  Future<void> _injectStealth(InAppWebViewController controller) async {
    try {
      await controller.evaluateJavascript(source: DeanWebViewStealth.script);
    } on Object catch (error) {
      AppLogger.warn('WebView stealth evaluate 失败: $error');
    }
  }

  Future<void> _tryCapture(InAppWebViewController controller) async {
    if (_finished || !mounted) return;
    try {
      final raw = await controller.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      final html = raw?.toString() ?? '';
      if (html.isEmpty || html == 'null') return;

      final looksList = DeanPublicChallenge.looksLikeNoticeList(html);
      final isChallenge = DeanPublicChallenge.looksLikeChallenge(html);
      if (!looksList || isChallenge) return;

      final parsed = DeanNoticeParser.parse(html, base: _currentUrl);
      if (parsed.isEmpty) return;

      _finished = true;
      _timeoutTimer?.cancel();
      _pollTimer?.cancel();
      AppLogger.info('嵌入式 WebView 教务通知成功（${parsed.length} 条）');
      ref.read(liveDeanNoticesProvider.notifier).markSuccess(
            parsed,
            baseUrl: _currentUrl,
          );
      unawaited(_exportClientIdCookie());
    } on Object catch (error) {
      AppLogger.warn('嵌入式 WebView 读取教务通知 HTML 失败: $error');
    }
  }

  Future<void> _exportClientIdCookie() async {
    try {
      final manager = CookieManager.instance();
      final cookies = await manager.getCookies(url: WebUri(ref.read(campusSessionProvider).resolveUrl(_currentUrl)));
      String? clientId;
      for (final c in cookies) {
        if (c.name != 'client_id') continue;
        final v = c.value?.toString() ?? '';
        if (v.isNotEmpty) {
          clientId = v;
          break;
        }
      }
      if (clientId == null) return;
      final host = Uri.parse(_currentUrl).host;
      final session = ref.read(campusSessionProvider);
      await session.importCookies([
        ImportedCampusCookie(
          name: 'client_id',
          value: clientId,
          domain: host,
          path: '/',
          scheme: 'https',
          secure: true,
        ),
      ]);
      AppLogger.info('已从 WebView 导出 $host client_id 到 CampusSession');
    } on Object catch (error) {
      AppLogger.warn('导出 client_id Cookie 失败: $error');
    }
  }

  void _startPolling(InAppWebViewController controller) {
    _pollTimer?.cancel();
    var ticks = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      ticks++;
      if (_finished || ticks > 80) {
        _pollTimer?.cancel();
        return;
      }
      await _tryCapture(controller);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Non-zero layout size helps Android WebView actually run JS.
    return SizedBox(
      width: 1,
      height: 1,
      child: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(ref.read(campusSessionProvider).resolveUrl(_currentUrl))),
        initialUserScripts: UnmodifiableListView<UserScript>([
          _stealthUserScript,
        ]),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          thirdPartyCookiesEnabled: true,
          userAgent: CampusUrls.userAgent,
          cacheEnabled: true,
          // Keep tiny footprint when opacity-0 / offstage.
          transparentBackground: true,
        ),
        onWebViewCreated: (controller) async {
          _controller = controller;
          await _injectStealth(controller);
        },
        onLoadStart: (controller, url) async {
          await _injectStealth(controller);
        },
        onLoadStop: (controller, url) async {
          await _tryCapture(controller);
          if (_finished) return;
          _startPolling(controller);
        },
        onReceivedError: (controller, request, error) {
          AppLogger.warn('嵌入式 WebView 教务通知加载错误: ${error.description}');
        },
      ),
    );
  }
}
