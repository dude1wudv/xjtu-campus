import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import 'ncard_mobile_stealth.dart';
import 'ncard_sso.dart';

/// Fetches ncard queryCard + turnover inside HeadlessInAppWebView.
///
/// Uses iPhone UA + mobile spoof. On `ticket=` URL, prefers Dart Dio OAuth
/// (not soft-warm GET `/plat/auth/synjones/oauth`).
class CampusCardWebViewFetcher {
  CampusCardWebViewFetcher({
    this.session,
    this.timeout = const Duration(seconds: 50),
  });

  final CampusSession? session;
  final Duration timeout;

  static const _tokenPollInterval = Duration(milliseconds: 500);
  static const _tokenPollWindow = Duration(seconds: 20);

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
      await _seedCookiesFromManager();

      var fetchStarted = false;
      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(CampusUrls.ncardCasRedirect)),
        initialUserScripts: UnmodifiableListView<UserScript>([
          UserScript(
            source: NcardMobileStealth.script,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          thirdPartyCookiesEnabled: true,
          userAgent: NcardMobileStealth.userAgent,
          preferredContentMode: UserPreferredContentMode.MOBILE,
          supportZoom: false,
          cacheEnabled: true,
        ),
        onLoadStop: (controller, url) async {
          if (finished) return;
          try {
            await controller.evaluateJavascript(
              source: NcardMobileStealth.script,
            );
            await controller.evaluateJavascript(
              source: NcardMobileStealth.dismissMobileDialogScript,
            );
          } on Object catch (error) {
            AppLogger.warn('WebView ncard mobile inject 失败: $error');
          }

          final uri = url == null ? null : Uri.tryParse(url.toString());
          if (uri != null && uri.host.contains('login')) {
            AppLogger.info(
              'WebView ncard CAS 跳转中: ${uri.host}${uri.path}',
            );
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
            final result = await _prepareAndFetch(controller, uri);
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

  Future<void> _seedCookiesFromManager() async {
    try {
      final manager = CookieManager.instance();
      final origins = [
        CampusUrls.ncardOrigin,
        CampusUrls.ncardPlat,
        'https://login.xjtu.edu.cn/',
        'https://ywtb.xjtu.edu.cn/',
      ];
      var count = 0;
      for (final origin in origins) {
        final cookies = await manager.getCookies(url: WebUri(origin));
        count += cookies.length;
      }
      AppLogger.info('WebView ncard CookieManager 相关 Cookie 条数: $count');
    } on Object catch (error) {
      AppLogger.warn('WebView ncard Cookie 预检失败: $error');
    }
  }

  Future<CampusCardRawPayload?> _prepareAndFetch(
    InAppWebViewController controller,
    Uri? uri,
  ) async {
    // Prefer Dart Dio oauth when ticket= is visible — skip SPA soft-warm GET.
    if (uri != null) {
      final ticket = NcardSso.ticketFromUri(uri);
      if (ticket != null) {
        final sess = session;
        if (sess != null) {
          final access = await NcardSso(sess).oauthAndSave(ticket);
          AppLogger.info('WebView Dart oauth from ticket: ${access != null}');
        } else {
          final exchanged = await _jsExchangeTicket(controller, ticket);
          AppLogger.info('WebView JS oauth from ticket: $exchanged');
        }
      }
    }

    final hasToken = await _pollAccessToken(controller);
    AppLogger.info('WebView sessionStorage access_token present: $hasToken');

    // If Dio saved a token but SPA storage is empty, inject for fetch headers.
    if (!hasToken && session != null) {
      final stored = await session!.readNcardAccessToken();
      if (stored != null && stored.isNotEmpty) {
        await _injectToken(controller, stored);
      }
    }

    return _runFetch(controller);
  }

  Future<void> _injectToken(
    InAppWebViewController controller,
    String token,
  ) async {
    final tokenJson = jsonEncode(token);
    try {
      await controller.evaluateJavascript(
        source: '''
          (function() {
            try {
              sessionStorage.setItem('access_token', $tokenJson);
              localStorage.setItem('access_token', $tokenJson);
            } catch (e) {}
          })();
        ''',
      );
    } on Object catch (error) {
      AppLogger.warn('WebView inject bearer 失败: $error');
    }
  }

  Future<bool> _jsExchangeTicket(
    InAppWebViewController controller,
    String ticket,
  ) async {
    final tokenUrl = CampusUrls.ncardOAuthToken;
    final basic = CampusUrls.ncardH5TokenBasicAuth;
    final ticketJson = jsonEncode(ticket);
    final basicJson = jsonEncode(basic);
    final tokenUrlJson = jsonEncode(tokenUrl);
    final result = await controller.callAsyncJavaScript(
      functionBody: '''
        const ticket = $ticketJson;
        const basic = $basicJson;
        const tokenUrl = $tokenUrlJson;
        const body = new URLSearchParams({
          username: ticket,
          password: ticket,
          grant_type: 'password',
          scope: 'all',
          loginFrom: 'h5',
          logintype: 'sso',
          device_token: 'h5',
          synAccessSource: 'h5',
        });
        const res = await fetch(tokenUrl, {
          method: 'POST',
          credentials: 'include',
          headers: {
            'Authorization': basic,
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
            'synAccessSource': 'h5',
          },
          body: body.toString(),
        });
        let json = null;
        try { json = await res.json(); } catch (e) { return false; }
        const access = json && json.access_token ? String(json.access_token) : '';
        if (!access) return false;
        try {
          sessionStorage.setItem('access_token', access);
          localStorage.setItem('access_token', access);
        } catch (e) {}
        return true;
      ''',
    );
    return result?.value == true;
  }

  Future<bool> _pollAccessToken(InAppWebViewController controller) async {
    final deadline = DateTime.now().add(_tokenPollWindow);
    var attempt = 0;
    while (DateTime.now().isBefore(deadline)) {
      attempt++;
      final present = await _hasAccessToken(controller);
      if (present) return true;
      if (attempt >= 12 && attempt % 4 == 0) {
        AppLogger.info('token poll #$attempt no token');
        try {
          await controller.evaluateJavascript(
            source: NcardMobileStealth.dismissMobileDialogScript,
          );
        } on Object {
          // ignore
        }
      }
      await Future<void>.delayed(_tokenPollInterval);
    }
    AppLogger.warn('_waitForToken timed out');
    return _hasAccessToken(controller);
  }

  Future<bool> _hasAccessToken(InAppWebViewController controller) async {
    try {
      final result = await controller.evaluateJavascript(
        source: '''
          (function() {
            const keys = [
              'access_token',
              'accessToken',
              'token',
              'Authorization',
              'Synjones-Auth',
            ];
            const stores = [sessionStorage, localStorage];
            for (const store of stores) {
              try {
                for (const k of keys) {
                  const v = store.getItem(k);
                  if (v && String(v).length > 8) return true;
                }
              } catch (e) {}
            }
            return false;
          })()
        ''',
      );
      return result == true || result?.toString() == 'true';
    } on Object {
      return false;
    }
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
        const pick = () => {
          const keys = [
            'access_token',
            'accessToken',
            'token',
          ];
          for (const store of [sessionStorage, localStorage]) {
            try {
              for (const k of keys) {
                const v = store.getItem(k);
                if (v && String(v).length > 8) return String(v);
              }
            } catch (e) {}
          }
          return '';
        };
        let token = pick();
        if (token.toLowerCase().startsWith('bearer ')) {
          token = token.slice(7).trim();
        }
        if (token) {
          const auth = 'bearer ' + token;
          headers['Synjones-Auth'] = auth;
          headers['synjones-auth'] = auth;
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
        return { card, turnover, hasToken: !!token };
      ''',
    );
    final value = asyncResult?.value;
    if (value is Map) {
      final map = value.map((k, v) => MapEntry(k.toString(), v));
      AppLogger.info('WebView fetch hasToken: ${map['hasToken'] == true}');
      final card = _asJsonMap(map['card']);
      final turnover = _asJsonMap(map['turnover']);
      if (card == null && turnover == null) return null;
      if (card != null && card.containsKey('_raw')) {
        AppLogger.warn('WebView 校园卡余额返回非 JSON');
        return null;
      }
      final code = card?['code'];
      AppLogger.info('WebView 校园卡 queryCard code: $code');
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
