import '../../../core/constants/campus_urls.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import '../../../core/network/webvpn_url.dart';
import 'ncard_mobile_stealth.dart';

/// Shared ncard CAS ticket → H5 OAuth bearer (Dio POST only).
///
/// Used by [LiveCampusCardRepository], [NcardSyncPage], and the headless
/// WebView fetcher. Never GETs `/plat/auth/synjones/oauth?ticket=` (401 path).
class NcardSso {
  NcardSso(this._session);

  final CampusSession _session;

  static const redirectStatuses = {301, 302, 303, 307, 308};

  static const mobileHeaders = {
    'Accept': 'application/json, text/plain, */*',
    'synAccessSource': 'h5',
    'User-Agent': NcardMobileStealth.userAgent,
    'Referer': CampusUrls.ncardPlat,
  };

  /// Extract `ticket=` from an ncard URL (never logs the value).
  static String? ticketFromUri(Uri uri) {
    final rawUrl = uri.toString();
    if (!rawUrl.contains('ticket=')) return null;
    if (uri.host.isNotEmpty && !WebVpnUrl.matchesHost(uri, 'ncard.xjtu.edu.cn')) return null;

    final fromParams = uri.queryParameters['ticket'];
    if (fromParams != null && fromParams.isNotEmpty) {
      return _decodeTicket(fromParams);
    }
    final match = RegExp(r'[?&]ticket=([^&#]*)').firstMatch(rawUrl);
    final raw = match?.group(1);
    if (raw == null || raw.isEmpty) return null;
    return _decodeTicket(raw);
  }

  static String? ticketFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    return ticketFromUri(uri);
  }

  static String _decodeTicket(String raw) {
    try {
      return Uri.decodeComponent(raw);
    } on Object {
      return raw;
    }
  }

  /// Pull `access_token` from top-level or nested `data` (never logs value).
  static String? accessTokenFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final top = json['access_token']?.toString();
    if (top != null && top.isNotEmpty) return top;
    final data = json['data'];
    if (data is Map) {
      final nested = data['access_token']?.toString();
      if (nested != null && nested.isNotEmpty) return nested;
    }
    return null;
  }

  /// Warm `/plat/` only — do not hit CAS redirect (consumes one-time ticket).
  Future<void> softWarmPlat() async {
    try {
      await _session.get(
        CampusUrls.ncardPlat,
        rewrite: true,
        headers: {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'User-Agent': NcardMobileStealth.userAgent,
          'Referer': CampusUrls.ywtbMain,
        },
      );
    } on Object catch (error) {
      AppLogger.warn('campus card soft-warm 失败: $error');
    }
  }

  /// Full SSO: capture ticket → POST oauth/token → save bearer.
  Future<String?> exchangeSsoBearer() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        var ticket = await captureTicketManual();
        ticket ??= await captureTicketFollowed();
        if (ticket == null || ticket.isEmpty) {
          AppLogger.info(
            '校园卡 SSO ticket found: false (attempt ${attempt + 1})',
          );
          continue;
        }
        AppLogger.info(
          '校园卡 SSO ticket found: true (attempt ${attempt + 1})',
        );

        final access = await oauthWithTicket(ticket);
        AppLogger.info('校园卡 SSO oauth ok: ${access != null}');
        if (access == null || access.isEmpty) continue;

        await _session.saveNcardAccessToken(access);
        AppLogger.info('校园卡 SSO 已完成');
        return access;
      } on Object catch (error) {
        AppLogger.warn('校园卡 SSO 失败 (attempt ${attempt + 1}): $error');
      }
    }
    return null;
  }

  /// Prefer Dart Dio oauth when a ticket URL is already known (WebView).
  Future<String?> oauthAndSave(String ticket) async {
    if (ticket.isEmpty) return null;
    AppLogger.info('校园卡 SSO ticket found: true (webview)');
    final access = await oauthWithTicket(ticket);
    AppLogger.info('校园卡 SSO oauth ok: ${access != null}');
    if (access == null || access.isEmpty) return null;
    await _session.saveNcardAccessToken(access);
    AppLogger.info('校园卡 SSO 已完成');
    return access;
  }

  Future<String?> captureTicketManual() async {
    var current = Uri.parse(CampusUrls.ncardCasRedirect);
    for (var hop = 0; hop < 16; hop++) {
      final fromCurrent = ticketFromUri(current);
      if (fromCurrent != null) return fromCurrent;

      final response = await _session.get(
        current.toString(),
        rewrite: true,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (status) => status != null && status < 500,
        headers: {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'User-Agent': NcardMobileStealth.userAgent,
        },
      );

      final fromReal = ticketFromUri(response.realUri);
      if (fromReal != null) return fromReal;

      final location = response.headers.value('location') ??
          response.headers.value('Location');
      if (location == null || location.isEmpty) {
        break;
      }
      final next = response.realUri.resolve(location);
      final fromLoc = ticketFromUri(next);
      if (fromLoc != null) return fromLoc;

      final status = response.statusCode ?? 0;
      if (!redirectStatuses.contains(status)) {
        break;
      }
      final host = next.host;
      if (host.isNotEmpty &&
          !host.endsWith('xjtu.edu.cn') &&
          !host.contains('ncard')) {
        AppLogger.warn('校园卡 SSO 手动跳转离开校园域: $host');
        break;
      }
      current = next;
    }
    return null;
  }

  Future<String?> captureTicketFollowed() async {
    final response = await _session.get(
      CampusUrls.ncardCasRedirect,
      rewrite: true,
      followRedirects: true,
      maxRedirects: 12,
      headers: {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'User-Agent': NcardMobileStealth.userAgent,
      },
    );
    final fromFinal = ticketFromUri(response.realUri);
    if (fromFinal != null) return fromFinal;
    for (final r in response.redirects) {
      final ticket = ticketFromUri(r.location);
      if (ticket != null) return ticket;
    }
    return null;
  }

  /// POST `/berserker-auth/oauth/token` only (XJTUToolBox path).
  ///
  /// Content-Type is form-urlencoded via [CampusSession.post] (`jsonBody: false`).
  Future<String?> oauthWithTicket(String ticket) async {
    final tokenResp = await _session.post(
      CampusUrls.ncardOAuthToken,
      rewrite: true,
      data: {
        'username': ticket,
        'password': ticket,
        'grant_type': 'password',
        'scope': 'all',
        'loginFrom': 'h5',
        'logintype': 'sso',
        'device_token': 'h5',
        'synAccessSource': 'h5',
      },
      headers: {
        'Authorization': CampusUrls.ncardH5TokenBasicAuth,
        'User-Agent': NcardMobileStealth.userAgent,
        'Accept': 'application/json',
        'synAccessSource': 'h5',
      },
    );
    final status = tokenResp.statusCode;
    final json = _session.tryJson(tokenResp);
    final hasTop = json != null && json.containsKey('access_token');
    final data = json?['data'];
    final hasNested = data is Map && data.containsKey('access_token');
    // Never log token values — only status + key presence.
    AppLogger.info(
      '校园卡 SSO oauth HTTP $status access_token key: top=$hasTop nested=$hasNested',
    );

    final access = accessTokenFromJson(json);
    if (access == null || access.isEmpty) {
      AppLogger.warn('校园卡 SSO 换取会话失败');
      return null;
    }
    return access;
  }

  /// Optional verify after save: queryCard with bearer.
  Future<bool> verifyQueryCard(String bearer) async {
    try {
      final value = 'bearer $bearer';
      final resp = await _session.get(
        CampusUrls.ncardQueryCard,
        rewrite: true,
        headers: {
          ...mobileHeaders,
          'Synjones-Auth': value,
          'synjones-auth': value,
        },
      );
      final json = _session.tryJson(resp);
      final code = json?['code'];
      AppLogger.info('校园卡 sync verify queryCard code: $code');
      return code == 200 || code?.toString() == '200';
    } on Object catch (error) {
      AppLogger.warn('校园卡 sync verify 失败: $error');
      return false;
    }
  }
}
