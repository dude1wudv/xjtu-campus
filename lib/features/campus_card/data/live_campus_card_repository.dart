import '../../../core/constants/campus_urls.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import '../domain/campus_card.dart';
import '../domain/campus_card_repository.dart';
import 'campus_card_mapper.dart';
import 'campus_card_webview_fetcher.dart';
import 'mock_campus_card_repository.dart';
import 'ncard_mobile_stealth.dart';
import 'ncard_sso.dart';

/// 校园卡：未登录走演示；已登录优先 WebView Cookie，再 CAS ticket → H5 OAuth + Dio。
/// 已登录但接口失败时**不**回落演示数据（由 UI 展示错误与重试）。
class LiveCampusCardRepository implements CampusCardRepository {
  LiveCampusCardRepository({
    required CampusSession session,
    required this._mock,
    CampusCardWebViewFetcher? webViewFetcher,
  })  : _session = session,
        _sso = NcardSso(session),
        _webViewFetcher = webViewFetcher ??
            CampusCardWebViewFetcher(session: session);

  final CampusSession _session;
  final MockCampusCardRepository _mock;
  final NcardSso _sso;
  final CampusCardWebViewFetcher _webViewFetcher;

  static const _ncardHeaders = {
    'Accept': 'application/json, text/plain, */*',
    'synAccessSource': 'h5',
    'User-Agent': NcardMobileStealth.userAgent,
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
      final viaStored = await _tryStoredBearer();
      if (viaStored != null) {
        AppLogger.info('校园卡路径成功: Dio(stored bearer)');
        return viaStored;
      }

      await _sso.softWarmPlat();
      final bearer = await _sso.exchangeSsoBearer();
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
