import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../data/ncard_mobile_stealth.dart';
import '../data/ncard_sso.dart';

/// Full-screen mobile WebView for ncard CAS → Dio OAuth token sync.
///
/// Only pops with `true` after [NcardSso.verifyQueryCard] succeeds. Ticket
/// URLs are cancelled in [shouldOverrideUrlLoading] so the SPA cannot burn
/// the one-time ticket with a soft-warm GET.
class NcardSyncPage extends ConsumerStatefulWidget {
  const NcardSyncPage({super.key});

  @override
  ConsumerState<NcardSyncPage> createState() => _NcardSyncPageState();
}

class _NcardSyncPageState extends ConsumerState<NcardSyncPage> {
  static const _tokenPollInterval = Duration(milliseconds: 500);
  static const _tokenPollWindow = Duration(seconds: 25);

  static const _cookieOrigins = [
    'https://login.xjtu.edu.cn/',
    'https://login.xjtu.edu.cn/cas/login',
    'https://ywtb.xjtu.edu.cn/',
    CampusUrls.ncardOrigin,
    CampusUrls.ncardPlat,
    CampusUrls.ncardCasRedirect,
  ];

  InAppWebViewController? _controller;
  var _status = '正在以手机模式同步校园卡…';
  var _done = false;
  var _oauthStarted = false;
  var _polling = false;
  var _cookiesImported = false;
  Timer? _pollTimer;

  UnmodifiableListView<UserScript> get _userScripts =>
      UnmodifiableListView<UserScript>([
        UserScript(
          source: NcardMobileStealth.script,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]);

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _injectMobile(InAppWebViewController c) async {
    try {
      await c.evaluateJavascript(source: NcardMobileStealth.script);
    } on Object catch (error) {
      AppLogger.warn('ncard sync mobile spoof 失败: $error');
    }
  }

  Future<void> _dismissMobileDialog(InAppWebViewController c) async {
    try {
      await c.evaluateJavascript(
        source: NcardMobileStealth.dismissMobileDialogScript,
      );
    } on Object catch (error) {
      AppLogger.warn('ncard sync dismiss dialog 失败: $error');
    }
  }

  /// Import WebView cookies into Dio [CampusSession] after CAS → ncard.
  Future<void> _importWebViewCookies({required bool force}) async {
    if (_cookiesImported && !force) return;
    try {
      final cookieManager = CookieManager.instance();
      final all = <Cookie>[];
      for (final origin in _cookieOrigins) {
        all.addAll(await cookieManager.getCookies(url: WebUri(origin)));
      }
      final seen = <String>{};
      all.retainWhere((c) => seen.add('${c.domain}|${c.name}|${c.value}'));
      if (all.isEmpty) return;

      final mapped = <({String name, String value, String? domain, String? path})>[
        for (final c in all)
          (
            name: c.name,
            value: c.value.toString(),
            domain: c.domain,
            path: c.path,
          ),
      ];
      final session = ref.read(campusSessionProvider);
      await session.importCookies(mapped);
      _cookiesImported = true;
      AppLogger.info('ncard sync: imported ${mapped.length} WebView cookies');
    } on Object catch (error) {
      AppLogger.warn('ncard sync Cookie 导入失败: $error');
    }
  }

  Future<void> _maybeImportCookies(Uri? uri) async {
    if (uri == null || _done) return;
    final host = uri.host;
    final leftLogin = host.isNotEmpty && !host.contains('login.xjtu.edu.cn');
    final onNcard = host.contains('ncard');
    if (leftLogin || onNcard) {
      await _importWebViewCookies(force: onNcard && !_cookiesImported);
    }
  }

  /// Ticket capture → oauth → verifyQueryCard. Never pops without verify OK.
  Future<void> _startOauthFromTicket(String ticket) async {
    if (_done || _oauthStarted) return;
    _oauthStarted = true;
    if (mounted) {
      setState(() => _status = '换取令牌…');
    }

    await _importWebViewCookies(force: true);

    final session = ref.read(campusSessionProvider);
    final sso = NcardSso(session);
    final access = await sso.oauthAndSave(ticket);
    if (!mounted || _done) return;

    if (access == null || access.isEmpty) {
      setState(() => _status = '令牌换取未成功，请再登录一次');
      _oauthStarted = false;
      return;
    }

    if (mounted) {
      setState(() => _status = '校验余额接口…');
    }
    final ok = await sso.verifyQueryCard(access);
    if (!mounted || _done) return;

    if (!ok) {
      await session.clearNcardAccessToken();
      setState(() => _status = '授权未通过余额校验，请再登录一次');
      _oauthStarted = false;
      return;
    }

    // Optional UX: land on clean plat URL (no ticket) before pop.
    final c = _controller;
    if (c != null) {
      try {
        await c.loadUrl(
          urlRequest: URLRequest(url: WebUri(CampusUrls.ncardPlat)),
        );
      } on Object catch (error) {
        AppLogger.warn('ncard sync loadUrl plat 失败: $error');
      }
    }
    await _finishSuccess();
  }

  Future<void> _onUrl(Uri? uri) async {
    if (_done || uri == null) return;
    if (!uri.host.contains('ncard')) return;

    final ticket = NcardSso.ticketFromUri(uri);
    if (ticket != null) {
      // Prefer shouldOverrideUrlLoading path; this is a fallback if history
      // already updated without override (e.g. some Android WebView versions).
      unawaited(_startOauthFromTicket(ticket));
      return;
    }

    if (!_polling) {
      _startTokenPoll();
    }
  }

  void _startTokenPoll() {
    if (_polling || _done) return;
    _polling = true;
    final deadline = DateTime.now().add(_tokenPollWindow);
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_tokenPollInterval, (_) async {
      if (!mounted || _done) {
        _pollTimer?.cancel();
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        _pollTimer?.cancel();
        if (mounted && !_done) {
          setState(() => _status = '同步超时，可点完成后返回再重试');
        }
        return;
      }
      // Do not pop on storage token alone — must pass verifyQueryCard.
      if (_oauthStarted) return;
      final c = _controller;
      if (c == null) return;
      final token = await _readStorageToken(c);
      if (token == null || token.isEmpty) return;

      _oauthStarted = true;
      final session = ref.read(campusSessionProvider);
      await session.saveNcardAccessToken(token);
      AppLogger.info('ncard sync: storage token saved, verifying…');
      if (mounted) {
        setState(() => _status = '校验余额接口…');
      }
      final ok = await NcardSso(session).verifyQueryCard(token);
      if (!mounted || _done) return;
      if (!ok) {
        await session.clearNcardAccessToken();
        setState(() => _status = '授权未通过余额校验，请再登录一次');
        _oauthStarted = false;
        return;
      }
      AppLogger.info('ncard sync: storage token verified');
      await _finishSuccess();
    });
  }

  Future<String?> _readStorageToken(InAppWebViewController c) async {
    try {
      final result = await c.evaluateJavascript(
        source: '''
          (function() {
            const keys = ['access_token', 'accessToken', 'token'];
            for (const store of [sessionStorage, localStorage]) {
              try {
                for (const k of keys) {
                  let v = store.getItem(k);
                  if (!v || String(v).length < 8) continue;
                  v = String(v);
                  if (v.toLowerCase().startsWith('bearer ')) v = v.slice(7).trim();
                  return v;
                }
              } catch (e) {}
            }
            return '';
          })()
        ''',
      );
      final s = result?.toString() ?? '';
      if (s.isEmpty || s == 'null') return null;
      return s;
    } on Object {
      return null;
    }
  }

  Future<void> _finishSuccess() async {
    if (_done) return;
    _done = true;
    _pollTimer?.cancel();
    if (!mounted) return;
    setState(() => _status = '同步成功，即将返回…');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _popManual() {
    Navigator.of(context).pop(_done);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text('校园卡登录同步'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _popManual,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceLg,
              AppTokens.spaceMd,
              AppTokens.spaceLg,
              AppTokens.spaceSm,
            ),
            child: Row(
              children: [
                if (!_done)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (!_done) const SizedBox(width: AppTokens.spaceMd),
                Expanded(
                  child: Text(
                    _status,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest:
                  URLRequest(url: WebUri(CampusUrls.ncardCasRedirect)),
              initialUserScripts: _userScripts,
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
                mediaPlaybackRequiresUserGesture: true,
                userAgent: NcardMobileStealth.userAgent,
                preferredContentMode: UserPreferredContentMode.MOBILE,
                supportZoom: false,
                cacheEnabled: true,
                transparentBackground: false,
                useShouldOverrideUrlLoading: true,
              ),
              onWebViewCreated: (c) async {
                _controller = c;
                await _injectMobile(c);
              },
              onLoadStart: (c, url) async {
                await _injectMobile(c);
              },
              onLoadStop: (c, url) async {
                await _injectMobile(c);
                await _dismissMobileDialog(c);
                final uri = url == null ? null : Uri.tryParse(url.toString());
                await _maybeImportCookies(uri);
                // Ticket URLs should already be cancelled; only handle non-ticket.
                if (uri != null && NcardSso.ticketFromUri(uri) == null) {
                  await _onUrl(uri);
                }
              },
              onUpdateVisitedHistory: (c, url, isReload) async {
                final uri = url == null ? null : Uri.tryParse(url.toString());
                if (uri != null && NcardSso.ticketFromUri(uri) == null) {
                  await _onUrl(uri);
                }
              },
              shouldOverrideUrlLoading: (c, action) async {
                final req = action.request;
                final uri =
                    req.url == null ? null : Uri.tryParse(req.url.toString());
                if (uri == null) {
                  return NavigationActionPolicy.ALLOW;
                }

                // Allow normal CAS login navigations.
                if (uri.host.contains('login.xjtu.edu.cn')) {
                  return NavigationActionPolicy.ALLOW;
                }

                // ncard + ticket=: capture once, CANCEL so SPA soft-warm
                // cannot GET /plat/auth/synjones/oauth?ticket= and burn it.
                if (uri.host.contains('ncard') &&
                    uri.toString().contains('ticket=')) {
                  final ticket = NcardSso.ticketFromUri(uri);
                  if (ticket != null) {
                    unawaited(_startOauthFromTicket(ticket));
                  }
                  return NavigationActionPolicy.CANCEL;
                }

                return NavigationActionPolicy.ALLOW;
              },
              onReceivedError: (c, request, error) {
                final isMain = request.isForMainFrame ?? true;
                if (!isMain) return;
                AppLogger.warn('ncard sync 加载错误: ${error.description}');
                if (mounted && !_done) {
                  setState(() => _status = '页面加载异常，可完成后返回再重试');
                }
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _popManual,
                  child: const Text('完成后返回'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
