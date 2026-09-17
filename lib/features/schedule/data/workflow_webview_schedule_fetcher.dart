import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import '../../../core/network/webview_cookie_bridge.dart';
import '../../../core/network/webvpn_url.dart';

/// Fetches undergraduate kebiao JSON inside a [HeadlessInAppWebView] so the
/// request shares the same cookie jar as CAS web login (unlike Dio on phone).
class WorkflowWebViewScheduleFetcher {
  WorkflowWebViewScheduleFetcher({this.session, this.timeout = const Duration(seconds: 20)});

  final Duration timeout;
  final CampusSession? session;

  String _url(String url) => session?.resolveUrl(url) ?? url;

  /// Returns the raw response body (JSON text), or `null` on timeout / error.
  Future<String?> fetchUndergraduateKebiao({
    required String startDate,
    required String endDate,
  }) async {
    final completer = Completer<String?>();
    HeadlessInAppWebView? headless;
    Timer? timer;
    var finished = false;

    Future<void> complete(String? value) async {
      if (finished) return;
      finished = true;
      timer?.cancel();
      try {
        await headless?.dispose();
      } on Object catch (error) {
        AppLogger.warn('HeadlessInAppWebView dispose failed: $error');
      }
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    }

    timer = Timer(timeout, () {
      AppLogger.warn('WebView workflow 课表拉取超时 (${timeout.inSeconds}s)');
      unawaited(complete(null));
    });

    try {
      var fetchStarted = false;
      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(_url(CampusUrls.workflowKebiaoPage)),
        ),
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
          if (uri != null && WebVpnUrl.isLoginPage(uri)) {
            AppLogger.warn('WebView workflow 课表页落到登录: ${uri.host}${uri.path}');
            await complete(null);
            return;
          }
          fetchStarted = true;
          try {
            final raw = await _runFetch(
              controller,
              startDate: startDate,
              endDate: endDate,
            );
            await complete(raw);
          } on Object catch (error) {
            AppLogger.warn('WebView evaluate/fetch 课表失败: $error');
            await complete(null);
          }
        },
        onReceivedError: (controller, request, error) {
          AppLogger.warn('WebView workflow 加载错误: ${error.description}');
        },
        onReceivedHttpError: (controller, request, response) {
          AppLogger.warn(
            'WebView workflow HTTP ${response.statusCode} ${request.url}',
          );
        },
      );

      AppLogger.info('WebView 开始拉取 workflow 课表 $startDate~$endDate');
      final activeSession = session;
      if (activeSession != null) {
        await WebViewCookieBridge.seedOrigins(
          session: activeSession,
          origins: [CampusUrls.casLogin, _url(CampusUrls.workflowKebiaoPage)],
        );
      }
      if (!finished) await headless.run();
    } on Object catch (error) {
      AppLogger.warn('HeadlessInAppWebView 启动失败: $error');
      await complete(null);
    }

    return completer.future;
  }

  Future<String?> _runFetch(
    InAppWebViewController controller, {
    required String startDate,
    required String endDate,
  }) async {
    // Prefer callAsyncJavaScript so the Promise from fetch is awaited.
    try {
      final asyncResult = await controller.callAsyncJavaScript(
        functionBody: '''
          try {
            await fetch(
              '${_url(CampusUrls.workflowSelKxueqi)}?date=' +
                encodeURIComponent(startDate),
              {
                credentials: 'include',
                headers: { 'Accept': 'application/json, text/plain, */*' },
              }
            );
          } catch (e) {}
          const url =
            '${_url(CampusUrls.workflowUndergraduateKebiao)}?startDate=' +
            encodeURIComponent(startDate) +
            '&endDate=' +
            encodeURIComponent(endDate);
          const response = await fetch(url, {
            credentials: 'include',
            headers: { 'Accept': 'application/json, text/plain, */*' },
          });
          return await response.text();
        ''',
        arguments: {'startDate': startDate, 'endDate': endDate},
      );
      if (asyncResult?.error != null &&
          asyncResult!.error.toString().trim().isNotEmpty) {
        AppLogger.warn('callAsyncJavaScript error: ${asyncResult.error}');
      } else {
        final value = asyncResult?.value;
        if (value is String && value.trim().isNotEmpty) {
          AppLogger.info('WebView callAsyncJavaScript 课表成功（${value.length} 字）');
          return value;
        }
        if (value != null) {
          final text = value.toString();
          if (text.trim().isNotEmpty && text != 'null') {
            return text;
          }
        }
      }
    } on Object catch (error) {
      AppLogger.warn('callAsyncJavaScript 不可用，回退 evaluateJavascript: $error');
    }

    // Fallback: evaluateJavascript with then-chain (user-requested pattern).
    final qStart = jsonQuote(startDate);
    final qEnd = jsonQuote(endDate);
    final source =
        '''
(function(){
  var startDate = $qStart;
  var endDate = $qEnd;
  var absBase = '${_url(CampusUrls.workflow).replaceFirst(RegExp(r'/$'), '')}';
  return fetch(absBase + '/selectpage/site/kebiao/selkxueqi?date=' + encodeURIComponent(startDate), {
    credentials: 'include',
    headers: { 'Accept': 'application/json, text/plain, */*' }
  }).catch(function(){ return null; }).then(function(){
    return fetch(absBase + '/selectpage/site/newkebiao/getUndergraduateKebiao?startDate=' + encodeURIComponent(startDate) + '&endDate=' + encodeURIComponent(endDate), {
      credentials: 'include',
      headers: { 'Accept': 'application/json, text/plain, */*' }
    });
  }).then(function(r){ return r.text(); });
})()
''';
    final evaluated = await controller.evaluateJavascript(source: source);
    if (evaluated == null) return null;
    final text = evaluated.toString();
    if (text.trim().isEmpty ||
        text == 'null' ||
        text.contains('[object Promise]')) {
      AppLogger.warn('evaluateJavascript 未得到课表 JSON（${_preview(text)}）');
      return null;
    }
    AppLogger.info('WebView evaluateJavascript 课表成功（${text.length} 字）');
    return text;
  }

  static String jsonQuote(String value) =>
      "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

  static String _preview(String raw) {
    final oneLine = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= 80) return oneLine;
    return '${oneLine.substring(0, 80)}…';
  }
}
