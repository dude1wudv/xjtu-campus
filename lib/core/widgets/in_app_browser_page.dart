import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/notifications/data/dean_public_challenge.dart';
import '../../features/notifications/data/dean_webview_stealth.dart';
import '../constants/campus_urls.dart';
import '../../features/campus_card/data/ncard_mobile_stealth.dart';
import '../di/core_providers.dart';
import '../network/imported_campus_cookie.dart';
import '../network/webview_cookie_bridge.dart';
import '../logging/app_logger.dart';
import '../theme/app_theme.dart';

/// 应用内浏览器：通知原文、教务页等在 App 内打开。
class InAppBrowserPage extends ConsumerStatefulWidget {
  const InAppBrowserPage({
    super.key,
    required this.initialUrl,
    this.title,
  });

  final String initialUrl;
  final String? title;

  @override
  ConsumerState<InAppBrowserPage> createState() => _InAppBrowserPageState();
}

class _InAppBrowserPageState extends ConsumerState<InAppBrowserPage> {
  static const _challengePollWindow = Duration(seconds: 15);
  static const _challengePollInterval = Duration(milliseconds: 700);

  InAppWebViewController? _controller;
  double _progress = 0;
  late String _title;
  String? _errorMessage;
  var _challengeStuck = false;
  var _hasStartedLoading = false;
  DateTime? _challengeSeenAt;
  Timer? _challengePollTimer;
  var _exportedClientId = false;
  /// 无权访问页已自动改用系统浏览器（只触发一次）。
  var _openedSystemForAccessDenied = false;

  bool get _isDeanHost {
    final host = Uri.tryParse(widget.initialUrl)?.host.toLowerCase() ?? '';
    return host == 'dean.xjtu.edu.cn' || host == 'due.xjtu.edu.cn';
  }

  bool get _isNcardHost {
    final host = Uri.tryParse(widget.initialUrl)?.host.toLowerCase() ?? '';
    return host.contains('ncard');
  }

  bool get _isLibHost {
    final host = Uri.tryParse(widget.initialUrl)?.host.toLowerCase() ?? '';
    return host == 'lib.xjtu.edu.cn' || host.endsWith('.lib.xjtu.edu.cn');
  }

  String get _webUserAgent =>
      _isNcardHost ? CampusUrls.ncardMobileUserAgent : CampusUrls.userAgent;

  UnmodifiableListView<UserScript>? get _initialUserScripts {
    if (_isNcardHost) {
      return UnmodifiableListView<UserScript>([
        UserScript(
          source: NcardMobileStealth.script,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]);
    }
    if (!_isDeanHost) return null;
    return UnmodifiableListView<UserScript>([
      UserScript(
        source: DeanWebViewStealth.script,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    ]);
  }

  @override
  void initState() {
    super.initState();
    _title = widget.title ?? '浏览';
  }

  @override
  void dispose() {
    _challengePollTimer?.cancel();
    super.dispose();
  }

  Future<void> _injectStealth(InAppWebViewController controller) async {
    if (_isNcardHost) {
      try {
        await controller.evaluateJavascript(source: NcardMobileStealth.script);
      } on Object catch (error) {
        AppLogger.warn('InAppBrowser ncard mobile spoof 失败: $error');
      }
      return;
    }
    if (!_isDeanHost) return;
    try {
      await controller.evaluateJavascript(source: DeanWebViewStealth.script);
    } on Object catch (error) {
      AppLogger.warn('InAppBrowser stealth evaluate 失败: $error');
    }
  }

  Future<void> _dismissNcardMobileDialog(
    InAppWebViewController controller,
  ) async {
    if (!_isNcardHost) return;
    try {
      await controller.evaluateJavascript(
        source: NcardMobileStealth.dismissMobileDialogScript,
      );
    } on Object catch (error) {
      AppLogger.warn('InAppBrowser ncard dismiss dialog 失败: $error');
    }
  }

  Future<void> _exportClientIdCookie() async {
    if (_exportedClientId || !_isDeanHost) return;
    try {
      final manager = CookieManager.instance();
      final cookies =
          await manager.getCookies(url: WebUri(widget.initialUrl));
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
      final uri = Uri.parse(widget.initialUrl);
      final session = ref.read(campusSessionProvider);
      await session.importCookies([
        ImportedCampusCookie(
          name: 'client_id',
          value: clientId,
          domain: uri.host,
          path: '/',
          scheme: uri.scheme.isEmpty ? 'https' : uri.scheme,
          port: uri.hasPort ? uri.port : null,
          secure: true,
        ),
      ]);
      _exportedClientId = true;
      AppLogger.info('InAppBrowser 已导出 ${uri.host} client_id 到 CampusSession');
    } on Object catch (error) {
      AppLogger.warn('InAppBrowser 导出 client_id 失败: $error');
    }
  }

  Future<void> _exportLibraryCookies() async {
    if (!_isLibHost) return;
    try {
      final session = ref.read(campusSessionProvider);
      final origins = <String>{
        widget.initialUrl,
        ...WebViewCookieBridge.libraryOrigins,
      };
      final n = await WebViewCookieBridge.importOrigins(
        session: session,
        origins: origins,
      );
      if (n > 0) {
        AppLogger.info('InAppBrowser 已导出图书馆 Cookie $n 条到 CampusSession');
      }
    } on Object catch (error) {
      AppLogger.warn('InAppBrowser 导出图书馆 Cookie 失败: $error');
    }
  }

  Future<String> _pageHtml(InAppWebViewController controller) async {
    try {
      final raw = await controller.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      final html = raw?.toString() ?? '';
      if (html.isEmpty || html == 'null') return '';
      return html;
    } on Object {
      return '';
    }
  }


  Future<String> _pageTitle(InAppWebViewController controller) async {
    try {
      final raw = await controller.evaluateJavascript(source: 'document.title');
      final title = raw?.toString() ?? '';
      if (title.isEmpty || title == 'null') return _title;
      return title;
    } on Object {
      return _title;
    }
  }

  /// 教务处等站点返回的「无权访问」类 403 页。
  static bool looksLikeAccessDenied({required String html, required String title}) {
    final hay = '$title\n$html';
    const needles = [
      '无权访问',
      '您无权访问本页面',
      '您无权访问',
      '没有权限访问',
      'Access Denied',
      '403 Forbidden',
    ];
    for (final n in needles) {
      if (hay.contains(n)) return true;
    }
    return false;
  }

  Future<void> _handleAccessDeniedFallback() async {
    if (_openedSystemForAccessDenied) return;
    _openedSystemForAccessDenied = true;
    _challengePollTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    await _openInSystemBrowser();
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('已改用系统浏览器打开')),
    );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleLoadStop(InAppWebViewController controller) async {
    await _injectStealth(controller);
    await _dismissNcardMobileDialog(controller);

    final html = await _pageHtml(controller);
    final pageTitle = await _pageTitle(controller);
    if (html.isNotEmpty || pageTitle.isNotEmpty) {
      if (looksLikeAccessDenied(html: html, title: pageTitle)) {
        await _handleAccessDeniedFallback();
        return;
      }
    }

    if (!_isDeanHost) {
      unawaited(_exportClientIdCookie());
      unawaited(_exportLibraryCookies());
      return;
    }

    if (html.isEmpty) return;

    if (!DeanPublicChallenge.looksLikeChallenge(html)) {
      _challengePollTimer?.cancel();
      _challengeSeenAt = null;
      if (mounted && _challengeStuck) {
        setState(() => _challengeStuck = false);
      }
      unawaited(_exportClientIdCookie());
      return;
    }

    _challengeSeenAt ??= DateTime.now();
    final elapsed = DateTime.now().difference(_challengeSeenAt!);
    if (elapsed >= _challengePollWindow) {
      _challengePollTimer?.cancel();
      if (mounted && !_challengeStuck) {
        setState(() => _challengeStuck = true);
      }
      return;
    }

    _startChallengePolling(controller);
  }

  void _startChallengePolling(InAppWebViewController controller) {
    if (_challengePollTimer?.isActive ?? false) return;
    var midReloadDone = false;
    _challengePollTimer = Timer.periodic(_challengePollInterval, (_) async {
      if (!mounted) {
        _challengePollTimer?.cancel();
        return;
      }
      final html = await _pageHtml(controller);
      if (html.isEmpty) return;

      if (!DeanPublicChallenge.looksLikeChallenge(html)) {
        _challengePollTimer?.cancel();
        _challengeSeenAt = null;
        if (_challengeStuck) {
          setState(() => _challengeStuck = false);
        }
        unawaited(_exportClientIdCookie());
        return;
      }

      final seenAt = _challengeSeenAt ?? DateTime.now();
      _challengeSeenAt = seenAt;
      final elapsed = DateTime.now().difference(seenAt);
      // One mid-window reload if still stuck on interstitial.
      if (!midReloadDone && elapsed >= const Duration(seconds: 6)) {
        midReloadDone = true;
        try {
          await _injectStealth(controller);
          await controller.reload();
        } on Object catch (error) {
          AppLogger.warn('InAppBrowser challenge reload 失败: $error');
        }
        return;
      }
      if (elapsed >= _challengePollWindow) {
        _challengePollTimer?.cancel();
        if (mounted) {
          setState(() => _challengeStuck = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('页面安全验证未通过，可改用系统浏览器打开'),
              action: SnackBarAction(
                label: '系统浏览器',
                onPressed: _openInSystemBrowser,
              ),
            ),
          );
        }
      }
    });
  }

  Future<void> _openInSystemBrowser() async {
    final uri = Uri.tryParse(widget.initialUrl);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开系统浏览器')),
      );
    }
  }

  Future<void> _retry() async {
    _challengePollTimer?.cancel();
    setState(() {
      _errorMessage = null;
      _challengeStuck = false;
      _challengeSeenAt = null;
      _progress = 0;
      _hasStartedLoading = false;
    });
    try {
      await _controller?.loadUrl(
        urlRequest: URLRequest(url: WebUri(widget.initialUrl)),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorMessage = '重新加载失败：$error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showLoadingOverlay =
        !_hasStartedLoading && _errorMessage == null && !_challengeStuck;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '系统浏览器打开',
            onPressed: _openInSystemBrowser,
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 1 && _errorMessage == null)
            LinearProgressIndicator(
              value: _progress <= 0 ? null : _progress,
              minHeight: 2,
              backgroundColor: Colors.transparent,
            ),
          Expanded(
            child: ColoredBox(
              color: AppColors.surface,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  InAppWebView(
                    initialUrlRequest:
                        URLRequest(url: WebUri(widget.initialUrl)),
                    initialUserScripts: _initialUserScripts,
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      thirdPartyCookiesEnabled: true,
                      mediaPlaybackRequiresUserGesture: true,
                      userAgent: _webUserAgent,
                      preferredContentMode: _isNcardHost
                          ? UserPreferredContentMode.MOBILE
                          : UserPreferredContentMode.RECOMMENDED,
                      supportZoom: !_isNcardHost,
                      cacheEnabled: true,
                      transparentBackground: false,
                    ),
                    onWebViewCreated: (c) async {
                      _controller = c;
                      await _injectStealth(c);
                    },
                    onLoadStart: (c, url) async {
                      await _injectStealth(c);
                      if (mounted) {
                        setState(() {
                          _errorMessage = null;
                          _challengeStuck = false;
                        });
                      }
                    },
                    onProgressChanged: (c, p) {
                      if (!mounted) return;
                      setState(() {
                        _progress = p / 100;
                        if (p > 0) _hasStartedLoading = true;
                      });
                    },
                    onTitleChanged: (c, title) {
                      if (title != null && title.trim().isNotEmpty) {
                        final t = title.trim();
                        setState(() => _title = t);
                        if (looksLikeAccessDenied(html: '', title: t)) {
                          unawaited(_handleAccessDeniedFallback());
                        }
                      }
                    },
                    onLoadStop: (c, url) => _handleLoadStop(c),
                    onReceivedError: (c, request, error) {
                      // Ignore subframe / non-main-frame noise when possible.
                      final isMain = request.isForMainFrame ?? true;
                      if (!isMain) return;
                      AppLogger.warn(
                        'InAppBrowser 加载错误: ${error.description}',
                      );
                      if (!mounted) return;
                      setState(() {
                        _errorMessage = error.description.isNotEmpty
                            ? error.description
                            : '页面加载失败';
                        _progress = 1;
                      });
                    },
                  ),
                  if (showLoadingOverlay)
                    const ColoredBox(
                      color: AppColors.surface,
                      child: Center(
                        child: Text(
                          '加载中…',
                          style: TextStyle(
                            color: AppColors.inkSoft,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (_errorMessage != null)
                    _BrowserStatusPane(
                      icon: Icons.wifi_off_rounded,
                      message: _errorMessage!,
                      primaryLabel: '重试',
                      onPrimary: _retry,
                      secondaryLabel: '系统浏览器打开',
                      onSecondary: _openInSystemBrowser,
                    ),
                  if (_challengeStuck && _errorMessage == null)
                    _BrowserStatusPane(
                      icon: Icons.security_rounded,
                      message: '页面安全验证未通过，内容未能加载。可刷新重试，或改用系统浏览器打开。',
                      primaryLabel: '刷新重试',
                      onPrimary: _retry,
                      secondaryLabel: '系统浏览器打开',
                      onSecondary: _openInSystemBrowser,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowserStatusPane extends StatelessWidget {
  const _BrowserStatusPane({
    required this.icon,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final IconData icon;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: AppColors.inkSoft),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onPrimary,
                child: Text(primaryLabel),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
