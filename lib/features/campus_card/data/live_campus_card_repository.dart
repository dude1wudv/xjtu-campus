import '../../../core/constants/campus_urls.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import '../domain/campus_card.dart';
import '../domain/campus_card_repository.dart';
import 'campus_card_mapper.dart';
import 'campus_card_webview_fetcher.dart';
import 'mock_campus_card_repository.dart';

/// 校园卡：未登录走演示；已登录优先 WebView Cookie，再 CAS ticket → H5 OAuth + Dio。
/// 已登录但接口失败时**不**回落演示数据（由 UI 展示错误与重试）。
class LiveCampusCardRepository implements CampusCardRepository {
  LiveCampusCardRepository({
    required this._session,
    required this._mock,
    CampusCardWebViewFetcher? webViewFetcher,
  }) : _webViewFetcher = webViewFetcher ?? CampusCardWebViewFetcher();

  final CampusSession _session;
  final MockCampusCardRepository _mock;
  final CampusCardWebViewFetcher _webViewFetcher;

  static const _ncardHeaders = {
    'Accept': 'application/json, text/plain, */*',
    'synAccessSource': 'h5',
    'User-Agent': CampusUrls.ncardMobileUserAgent,
    'Referer': CampusUrls.ncardPlat,
  };

  static const _redirectStatuses = {301, 302, 303, 307, 308};

  @override
  Future<CampusCardSnapshot> load() async {
    var loggedIn = false;
    try {
      loggedIn = await _session.hasCasCookie();
    } on Object {
      loggedIn = false;
    }
    if (!loggedIn) {
      return _mock.load();
    }
    try {
      final payload = await _fetchLive();
      if (payload == null || payload.card == null) {
        AppLogger.warn('校园卡接口未返回有效余额');
        return _failed();
      }
      final cardJson = payload.card!;
      if (!CampusCardMapper.looksOk(cardJson)) {
        AppLogger.warn('校园卡余额业务码异常');
        return _failed();
      }
      final card = CampusCardMapper.cardFromQuery(cardJson);
      if (card == null) {
        AppLogger.warn('校园卡余额无法解析');
        return _failed();
      }
      var transactions = const <CampusCardTransaction>[];
      int? total;
      final turn = payload.turnover;
      if (turn != null && CampusCardMapper.looksOk(turn)) {
        transactions = CampusCardMapper.transactionsFromTurnover(turn);
        total = CampusCardMapper.totalFromTurnover(turn);
      } else {
        AppLogger.warn('校园卡流水未同步，仍展示余额');
      }
      AppLogger.info(
        '校园卡拉取成功：流水 ${transactions.length} 条（不记录明细）',
      );
      return CampusCardSnapshot(
        card: card,
        transactions: transactions,
        live: true,
        banner: AppStrings.campusCardLiveBanner,
        totalCount: total,
      );
    } on Object catch (error) {
      AppLogger.warn('实时校园卡失败: $error');
      return _failed();
    }
  }

  CampusCardSnapshot _failed() {
    return const CampusCardSnapshot(
      card: null,
      transactions: [],
      live: false,
      failed: true,
      banner: AppStrings.campusCardSyncFailedBanner,
    );
  }

  Future<CampusCardRawPayload?> _fetchLive() async {
    try {
      final viaWebView = await _webViewFetcher.fetchRaw();
      if (viaWebView != null &&
          viaWebView.card != null &&
          CampusCardMapper.looksOk(viaWebView.card!)) {
        AppLogger.info('校园卡路径成功: HeadlessInAppWebView');
        return viaWebView;
      }
    } on Object catch (error) {
      AppLogger.warn('WebView 校园卡失败，回退 Dio: $error');
    }

    try {
      final viaStored = await _tryStoredBearer();
      if (viaStored != null) {
        AppLogger.info('校园卡路径成功: Dio(stored bearer)');
        return viaStored;
      }

      await _softWarm();
      final bearer = await _exchangeSsoBearer();
      final headers = _authHeaders(bearer);
      final payload = await _queryWithHeaders(headers);
      if (payload != null) {
        AppLogger.info('校园卡路径成功: Dio');
      }
      return payload;
    } on Object catch (error) {
      AppLogger.warn('Dio 校园卡失败: $error');
      return null;
    }
  }

  Map<String, String> _authHeaders(String? bearer) {
    final headers = <String, String>{..._ncardHeaders};
    if (bearer != null && bearer.isNotEmpty) {
      final value = 'bearer $bearer';
      headers['Synjones-Auth'] = value;
      headers['synjones-auth'] = value;
    }
    return headers;
  }

  Future<CampusCardRawPayload?> _tryStoredBearer() async {
    final stored = await _session.readNcardAccessToken();
    if (stored == null || stored.isEmpty) return null;
    final headers = _authHeaders(stored);
    final cardResp = await _session.get(
      CampusUrls.ncardQueryCard,
      rewrite: false,
      headers: headers,
    );
    final cardJson = _session.tryJson(cardResp);
    final code = cardJson?['code'];
    AppLogger.info('校园卡 queryCard code(stored): $code');
    if (cardJson == null) return null;
    if (_isUnauthorized(cardJson)) {
      AppLogger.warn('校园卡 stored bearer 401，清除并重新 SSO');
      await _session.clearNcardAccessToken();
      return null;
    }
    if (!CampusCardMapper.looksOk(cardJson)) return null;
    Map<String, dynamic>? turnJson;
    try {
      final range = _defaultTurnoverRange();
      final turnResp = await _session.get(
        CampusUrls.ncardTurnover,
        rewrite: false,
        query: {
          'size': 30,
          'current': 1,
          'timeFrom': range.$1,
          'timeTo': range.$2,
          'synAccessSource': 'h5',
        },
        headers: headers,
      );
      turnJson = _session.tryJson(turnResp);
    } on Object catch (error) {
      AppLogger.warn('Dio 校园卡流水失败(stored): $error');
    }
    return CampusCardRawPayload(card: cardJson, turnover: turnJson);
  }

  Future<CampusCardRawPayload?> _queryWithHeaders(
    Map<String, String> headers,
  ) async {
    final cardResp = await _session.get(
      CampusUrls.ncardQueryCard,
      rewrite: false,
      headers: headers,
    );
    final cardJson = _session.tryJson(cardResp);
    final code = cardJson?['code'];
    AppLogger.info('校园卡 queryCard code: $code');
    if (cardJson == null || !CampusCardMapper.looksOk(cardJson)) {
      AppLogger.warn('Dio 校园卡余额无效');
      return null;
    }
    Map<String, dynamic>? turnJson;
    try {
      final range = _defaultTurnoverRange();
      final turnResp = await _session.get(
        CampusUrls.ncardTurnover,
        rewrite: false,
        query: {
          'size': 30,
          'current': 1,
          'timeFrom': range.$1,
          'timeTo': range.$2,
          'synAccessSource': 'h5',
        },
        headers: headers,
      );
      turnJson = _session.tryJson(turnResp);
    } on Object catch (error) {
      AppLogger.warn('Dio 校园卡流水失败: $error');
    }
    return CampusCardRawPayload(card: cardJson, turnover: turnJson);
  }

  bool _isUnauthorized(Map<String, dynamic> json) {
    final code = json['code'];
    if (code == 401 || code?.toString() == '401') return true;
    final message = json['message']?.toString() ?? '';
    return message.contains('缺失令牌') || message.contains('鉴权失败');
  }

  Future<void> _softWarm() async {
    // Only warm /plat/. Do NOT hit ncardCasRedirect here — that would
    // consume the one-time CAS ticket before _exchangeSsoBearer can capture it.
    try {
      await _session.get(
        CampusUrls.ncardPlat,
        rewrite: false,
        headers: {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'User-Agent': CampusUrls.ncardMobileUserAgent,
          'Referer': CampusUrls.ywtbMain,
        },
      );
    } on Object catch (error) {
      AppLogger.warn('campus card soft-warm 失败: $error');
    }
  }

  /// CAS ticket on ncard redirect → H5 OAuth access (public platform client).
  ///
  /// Prefer a manual redirect walk so Dio does not consume the intermediate
  /// `ticket=` hop (final URL is often `/plat/` without the ticket).
  Future<String?> _exchangeSsoBearer() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        var ticket = await _captureTicketManual();
        ticket ??= await _captureTicketFollowed();
        if (ticket == null || ticket.isEmpty) {
          AppLogger.info(
            '校园卡 SSO ticket found: false (attempt ${attempt + 1})',
          );
          continue;
        }
        AppLogger.info(
          '校园卡 SSO ticket found: true (attempt ${attempt + 1})',
        );

        final access = await _oauthWithTicket(ticket);
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

  Future<String?> _captureTicketManual() async {
    var current = Uri.parse(CampusUrls.ncardCasRedirect);
    for (var hop = 0; hop < 16; hop++) {
      final fromCurrent = _ticketFrom(current);
      if (fromCurrent != null) return fromCurrent;

      final response = await _session.get(
        current.toString(),
        rewrite: false,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (status) => status != null && status < 500,
        headers: {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'User-Agent': CampusUrls.ncardMobileUserAgent,
        },
      );

      final fromReal = _ticketFrom(response.realUri);
      if (fromReal != null) return fromReal;

      final location = response.headers.value('location') ??
          response.headers.value('Location');
      if (location == null || location.isEmpty) {
        break;
      }
      final next = current.resolve(location);
      final fromLoc = _ticketFrom(next);
      if (fromLoc != null) return fromLoc;

      final status = response.statusCode ?? 0;
      if (!_redirectStatuses.contains(status)) {
        break;
      }
      // Stay on campus/CAS hosts only.
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

  Future<String?> _captureTicketFollowed() async {
    final response = await _session.get(
      CampusUrls.ncardCasRedirect,
      rewrite: false,
      followRedirects: true,
      maxRedirects: 12,
      headers: {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'User-Agent': CampusUrls.ncardMobileUserAgent,
      },
    );
    final fromFinal = _ticketFrom(response.realUri);
    if (fromFinal != null) return fromFinal;
    return _ticketFromRedirects(response.redirects.map((r) => r.location));
  }

  Future<String?> _oauthWithTicket(String ticket) async {
    final tokenResp = await _session.post(
      CampusUrls.ncardOAuthToken,
      rewrite: false,
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
        'User-Agent': CampusUrls.ncardMobileUserAgent,
        'Accept': 'application/json',
        'synAccessSource': 'h5',
      },
    );
    final json = _session.tryJson(tokenResp);
    final access = json?['access_token']?.toString();
    if (access == null || access.isEmpty) {
      AppLogger.warn('校园卡 SSO 换取会话失败');
      return null;
    }
    return access;
  }

  String? _ticketFrom(Uri uri) {
    final rawUrl = uri.toString();
    if (!rawUrl.contains('ticket=')) return null;
    // Ticket is issued for ncard; host may be empty on relative redirect locations.
    if (uri.host.isNotEmpty && !uri.host.contains('ncard')) return null;

    final fromParams = uri.queryParameters['ticket'];
    if (fromParams != null && fromParams.isNotEmpty) {
      return _decodeTicket(fromParams);
    }
    final match = RegExp(r'[?&]ticket=([^&#]*)').firstMatch(rawUrl);
    final raw = match?.group(1);
    if (raw == null || raw.isEmpty) return null;
    return _decodeTicket(raw);
  }

  String _decodeTicket(String raw) {
    try {
      return Uri.decodeComponent(raw);
    } on Object {
      return raw;
    }
  }

  String? _ticketFromRedirects(Iterable<Uri> locations) {
    for (final uri in locations) {
      final ticket = _ticketFrom(uri);
      if (ticket != null) return ticket;
    }
    return null;
  }

  (String, String) _defaultTurnoverRange() {
    final now = DateTime.now();
    final to = DateTime(now.year, now.month, now.day);
    final from = to.subtract(const Duration(days: 90));
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return (iso(from), iso(to));
  }
}
