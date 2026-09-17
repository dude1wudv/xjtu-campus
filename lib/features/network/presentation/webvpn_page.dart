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
import '../../auth/presentation/auth_controller.dart';

/// Official interactive login. A protected JSON response, not a landing-page
/// URL or an arbitrary cookie, is required before reporting a connection.
class WebVpnPage extends ConsumerStatefulWidget {
  const WebVpnPage({super.key});

  @override
  ConsumerState<WebVpnPage> createState() => _WebVpnPageState();
}

class _WebVpnPageState extends ConsumerState<WebVpnPage> {
  final _studentId = TextEditingController();
  InAppWebViewController? _controller;
  Timer? _timeout;
  bool _checking = false;
  bool _verifying = false;
  bool _committed = false;
  String _status = '先在学校官方页面完成登录，再点击下方按钮连接。';

  @override
  void initState() {
    super.initState();
    _studentId.text = ref.read(authControllerProvider).user.studentId;
    Future.microtask(() {
      if (mounted) ref.read(campusConnectionBusyProvider.notifier).setBusy(true);
    });
  }

  Future<void> _connect() async {
    if (_checking || _controller == null) return;
    if (_studentId.text.trim().isEmpty) {
      setState(() => _status = '请填写学号，用于保存这次校园登录。');
      return;
    }
    setState(() {
      _checking = true;
      _status = '正在打开教务系统，确认 WebVPN 与校园登录状态…';
    });
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 60), () {
      if (mounted && !_committed && !_verifying) {
        setState(() {
          _checking = false;
          _status = '连接较慢或仍需认证，请完成网页中的登录后重试。';
        });
      }
    });
    try {
      await _controller!.loadUrl(urlRequest: URLRequest(
        url: WebUri(WebVpnUrl.convert(CampusUrls.jwxtWdkbIndex)),
      ));
    } catch (_) {
      if (mounted) setState(() {
        _checking = false;
        _status = '无法打开教务系统，请检查网络后重试。';
      });
    }
  }

  Future<void> _verify(InAppWebViewController controller, Uri uri) async {
    if (!_checking || _verifying || _committed ||
        !WebVpnUrl.isWebVpn(uri.toString()) ||
        !WebVpnUrl.matchesHost(uri, 'jwxt.xjtu.edu.cn')) return;
    _verifying = true;
    try {
      final result = await controller.callAsyncJavaScript(
        functionBody: '''
          const response = await fetch(endpoint, {
            method: 'POST', credentials: 'include',
            headers: {'Accept': 'application/json',
              'Content-Type': 'application/x-www-form-urlencoded'},
            body: ''
          });
          try {
            const data = await response.json();
            return response.ok && !!(data.datas && data.datas.dqxnxq);
          } catch (_) { return false; }
        ''',
        arguments: {'endpoint': WebVpnUrl.convert(CampusUrls.jwxtCurrentTerm)},
      ).timeout(const Duration(seconds: 35));
      if (!mounted) return;
      if (result?.value != true) {
        setState(() => _status = '尚未获得教务数据。请完成网页认证或切换学生身份后重试。');
        return;
      }
      final session = ref.read(campusSessionProvider);
      final origins = [
        CampusUrls.casLogin,
        CampusUrls.webVpn,
        uri.toString(),
        WebVpnUrl.convert(CampusUrls.workflowKebiaoPage),
        WebVpnUrl.convert(CampusUrls.jwxtHome),
        WebVpnUrl.convert(CampusUrls.ncardPlat),
        ...WebViewCookieBridge.libraryOrigins.map(WebVpnUrl.convert),
      ];
      await WebViewCookieBridge.importOrigins(session: session, origins: origins);
      if (!mounted) return;
      await session.setUseWebVpn(true);
      final auth = ref.read(authControllerProvider);
      if (!auth.isLoggedIn || auth.user.isDemo ||
          auth.user.studentId != _studentId.text.trim()) {
        // Importing has already persisted the browser cookies; read them using
        // the same bridge representation for the existing authentication API.
        final cookies = await WebViewCookieBridge.collectOrigins(origins);
        final user = await ref.read(authRepositoryProvider).completeWebLogin(
          studentId: _studentId.text.trim(), cookies: cookies,
        );
        if (!mounted) return;
        await ref.read(authControllerProvider.notifier).applyExternalLogin(user);
      }
      if (!mounted) return;
      _committed = true;
      ref.read(campusConnectionRevisionProvider.notifier).changed();
      ref.read(campusConnectionBusyProvider.notifier).setBusy(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebVPN 已连接，正在后台同步校园信息')),
      );
      context.go('/home');
    } catch (_) {
      if (mounted) setState(() => _status = '连接未完成，请检查网络并重试；已有缓存仍可使用。');
    } finally {
      _timeout?.cancel();
      _verifying = false;
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _studentId.dispose();
    // Schedule after the route's widget teardown; avoid modifying providers
    // synchronously while Flutter is disposing a subtree.
    final busy = ref.read(campusConnectionBusyProvider.notifier);
    Future.microtask(() => busy.setBusy(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('连接校园 WebVPN')),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text(_status),
              if (!auth.isLoggedIn || auth.user.isDemo) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _studentId,
                  enabled: !_checking,
                  decoration: const InputDecoration(labelText: '学号'),
                ),
              ],
            ]),
          ),
          if (_checking) const LinearProgressIndicator(),
          Expanded(child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(CampusUrls.webVpnLogin)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              thirdPartyCookiesEnabled: true,
              userAgent: CampusUrls.userAgent,
            ),
            onWebViewCreated: (controller) => _controller = controller,
            onLoadStop: (controller, url) async {
              if (url == null) return;
              final uri = Uri.parse(url.toString());
              if (!_checking && !_committed && _studentId.text.trim().isNotEmpty &&
                  uri.host == 'webvpn.xjtu.edu.cn' &&
                  (uri.path == '/' || uri.path == '/portal')) {
                await _connect();
                return;
              }
              await _verify(controller, uri);
            },
          )),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _checking ? null : _connect,
              icon: const Icon(Icons.vpn_lock_outlined),
              label: Text(_checking ? '正在连接…' : '已完成网页登录，连接并同步'),
            ),
          ),
        ]),
      ),
    );
  }
}
