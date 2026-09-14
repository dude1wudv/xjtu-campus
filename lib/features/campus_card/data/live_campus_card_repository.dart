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
      await _softWarm();
      final bearer = await _exchangeSsoBearer();
      final headers = <String, String>{..._ncardHeaders};
      if (bearer != null && bearer.isNotEmpty) {
        headers['Synjones-Auth'] = 'bearer $bearer';
      }
      final cardResp = await _session.get(
        CampusUrls.ncardQueryCard,
        rewrite: false,
        headers: headers,
      );
      final cardJson = _session.tryJson(cardResp);
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
      AppLogger.info('校园卡路径成功: Dio');
      return CampusCardRawPayload(card: cardJson, turnover: turnJson);
    } on Object catch (error) {
      AppLogger.warn('Dio 校园卡失败: $error');
      return null;
    }
  }

  Future<void> _softWarm() async {
    for (final url in [
      CampusUrls.ncardPlat,
      CampusUrls.ncardCasRedirect,
    ]) {
      try {
        await _session.get(
          url,
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
  }

  /// CAS ticket on ncard redirect → H5 OAuth access (public platform client).
  Future<String?> _exchangeSsoBearer() async {
    try {
      final response = await _session.get(
        CampusUrls.ncardCasRedirect,
        rewrite: false,
        headers: {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'User-Agent': CampusUrls.ncardMobileUserAgent,
        },
      );
      final ticket = _ticketFrom(response.realUri) ??
          _ticketFromRedirects(response.redirects.map((r) => r.location));
      if (ticket == null || ticket.isEmpty) {
        AppLogger.warn('校园卡 SSO 未拿到 ticket');
        return null;
      }
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
      AppLogger.info('校园卡 SSO 已完成');
      return access;
    } on Object catch (error) {
      AppLogger.warn('校园卡 SSO 失败: $error');
      return null;
    }
  }

  String? _ticketFrom(Uri uri) {
    final ticket = uri.queryParameters['ticket'];
    if (ticket == null || ticket.isEmpty) return null;
    // Ticket is issued for ncard; host may be empty on relative redirect locations.
    if (uri.host.isEmpty || uri.host.contains('ncard')) return ticket;
    return null;
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
