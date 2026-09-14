import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/logging/app_logger.dart';

class ExamsWebViewFetcher {
  ExamsWebViewFetcher({this.timeout = const Duration(seconds: 45)});

  final Duration timeout;

  Future<Map<String, dynamic>?> fetchExamsJson({required String termCode}) async {
    final completer = Completer<Map<String, dynamic>?>();
    HeadlessInAppWebView? headless;
    Timer? timer;
    var finished = false;

    Future<void> complete(Map<String, dynamic>? value) async {
      if (finished) return;
      finished = true;
      timer?.cancel();
      try {
        await headless?.dispose();
      } on Object catch (error) {
        AppLogger.warn('Exams HeadlessInAppWebView dispose failed: $error');
      }
      if (!completer.isCompleted) completer.complete(value);
    }

    timer = Timer(timeout, () {
      AppLogger.warn('WebView 考试安排拉取超时 (${timeout.inSeconds}s)');
      unawaited(complete(null));
    });

    try {
      var fetchStarted = false;
      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(CampusUrls.jwxtWdksapIndex)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          thirdPartyCookiesEnabled: true,
          userAgent: CampusUrls.userAgent,
          cacheEnabled: true,
        ),
        onLoadStop: (controller, url) async {
          if (fetchStarted || finished) return;
          final uri = url == null ? null : Uri.tryParse(url.toString());
          if (uri != null && uri.host.contains('login')) {
            AppLogger.warn('WebView wdksap 落到登录: ${uri.host}${uri.path}');
            await complete(null);
            return;
          }
          fetchStarted = true;
          try {
            final result = await _runFetch(controller, termCode);
            await complete(result);
          } on Object catch (error) {
            AppLogger.warn('WebView evaluate/fetch 考试安排失败: $error');
            await complete(null);
          }
        },
        onReceivedError: (controller, request, error) {
          AppLogger.warn('WebView wdksap 加载错误: ${error.description}');
        },
      );
      AppLogger.info('WebView 开始拉取考试安排');
      await headless.run();
    } on Object catch (error) {
      AppLogger.warn('Exams HeadlessInAppWebView 启动失败: $error');
      await complete(null);
    }

    return completer.future;
  }

  Future<Map<String, dynamic>?> _runFetch(
    InAppWebViewController controller,
    String termCode,
  ) async {
    final endpoint = CampusUrls.jwxtExams;
    final body =
        'XNXQDM=${Uri.encodeQueryComponent(termCode)}&*order=-KSRQ,-KSSJMS';
    final asyncResult = await controller.callAsyncJavaScript(
      functionBody: '''
        const postHeaders = {
          'Accept': 'application/json, text/javascript, */*; q=0.01',
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'X-Requested-With': 'XMLHttpRequest',
        };
        const res = await fetch('$endpoint', {
          method: 'POST',
          credentials: 'include',
          headers: postHeaders,
          body: '$body',
        });
        const text = await res.text();
        try { return JSON.parse(text); } catch (e) { return { _raw: text.slice(0, 200) }; }
      ''',
    );
    final value = asyncResult?.value;
    if (value is Map) {
      final map = value.map((k, v) => MapEntry(k.toString(), v));
      if (map.containsKey('_raw')) {
        AppLogger.warn('WebView 考试安排返回非 JSON');
        return null;
      }
      AppLogger.info('WebView 考试安排 JSON 已解析（不记录行内容）');
      return Map<String, dynamic>.from(map);
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
      } on Object {
        return null;
      }
    }
    return null;
  }
}
