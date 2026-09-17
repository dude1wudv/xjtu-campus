import 'dart:async';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
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
import '../data/attendance_diagnostics.dart';
import '../data/undergraduate_attendance_adapter.dart';
import 'attendance_diagnostics_sheet.dart';
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
  bool _portal = false;
  bool _useWebVpn = false;
  bool _diagnosticMode = false;
  bool _businessSessionSaved = false;
  CancelToken? _verificationToken;
  @override
  void initState() {
    super.initState();
    _system = ref.read(attendanceSystemProvider);
    _useWebVpn = _system.usesLegacyApi && ref.read(campusSessionProvider).useWebVpn;
    Future.microtask(_prepare);
  }
  Future<void> _prepare() async {
    if (!mounted) return;
    ref.read(campusConnectionBusyProvider.notifier).setBusy(true);
    try {
      final session = ref.read(campusSessionProvider);
      await session.restore();
      _useWebVpn = _system.usesLegacyApi ? session.useWebVpn
          : await session.undergraduateAttendanceUsesWebVpn();
      await WebViewCookieBridge.seedOrigins(session: session, origins: {
        CampusUrls.casLogin, _system.loginUrl, session.resolveUrl(_system.loginUrl),
        _system.origin, _system.workbenchUrl,
        if (!_system.usesLegacyApi) ...{
          '${_system.origin}/sa/',
          WebVpnUrl.maybeConvert('${_system.origin}/sa/', enabled: _useWebVpn),
          WebVpnUrl.maybeConvert(_system.loginUrl, enabled: _useWebVpn),
        },
        WebVpnUrl.maybeConvert(_system.origin, enabled: _useWebVpn), CampusUrls.webVpn,
      });
      if (mounted) { setState(() => _ready = true); _arm(); }
    } catch (_) { if (mounted) setState(() => _error = '登录页面准备失败，请重试'); }
  }
  void _arm() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 50), () {
      if (mounted && !_saving) {
        AttendanceDiagnostics.add('authentication-timeout');
        if (_controller != null) _recordPage(_controller!);
        setState(() => _error = '页面等待时间较长。若一直停在认证跳转页，可用系统浏览器从登录入口继续。');
      }
    });
  }
  Future<void> _recordPage(InAppWebViewController controller) async {
    if (!mounted || !_diagnosticMode) return;
    try {
      final url = await controller.getUrl();
      final uri = Uri.tryParse('$url');
      if (uri == null || !['login.xjtu.edu.cn', 'org.xjtu.edu.cn', 'kq.xjtu.edu.cn', _system.host]
          .any((host) => WebVpnUrl.matchesHost(uri, host))) return;
      // Read the document URL, classification and form routes in one JS turn.
      // WebView.getUrl may already point at the next navigation while the DOM
      // still belongs to the previous document. Discard such mixed snapshots.
      final page = await controller.evaluateJavascript(source: r"""
        (() => {
          if (document.readyState !== 'complete') return null;
          const text = document.body?.innerText || '';
          const kind = text.includes('404 Not Found') ? 'page-not-found'
            : document.querySelector('input[type="password"]') ? 'login-form'
            : text.includes('正在完成登录') ? 'login-redirect-wait' : 'page-loaded';
          return {url: location.href, kind,
            forms: kind === 'login-form' ? Array.from(document.forms).slice(0, 4)
              .map(f => ({action: f.action, method: f.method})) : []};
        })()
      """);
      if (page is! Map || page['url'] != url?.toString() ||
          (await controller.getUrl())?.toString() != page['url'] ||
          !mounted || !_diagnosticMode) return;
      const allowed = ['login-form', 'login-redirect-wait', 'page-not-found', 'page-loaded'];
      if (!allowed.contains(page['kind'])) return;
      AttendanceDiagnostics.add('${page['kind']}', url: url?.toString());
      if (page['forms'] case final List forms) {
        for (final form in forms.whereType<Map>()) {
          AttendanceDiagnostics.add('login-form-target', url: '${form['action'] ?? ''}',
            method: '${form['method'] ?? 'GET'}'.toUpperCase());
        }
      }
    } catch (_) { /* Diagnostics must not interrupt authentication. */ }
  }

  Future<void> _capture(WebUri? value) async {
    if (!mounted || value == null || _saving) return;
    if (!_system.usesLegacyApi) {
      await _captureBusinessSession(value);
      return;
    }
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
      AttendanceDiagnostics.add('token-saved', url: uri.toString());
      if (_diagnosticMode) {
        setState(() { _saving = false; _error = null; });
      } else {
        context.pop(true);
      }
    } catch (_) {
      _saving = false;
      if (mounted) setState(() => _error = '登录凭据保存失败，请重试');
    }
  }
  Future<void> _captureBusinessSession(WebUri value) async {
    final uri = Uri.tryParse(value.toString());
    if (_businessSessionSaved || uri == null ||
        uri.scheme != 'https' || !uri.path.endsWith('/studentpc/workbench') ||
        !WebVpnUrl.matchesHost(uri, _system.host) || _controller == null) return;
    _saving = true;
    final cancelToken = CancelToken();
    _verificationToken = cancelToken;
    var timedOut = false;
    final deadline = Timer(const Duration(seconds: 30), () {
      timedOut = true;
      cancelToken.cancel();
    });
    try {
      // Exact storage key from the public student frontend (module 4b1a).
      // This is an app session handoff, never part of diagnostics/export.
      final token = await _controller!.evaluateJavascript(source: r"""
        (() => {
          return localStorage.getItem('ATT_STUDENT_PC_BUSINESS_TOKEN') ||
            sessionStorage.getItem('ATT_STUDENT_PC_BUSINESS_TOKEN') || null;
        })()
      """);
      if (token is! String || token.isEmpty || token.length > 16384 ||
          token.contains(RegExp(r'[\r\n]'))) return;
      // Navigation may have moved while the script ran. Never accept a result
      // from a different document or from the general CAS login origin.
      if ((await _controller!.getUrl())?.toString() != value.toString() || !mounted) return;
      final session = ref.read(campusSessionProvider);
      await WebViewCookieBridge.importOrigins(session: session, origins: {
        '${_system.origin}/sa/',
        WebVpnUrl.maybeConvert('${_system.origin}/sa/', enabled: _useWebVpn),
      });
      await session.saveUndergraduateAttendanceToken(token);
      await session.setUndergraduateAttendanceWebVpn(_useWebVpn);
      await UndergraduateAttendanceAdapter(session, cancelToken).verifySession();
      if (cancelToken.isCancelled || !mounted) return;
      _businessSessionSaved = true;
      _timer?.cancel();
      AttendanceDiagnostics.add('business-session-saved', url: _system.origin);
      AttendanceDiagnostics.add('session-verified', url: _system.origin);
      if (!mounted) return;
      if (_diagnosticMode) {
        setState(() => _error = null);
      } else {
        context.pop(true);
      }
    } catch (error) {
      final failure = timedOut ? TimeoutException('考勤会话验证超时') : error;
      AttendanceDiagnostics.add(attendanceDiagnosticPhase(failure));
      if (mounted) setState(() => _error = attendanceErrorMessage(failure,
          useWebVpn: _useWebVpn));
    } finally {
      deadline.cancel();
      if (identical(_verificationToken, cancelToken)) _verificationToken = null;
      _saving = false;
    }
  }

  String _entry() {
    return _portal ? WebVpnUrl.maybeConvert(_system.workbenchUrl, enabled: _useWebVpn)
        : _system.entryUrl(useWebVpn: _useWebVpn);
  }
  Future<void> _openExternal({bool workbench = false}) async {
    final raw = workbench ? _system.workbenchUrl : _system.loginUrl;
    final url = WebVpnUrl.maybeConvert(raw, enabled: _useWebVpn);
    try {
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened && mounted) setState(() => _error = '无法打开系统浏览器，请检查是否安装浏览器');
    } catch (_) {
      if (mounted) setState(() => _error = '系统浏览器启动失败，请稍后重试');
    }
  }

  Future<void> _httpFailure(int status) async {
    if (!mounted || _saving) return;
    _timer?.cancel();
    // Preserve the failed document. Automatically opening another origin here
    // hides the original failure and can start a second authentication flow.
    setState(() { _progress = 1; _error = '认证页面返回 HTTP $status，登录尚未完成。可重试当前入口，或手动切换入口。'; });
  }
  Future<void> _retry() async {
    _verificationToken?.cancel();
    setState(() { _error = null; _progress = 0; _businessSessionSaved = false; });
    if (!_ready) { await _prepare(); return; }
    _arm();
    try {
      await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(_entry())));
    } catch (_) { if (mounted) setState(() => _error = '无法打开认证页面，请检查网络后重试'); }
  }
  @override
  void dispose() {
    _timer?.cancel();
    _verificationToken?.cancel();
    final busy = ref.read(campusConnectionBusyProvider.notifier);
    Future.microtask(() => busy.setBusy(false));
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(appBar: AppBar(title: Text('${_system.label}${_system.usesLegacyApi ? '考勤认证' : '考勤工作台'}'), actions: [
      IconButton(tooltip: '系统浏览器登录', onPressed: () => _openExternal(), icon: const Icon(Icons.open_in_browser)),
      IconButton(tooltip: '接口诊断', onPressed: () => showAttendanceDiagnostics(context), icon: const Icon(Icons.bug_report_outlined)),
      IconButton(tooltip: '重新授权', onPressed: _retry, icon: const Icon(Icons.refresh)),
    ]), body: Column(children: [
      if (!_system.usesLegacyApi) Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile.adaptive(contentPadding: EdgeInsets.zero,
            title: const Text('考勤使用 WebVPN'),
            subtitle: const Text('默认直连；只有直连无法访问时再开启'),
            value: _useWebVpn, onChanged: (value) async {
              setState(() { _useWebVpn = value; _portal = false; });
              await ref.read(campusSessionProvider).setUndergraduateAttendanceWebVpn(value);
              if (mounted) await _retry();
            }),
          Wrap(spacing: 8, children: [
            TextButton.icon(onPressed: () => _openExternal(), icon: const Icon(Icons.login),
              label: const Text('浏览器登录入口')),
            TextButton(onPressed: () => _openExternal(workbench: true), child: const Text('浏览器打开工作台')),
          ]),
          const Text('应用内同步请在下方完成登录。系统浏览器仅供独立查询，其登录状态不会自动同步到应用。'),
        ])),
      SwitchListTile(title: const Text('接口诊断模式'),
        subtitle: const Text('开启后在下方官方页面打开考勤记录或明细，再复制接口诊断。'),
        value: _diagnosticMode, onChanged: (value) async {
          setState(() { _diagnosticMode = value; _saving = false; _error = null; });
          AttendanceDiagnostics.add(value ? 'diagnostic-start' : 'diagnostic-stop');
          if (value && _controller != null) {
            try {
              await _controller!.evaluateJavascript(source: AttendanceDiagnostics.script);
              if (mounted && _controller != null) await _recordPage(_controller!);
            } catch (_) {
              AttendanceDiagnostics.add('script-injection-failed');
            }
          }
          if (mounted) _arm();
        }),
      if (_progress < 1) LinearProgressIndicator(value: _progress == 0 ? null : _progress),
      if (_businessSessionSaved) const Padding(
        padding: EdgeInsets.all(8),
        child: Text('考勤会话已确认，返回后同步明细；页面登录与明细同步分别检查。'),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Text(_error!),
        TextButton(onPressed: _retry, child: const Text('重新发起授权')),
        if (_system.usesLegacyApi) TextButton(onPressed: () { _portal = !_portal; _retry(); },
          child: Text(_portal ? '切换学校统一授权入口' : '切换考勤系统入口')),
      ])),
      Expanded(child: !_ready ? const Center(child: CircularProgressIndicator()) : InAppWebView(
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(source: AttendanceDiagnostics.script,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: false),
        ]),
        initialUrlRequest: URLRequest(url: WebUri(_entry())),
        initialSettings: InAppWebViewSettings(javaScriptEnabled: true, domStorageEnabled: true,
          thirdPartyCookiesEnabled: true, useShouldOverrideUrlLoading: true,
          userAgent: _system.usesLegacyApi ? CampusUrls.userAgent : null),
        onWebViewCreated: (controller) {
          _controller = controller;
          controller.addJavaScriptHandler(handlerName: 'attendanceTrace', callback: (args) async {
            final uri = Uri.tryParse('${await controller.getUrl()}');
            if (!_diagnosticMode || uri == null ||
                ![_system.host, if (!_system.usesLegacyApi) 'kq.xjtu.edu.cn']
                    .any((host) => WebVpnUrl.matchesHost(uri, host)) || args.isEmpty || args.first is! Map) return null;
            AttendanceDiagnostics.browser(args.first as Map);
            return true;
          });
          AttendanceDiagnostics.add('bridge-handler-registered');
        },
        shouldOverrideUrlLoading: (controller, action) async {
          if (action.isForMainFrame != false && action.request.url != null &&
              (action.request.method ?? 'GET').toUpperCase() == 'GET') {
            final raw = action.request.url.toString();
            final target = _system.navigationUrl(raw, useWebVpn: _useWebVpn);
            if (target != raw) {
              await controller.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
              return NavigationActionPolicy.CANCEL;
            }
          }
          return NavigationActionPolicy.ALLOW;
        },
        onLoadStart: (_, url) {
          AttendanceDiagnostics.add('navigation', url: url?.toString());
          if (_system.usesLegacyApi) _capture(url);
        },
        onUpdateVisitedHistory: (_, url, _) {
          if (url != null && WebVpnUrl.matchesHost(Uri.parse(url.toString()), _system.host) &&
              Uri.parse(url.toString()).path.endsWith('/studentpc/workbench')) {
            _timer?.cancel();
            if (mounted) setState(() => _error = null);
          }
          if (_diagnosticMode) AttendanceDiagnostics.add('history', url: url?.toString());
          _capture(url);
        },
        onProgressChanged: (_, progress) { if (mounted) setState(() => _progress = progress / 100); },
        onLoadStop: (controller, url) async {
          if (url != null && url.toString().split('?').first == _system.workbenchUrl) {
            _timer?.cancel();
          }
          // Idempotent fallback when document-start or the bridge was not ready.
          try {
            await controller.evaluateJavascript(source: AttendanceDiagnostics.script);
            if (_diagnosticMode) AttendanceDiagnostics.add('script-evaluated', url: url?.toString());
          } catch (_) {
            if (_diagnosticMode) AttendanceDiagnostics.add('script-injection-failed');
          }
          await _recordPage(controller);
          await _capture(url);
          if (!mounted || _saving) return;
          try {
            final body = await controller.evaluateJavascript(source: "document.body ? document.body.innerText : ''");
            if (AttendanceConnectionFailed.isGatewayError('$body') && mounted) {
              setState(() => _error = '学校认证服务暂时无法连接，请稍后重试');
            }
          } catch (_) {}
        },
        onReceivedHttpError: (controller, request, response) async {
          if ((response.statusCode ?? 0) < 400) return;
          final mainFrame = request.isForMainFrame;
          AttendanceDiagnostics.add(mainFrame == true ? 'page-http-error'
              : mainFrame == false ? 'resource-http-error' : 'unclassified-http-error',
            url: request.url.toString(), status: response.statusCode, method: request.method);
          // A missing frame flag is not evidence of a top-level failure.
          final currentUrl = mainFrame == null ? await controller.getUrl() : null;
          if (mainFrame == true || (mainFrame == null && currentUrl?.toString() == request.url.toString())) {
            if (!mounted || _saving) return;
            await _httpFailure(response.statusCode!);
          }
        },
        onReceivedError: (_, request, _) {
          if (request.isForMainFrame != false) AttendanceDiagnostics.add('page-network-error', url: request.url.toString());
          if (request.isForMainFrame != false && mounted) setState(() => _error = '认证页面连接失败，请重试');
        },
      )),
    ]));
  }
}
