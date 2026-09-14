import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import 'auth_controller.dart';

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
  String? _status;

  Uri get _startUrl => Uri.parse(CampusUrls.casLoginYwtb);

  Future<void> _tryFinish(Uri uri) async {
    if (_finishing) return;
    final host = uri.host;
    final path = uri.path;
    // ignore unauthorized-service interstitial
    final leftCas =
        host != 'login.xjtu.edu.cn' || !path.contains('/cas/login');
    final landedCampus = host.endsWith('xjtu.edu.cn') &&
        (host.contains('ehall') ||
            host.contains('ywtb') ||
            host.contains('jwxt') ||
            host.contains('webvpn') ||
            host.contains('authx-service'));
    if (!leftCas && !landedCampus) return;

    final cookieManager = CookieManager.instance();
    final cookies = await cookieManager.getCookies(
      url: WebUri('https://login.xjtu.edu.cn/'),
    );
    final hasTgc = cookies.any(
      (c) =>
          c.name.toUpperCase().contains('TGC') ||
          c.name.toUpperCase().contains('CASTGC'),
    );
    if (!hasTgc && !landedCampus) return;

    _finishing = true;
    setState(() => _status = '正在导入登录会话…');
    try {
      // Also collect cookies for other campus hosts if present.
      final all = <Cookie>[...cookies];
      for (final origin in [
        'https://jwxt.xjtu.edu.cn/',
        'https://ehall.xjtu.edu.cn/',
        'https://ywtb.xjtu.edu.cn/',
        'https://webvpn.xjtu.edu.cn/',
      ]) {
        all.addAll(await cookieManager.getCookies(url: WebUri(origin)));
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.loginSuccess)),
      );
      context.go('/home');
    } on Object catch (e) {
      _finishing = false;
      if (!mounted) return;
      setState(() => _status = e.toString());
    }
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
                if (url != null) {
                  final uri = Uri.parse(url.toString());
                  final html = await controller.evaluateJavascript(
                    source: 'document.body ? document.body.innerText : ""',
                  );
                  final text = html?.toString() ?? '';
                  if (text.contains('未认证授权的服务') ||
                      text.contains('missing service')) {
                    setState(() => _status = '登录目标已纠正，正在重新打开一网通办认证…');
                    await controller.loadUrl(
                      urlRequest: URLRequest(url: WebUri(CampusUrls.casLoginYwtb)),
                    );
                    return;
                  }
                  await _tryFinish(uri);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
