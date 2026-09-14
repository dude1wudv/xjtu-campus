import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/logging/app_logger.dart';
import '../../classroom/presentation/classroom_page.dart';
import '../../notifications/presentation/dean_notices_webview_loader.dart';
import '../../notifications/presentation/notifications_page.dart';
import '../../schedule/presentation/schedule_providers.dart';
import 'auth_controller.dart';

/// Sync phases after CAS lands on a campus portal.
enum _SyncPhase { idle, workflow, jwxt }

/// 使用学校官方 CAS 网页登录，验证码 / MFA / 滑块都在官方页完成。
class CasWebLoginPage extends ConsumerStatefulWidget {
  const CasWebLoginPage({super.key, required this.studentId});

  final String studentId;

  @override
  ConsumerState<CasWebLoginPage> createState() => _CasWebLoginPageState();
}

class _CasWebLoginPageState extends ConsumerState<CasWebLoginPage> {
  InAppWebViewController? _controller;
  var _finishing = false;
  var _syncPhase = _SyncPhase.idle;
  String? _status;
  Timer? _syncTimeout;

  Uri get _startUrl => Uri.parse(CampusUrls.casLoginYwtb);

  bool _isCampusLanding(Uri uri) {
    final host = uri.host;
    return host.endsWith('xjtu.edu.cn') &&
        (host.contains('ehall') ||
            host.contains('ywtb') ||
            host.contains('jwxt') ||
            host.contains('webvpn') ||
            host.contains('workflow') ||
            host.contains('authx-service'));
  }

  bool _isWorkflowHost(Uri uri) => uri.host.contains('workflow');

  bool _isJwxtHost(Uri uri) => uri.host.contains('jwxt');

  Future<void> _tryFinish(Uri uri) async {
    if (_finishing || _syncPhase != _SyncPhase.idle) return;
    final host = uri.host;
    final path = uri.path;
    // ignore unauthorized-service interstitial
    final leftCas =
        host != 'login.xjtu.edu.cn' || !path.contains('/cas/login');
    final landedCampus = _isCampusLanding(uri);
    if (!leftCas && !landedCampus) return;

    final cookieManager = CookieManager.instance();
    final seed = await cookieManager.getCookies(
      url: WebUri('https://login.xjtu.edu.cn/'),
    );
    // 已落到一网通办/ehall 就继续；不要死等 TGC 名称。
    if (seed.isEmpty && !landedCampus) return;

    // 落到 ywtb/ehall 后先打开 workflow 课表页，再同步 jwxt 教室会话。
    if (landedCampus && !_isWorkflowHost(uri) && !_isJwxtHost(uri)) {
      await _beginWorkflowSync();
      return;
    }

    // 已在 workflow/jwxt，或异常路径：直接导入现有 Cookie。
    await _finishWithCookies(warnPartial: false);
  }

  Future<void> _beginWorkflowSync() async {
    if (_finishing || _syncPhase != _SyncPhase.idle) return;
    _syncPhase = _SyncPhase.workflow;
    setState(() => _status = '正在同步课表会话…');
    AppLogger.info('网页登录已落到校园门户，开始加载 workflow 课表页以同步会话');

    // Overall sync timeout (~20s) covers workflow + jwxt.
    _syncTimeout?.cancel();
    _syncTimeout = Timer(const Duration(seconds: 20), () async {
      if (_finishing || !mounted) return;
      AppLogger.warn('课表/教室会话同步超时，仍尝试导入现有 Cookie');
      if (mounted) {
        setState(() => _status = '会话同步超时，仍尝试导入登录…');
      }
      await _finishWithCookies(warnPartial: true);
    });

    try {
      final controller = _controller;
      if (controller == null) {
        AppLogger.warn('WebView 控制器为空，跳过 workflow 同步');
        await _finishWithCookies(warnPartial: true);
        return;
      }
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(CampusUrls.workflowKebiaoPage)),
      );
    } on Object catch (e) {
      AppLogger.warn('加载 workflow 课表页失败: $e');
      await _finishWithCookies(warnPartial: true);
    }
  }

  Future<void> _beginJwxtSync() async {
    if (_finishing || _syncPhase != _SyncPhase.workflow) return;
    _syncPhase = _SyncPhase.jwxt;
    if (mounted) {
      setState(() => _status = '正在同步教室会话…');
    }
    AppLogger.info('workflow 已同步，开始加载 jwxt kxjas 以同步教室会话');

    try {
      final controller = _controller;
      if (controller == null) {
        AppLogger.warn('WebView 控制器为空，跳过 jwxt 同步');
        await _finishWithCookies(warnPartial: true);
        return;
      }
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(CampusUrls.jwxtKxjasIndex)),
      );
    } on Object catch (e) {
      AppLogger.warn('加载 jwxt kxjas 失败: $e');
      await _finishWithCookies(warnPartial: true);
    }
  }

  Future<void> _onSyncLoadStop(Uri uri) async {
    if (_finishing) return;

    if (_syncPhase == _SyncPhase.workflow) {
      // Only advance after the workflow host itself loads.
      // ywtb/ehall onLoadStop can still fire after we kicked off loadUrl(workflow).
      if (!_isWorkflowHost(uri)) {
        AppLogger.info(
          '课表会话同步中，忽略非 workflow 页面: ${uri.host}${uri.path}',
        );
        return;
      }
      AppLogger.info('workflow 同步页加载完成: ${uri.host}${uri.path}');
      await _beginJwxtSync();
      return;
    }

    if (_syncPhase == _SyncPhase.jwxt) {
      // CAS may briefly appear during SSO; wait for jwxt host or overall timeout.
      if (_isJwxtHost(uri)) {
        AppLogger.info('jwxt 同步页加载完成: ${uri.host}${uri.path}');
        await _finishWithCookies(warnPartial: false);
        return;
      }
      if (uri.host.contains('login')) {
        AppLogger.info(
          '教室会话同步中，CAS 跳转中: ${uri.host}${uri.path}',
        );
        return;
      }
      AppLogger.info(
        '教室会话同步中，忽略非 jwxt 页面: ${uri.host}${uri.path}',
      );
    }
  }

  Future<void> _finishWithCookies({required bool warnPartial}) async {
    if (_finishing) return;
    _finishing = true;
    _syncPhase = _SyncPhase.idle;
    _syncTimeout?.cancel();
    _syncTimeout = null;

    if (warnPartial) {
      setState(() => _status = '课表/教室会话可能未完全同步，正在导入登录会话…');
    } else {
      setState(() => _status = '正在导入登录会话…');
    }

    try {
      final cookieManager = CookieManager.instance();
      final all = <Cookie>[];
      for (final origin in [
        'https://login.xjtu.edu.cn/cas/login',
        'https://login.xjtu.edu.cn/',
        'https://ywtb.xjtu.edu.cn/',
        'https://ywtb.xjtu.edu.cn/main.html',
        'https://ehall.xjtu.edu.cn/',
        'https://ehall.xjtu.edu.cn/new/index.html',
        'https://jwxt.xjtu.edu.cn/',
        CampusUrls.jwxtHome,
        CampusUrls.jwxtKxjasIndex,
        'https://authx-service.xjtu.edu.cn/',
        'https://webvpn.xjtu.edu.cn/',
        'https://workflow.xjtu.edu.cn/',
        CampusUrls.workflowKebiaoPage,
      ]) {
        all.addAll(await cookieManager.getCookies(url: WebUri(origin)));
      }
      // 去重
      final seen = <String>{};
      all.retainWhere((c) => seen.add('${c.domain}|${c.name}|${c.value}'));

      final hasWorkflowCookie = all.any(
        (c) => (c.domain ?? '').contains('workflow'),
      );
      final hasJwxtCookie = all.any(
        (c) => (c.domain ?? '').contains('jwxt'),
      );
      if (!hasWorkflowCookie) {
        AppLogger.warn(
          '导入前未采集到 workflow 域 Cookie；课表接口可能仍需重新网页登录或 WebVPN',
        );
      } else {
        AppLogger.info('已采集到 workflow 域 Cookie');
      }
      if (!hasJwxtCookie) {
        AppLogger.warn(
          '导入前未采集到 jwxt 域 Cookie；空闲教室可能仍需重新网页登录或 WebVPN',
        );
      } else {
        AppLogger.info('已采集到 jwxt 域 Cookie，准备 completeWebLogin');
      }

      final mapped = <({String name, String value, String? domain, String? path})>[
        for (final c in all)
          (
            name: c.name,
            value: c.value.toString(),
            domain: c.domain,
            path: c.path,
          ),
      ];

      final user = await ref.read(authRepositoryProvider).completeWebLogin(
            studentId: widget.studentId,
            cookies: mapped,
          );
      await ref.read(authControllerProvider.notifier).applyExternalLogin(user);
      ref.invalidate(scheduleSnapshotProvider);
      ref.read(liveDeanNoticesProvider.notifier).markLoading();
      ref.read(deanNoticesReloadTickProvider.notifier).bump();
      ref.invalidate(noticesFallbackProvider);
      ref.invalidate(freeClassroomsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.loginSuccess)),
      );
      context.go('/home');
    } on Object catch (e) {
      _finishing = false;
      _syncPhase = _SyncPhase.idle;
      if (!mounted) return;
      setState(() => _status = e.toString());
    }
  }

  @override
  void dispose() {
    _syncTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.webLoginTitle),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => _controller?.reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _status ?? AppStrings.webLoginHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_startUrl.toString())),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
                userAgent: CampusUrls.userAgent,
                useShouldOverrideUrlLoading: true,
              ),
              onWebViewCreated: (controller) => _controller = controller,
              shouldOverrideUrlLoading: (controller, action) async {
                final uri = action.request.url;
                if (uri != null) {
                  await _tryFinish(Uri.parse(uri.toString()));
                }
                return NavigationActionPolicy.ALLOW;
              },
              onLoadStop: (controller, url) async {
                if (url == null) return;
                final uri = Uri.parse(url.toString());
                final html = await controller.evaluateJavascript(
                  source: 'document.body ? document.body.innerText : ""',
                );
                final text = html?.toString() ?? '';
                if (text.contains('未认证授权的服务') ||
                    text.contains('missing service')) {
                  setState(() => _status = '登录目标已纠正，正在重新打开一网通办认证…');
                  await controller.loadUrl(
                    urlRequest:
                        URLRequest(url: WebUri(CampusUrls.casLoginYwtb)),
                  );
                  return;
                }
                if (_syncPhase != _SyncPhase.idle) {
                  await _onSyncLoadStop(uri);
                  return;
                }
                await _tryFinish(uri);
              },
            ),
          ),
        ],
      ),
    );
  }
}
