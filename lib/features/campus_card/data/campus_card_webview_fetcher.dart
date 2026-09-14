import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/logging/app_logger.dart';

/// Fetches ncard queryCard + turnover inside HeadlessInAppWebView.
///
/// Warm `/plat` (or CAS redirect) so the H5 SPA can complete SSO and stash
/// `access_token` in sessionStorage. Mobile UA is required by berserker H5.
class CampusCardWebViewFetcher {
  CampusCardWebViewFetcher({this.timeout = const Duration(seconds: 50)});

  final Duration timeout;

  Future<CampusCardRawPayload?> fetchRaw() async {
    final completer = Completer<CampusCardRawPayload?>();
    HeadlessInAppWebView? headless;
    Timer? timer;
    var finished = false;

    Future<void> complete(CampusCardRawPayload? value) async {
      if (finished) return;
      finished = true;
      timer?.cancel();
      try {
        await headless?.dispose();
      } on Object catch (error) {
        AppLogger.warn('CampusCard HeadlessInAppWebView dispose failed: $error');
      }
      if (!completer.isCompleted) completer.complete(value);
    }

    timer = Timer(timeout, () {
      AppLogger.warn('WebView 校园卡拉取超时 (${timeout.inSeconds}s)');
      unawaited(complete(null));
    });

    try {
      var fetchStarted = false;
      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(CampusUrls.ncardCasRedirect)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          thirdPartyCookiesEnabled: true,
          userAgent: CampusUrls.ncardMobileUserAgent,
          cacheEnabled: true,
        ),
        onLoadStop: (controller, url) async {
          if (finished) return;
          final uri = url == null ? null : Uri.tryParse(url.toString());
          if (uri != null && uri.host.contains('login')) {
            AppLogger.warn('WebView ncard 落到登录: ${uri.host}${uri.path}');
            await complete(null);
            return;
          }
          if (uri != null && !uri.host.contains('ncard')) {
            AppLogger.info(
              'WebView ncard 同步中，忽略非 ncard 页面: ${uri.host}${uri.path}',
            );
            return;
          }
          if (fetchStarted) return;
          fetchStarted = true;
          try {
            // Give the H5 SPA a beat to write sessionStorage after redirect.
            await Future<void>.delayed(const Duration(milliseconds: 800));
            if (finished) return;
            final result = await _runFetch(controller);
            await complete(result);
          } on Object catch (error) {
            AppLogger.warn('WebView evaluate/fetch 校园卡失败: $error');
            await complete(null);
          }
        },
        onReceivedError: (controller, request, error) {
          AppLogger.warn('WebView ncard 加载错误: ${error.description}');
        },
      );
      AppLogger.info('WebView 开始拉取校园卡');
      await headless.run();
    } on Object catch (error) {
      AppLogger.warn('CampusCard HeadlessInAppWebView 启动失败: $error');
      await complete(null);
    }

    return completer.future;
  }

  Future<CampusCardRawPayload?> _runFetch(
    InAppWebViewController controller,
  ) async {
    final cardUrl = CampusUrls.ncardQueryCard;
    final turnUrl = CampusUrls.ncardTurnover;
    final asyncResult = await controller.callAsyncJavaScript(
      functionBody: '''
        const headers = {
          'Accept': 'application/json, text/plain, */*',
          'synAccessSource': 'h5',
        };
        const token = sessionStorage.getItem('access_token')
          || localStorage.getItem('access_token')
          || '';
        if (token) {
          headers['synjones-auth'] = 'bearer ' + token;
        }
        const today = new Date();
        const pad = (n) => String(n).padStart(2, '0');
        const iso = (d) => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
        const timeTo = iso(today);
        const from = new Date(today.getTime() - 90 * 24 * 3600 * 1000);
        const timeFrom = iso(from);
        const turnQs = new URLSearchParams({
          size: '30',
          current: '1',
          timeFrom: timeFrom,
          timeTo: timeTo,
          synAccessSource: 'h5',
        });
        const parse = async (res) => {
          const text = await res.text();
          try { return JSON.parse(text); } catch (e) { return { _raw: String(text).slice(0, 200) }; }
        };
        const card = await parse(await fetch('$cardUrl', {
          method: 'GET',
          credentials: 'include',
          headers,
        }));
        const turnover = await parse(await fetch('$turnUrl?' + turnQs.toString(), {
          method: 'GET',
          credentials: 'include',
          headers,
        }));
        return { card, turnover };
      ''',
    );
    final value = asyncResult?.value;
    if (value is Map) {
      final map = value.map((k, v) => MapEntry(k.toString(), v));
      final card = _asJsonMap(map['card']);
      final turnover = _asJsonMap(map['turnover']);
      if (card == null && turnover == null) return null;
      if (card != null && card.containsKey('_raw')) {
        AppLogger.warn('WebView 校园卡余额返回非 JSON');
        return null;
      }
      AppLogger.info('WebView 校园卡 JSON 已解析（不记录明细）');
      return CampusCardRawPayload(card: card, turnover: turnover);
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          final map = decoded.map((k, v) => MapEntry(k.toString(), v));
          return CampusCardRawPayload(
            card: _asJsonMap(map['card']),
            turnover: _asJsonMap(map['turnover']),
          );
        }
      } on Object {
        return null;
      }
    }
    return null;
  }

  Map<String, dynamic>? _asJsonMap(Object? value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }
}

class CampusCardRawPayload {
  const CampusCardRawPayload({this.card, this.turnover});

  final Map<String, dynamic>? card;
  final Map<String, dynamic>? turnover;
}
