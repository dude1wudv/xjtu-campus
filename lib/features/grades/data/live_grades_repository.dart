import '../../../core/constants/campus_urls.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import '../domain/grade_record.dart';
import '../domain/grades_repository.dart';
import 'grades_mapper.dart';
import 'grades_webview_fetcher.dart';
import 'mock_grades_repository.dart';

/// 成绩：WebView（共享网页登录 Cookie）优先，再 soft-warm + Dio jwxt。
class LiveGradesRepository implements GradesRepository {
  LiveGradesRepository({
    required this._session,
    required this._mock,
    GradesWebViewFetcher? webViewFetcher,
  }) : _webViewFetcher = webViewFetcher ?? GradesWebViewFetcher();

  final CampusSession _session;
  final MockGradesRepository _mock;
  final GradesWebViewFetcher _webViewFetcher;

  @override
  Future<GradesSnapshot> load() async {
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
      final json = await _fetchLiveJson();
      if (json == null) {
        AppLogger.warn('成绩接口未返回有效 JSON，回退演示数据');
        return await _demo(AppStrings.gradesSyncFailedBanner);
      }
      final snap = GradesMapper.fromJson(json);
      AppLogger.info('成绩拉取成功：${snap.records.length} 门课（不记录明细）');
      return GradesSnapshot(
        records: snap.records,
        live: true,
        banner: AppStrings.liveBanner,
        groupedByTerm: snap.groupedByTerm,
      );
    } on Object catch (error) {
      AppLogger.warn('实时成绩失败，回退演示数据: $error');
      return _demo(AppStrings.gradesSyncFailedBanner);
    }
  }

  Future<GradesSnapshot> _demo(String banner) async {
    final demo = await _mock.load();
    return GradesSnapshot(
      records: demo.records,
      live: false,
      banner: banner,
      groupedByTerm: demo.groupedByTerm,
    );
  }

  Future<Map<String, dynamic>?> _fetchLiveJson() async {
    try {
      final viaWebView = await _webViewFetcher.fetchGradesJson();
      if (viaWebView != null && _looksOk(viaWebView)) {
        AppLogger.info('成绩路径成功: HeadlessInAppWebView');
        return viaWebView;
      }
    } on Object catch (error) {
      AppLogger.warn('WebView 成绩失败，回退 Dio: $error');
    }

    Object? last;
    for (final rewrite in _rewriteModes()) {
      try {
        await _softWarm(rewrite: rewrite);
        final response = await _session.post(
          CampusUrls.jwxtGrades,
          data: {
            'pageSize': 500,
            'pageNumber': 1,
          },
          rewrite: rewrite,
          headers: {
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': CampusUrls.jwxtCjcxIndex,
          },
        );
        final json = _session.tryJson(response);
        if (json != null && _looksOk(json)) {
          AppLogger.info('成绩路径成功: Dio rewrite=$rewrite');
          return json;
        }
        last = StateError('grades json invalid');
      } on Object catch (e) {
        last = e;
        AppLogger.warn('Dio 成绩失败 (rewrite=$rewrite): $e');
      }
    }
    if (last != null) throw last;
    return null;
  }

  bool _looksOk(Map<String, dynamic> json) {
    final code = json['code']?.toString();
    if (code != null && code != '0' && code != '200') return false;
    final datas = json['datas'];
    if (datas is Map && datas['xscjcx'] != null) return true;
    // Accept empty-but-shaped responses.
    return code == '0';
  }

  List<bool> _rewriteModes() {
    if (_session.useWebVpn) return const [false, true];
    return const [false];
  }

  Future<void> _softWarm({required bool rewrite}) async {
    if (rewrite) await _session.ensureWebVpnSession();
    for (final url in [
      CampusUrls.jwxtHome,
      CampusUrls.jwxtCjcxIndex,
    ]) {
      try {
        await _session.get(
          url,
          rewrite: rewrite,
          headers: {
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Referer': CampusUrls.ywtbMain,
          },
        );
      } on Object catch (error) {
        AppLogger.warn('grades soft-warm 失败: $error');
      }
    }
  }
}
