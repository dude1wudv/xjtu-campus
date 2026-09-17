import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/campus_urls.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/network/campus_connection.dart';
import '../../../core/network/webview_cookie_bridge.dart';
import '../../../core/network/webvpn_url.dart';
import '../../../core/widgets/app_page_scaffold.dart';
import '../data/attendance_repository.dart';
import 'attendance_providers.dart';

/// Complete the OAuth redirect inside one shared-cookie WebView. Do not start
/// from the attendance site's intermediate "正在完成登录" landing page.
class AttendanceLoginPage extends ConsumerStatefulWidget {
  const AttendanceLoginPage({super.key});
  @override
  ConsumerState<AttendanceLoginPage> createState() => _AttendanceLoginPageState();
}
class _AttendanceLoginPageState extends ConsumerState<AttendanceLoginPage> {
  InAppWebViewController? _controller;
  late final AttendanceSystem _system;
  Timer? _timer;
  bool _ready = false, _saving = false;
  String? _error;
  double _progress = 0;
  @override
  void initState() {
    super.initState();
    _system = ref.read(attendanceSystemProvider);
    Future.microtask(_prepare);
  }
  Future<void> _prepare() async {
    if (!mounted) return;
    ref.read(campusConnectionBusyProvider.notifier).setBusy(true);
    try {
      final session = ref.read(campusSessionProvider);
      await session.restore();
      await WebViewCookieBridge.seedOrigins(session: session, origins: {
        CampusUrls.casLogin, _system.loginUrl, session.resolveUrl(_system.loginUrl),
        session.resolveUrl(_system.origin), CampusUrls.webVpn,
      });
      if (mounted) { setState(() => _ready = true); _arm(); }
    } catch (_) { if (mounted) setState(() => _error = '登录页面准备失败，请重试'); }
  }
  void _arm() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 50), () {
      if (mounted && !_saving) setState(() => _error = '认证尚未完成。请完成页面中的登录；若一直停在跳转页，可重新发起授权。');
    });
  }
  Future<void> _capture(WebUri? value) async {
    if (!mounted || value == null || _saving) return;
    final uri = Uri.tryParse(value.toString());
    if (uri == null || !WebVpnUrl.matchesHost(uri, _system.host)) return;
    final token = AttendanceRepository.tokenFromUri(uri);
    if (token == null) return;
    _saving = true;
    _timer?.cancel();
    try {
      final session = ref.read(campusSessionProvider);
      await WebViewCookieBridge.importOrigins(session: session, origins: {
        uri.toString(), _system.origin, _system.loginUrl,
        '${_system.origin}/attendance-student/',
      });
      await session.saveAttendanceToken(_system.host, token);
      if (!mounted) return;
      context.pop(true);
    } catch (_) {
      _saving = false;
      if (mounted) setState(() => _error = '登录凭据保存失败，请重试');
    }
  }
  Future<void> _retry() async {
    setState(() { _error = null; _progress = 0; });
    if (!_ready) { await _prepare(); return; }
    _arm();
    final session = ref.read(campusSessionProvider);
    try {
      await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(_system.entryUrl(useWebVpn: session.useWebVpn))));
    } catch (_) { if (mounted) setState(() => _error = '无法打开认证页面，请检查网络后重试'); }
  }
  @override
  void dispose() {
    _timer?.cancel();
    final busy = ref.read(campusConnectionBusyProvider.notifier);
    Future.microtask(() => busy.setBusy(false));
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final session = ref.read(campusSessionProvider);
    return AppPageScaffold(appBar: AppBar(title: Text('${_system.label}考勤认证'), actions: [
      IconButton(tooltip: '重新授权', onPressed: _retry, icon: const Icon(Icons.refresh)),
    ]), body: Column(children: [
      if (_progress < 1) LinearProgressIndicator(value: _progress == 0 ? null : _progress),
      if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Text(_error!), TextButton(onPressed: _retry, child: const Text('重新发起授权')),
      ])),
      Expanded(child: !_ready ? const Center(child: CircularProgressIndicator()) : InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(_system.entryUrl(useWebVpn: session.useWebVpn))),
        initialSettings: InAppWebViewSettings(javaScriptEnabled: true, domStorageEnabled: true,
          thirdPartyCookiesEnabled: true, useShouldOverrideUrlLoading: true,
          userAgent: CampusUrls.userAgent),
        onWebViewCreated: (controller) => _controller = controller,
        shouldOverrideUrlLoading: (controller, action) async {
          if (action.isForMainFrame != false && action.request.url != null) {
            final raw = action.request.url.toString();
            final target = _system.navigationUrl(raw, useWebVpn: session.useWebVpn);
            if (target != raw) {
              await controller.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
              return NavigationActionPolicy.CANCEL;
            }
          }
          return NavigationActionPolicy.ALLOW;
        },
        onLoadStart: (_, url) => _capture(url),
        onUpdateVisitedHistory: (_, url, _) => _capture(url),
        onProgressChanged: (_, progress) { if (mounted) setState(() => _progress = progress / 100); },
        onLoadStop: (controller, url) async {
          await _capture(url);
          if (!mounted || _saving) return;
          try {
            final body = await controller.evaluateJavascript(source: "document.body ? document.body.innerText : ''");
            if (AttendanceConnectionFailed.isGatewayError('$body') && mounted) {
              setState(() => _error = '学校认证服务暂时无法连接，请稍后重试');
            }
          } catch (_) {}
        },
        onReceivedError: (_, request, _) {
          if (request.isForMainFrame != false && mounted) setState(() => _error = '认证页面连接失败，请重试');
        },
      )),
    ]));
  }
}
