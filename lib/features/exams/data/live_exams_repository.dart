import '../../../core/constants/campus_urls.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import '../domain/exam_arrangement.dart';
import '../domain/exams_repository.dart';
import 'exams_mapper.dart';
import 'exams_webview_fetcher.dart';
import 'mock_exams_repository.dart';

class LiveExamsRepository implements ExamsRepository {
  LiveExamsRepository({
    required this._session,
    required this._mock,
    ExamsWebViewFetcher? webViewFetcher,
  }) : _webViewFetcher = webViewFetcher ?? ExamsWebViewFetcher();

  final CampusSession _session;
  final MockExamsRepository _mock;
  final ExamsWebViewFetcher _webViewFetcher;

  @override
  Future<ExamsSnapshot> load({String? termCode}) async {
    var loggedIn = false;
    try {
      loggedIn = await _session.hasCasCookie();
    } on Object {
      loggedIn = false;
    }
    if (!loggedIn) {
      return _mock.load(termCode: termCode);
    }
    try {
      final term = termCode ?? await _resolveTerm();
      if (term == null || term.isEmpty) {
        AppLogger.warn('考试安排：未能解析当前学期');
        return await _demo(AppStrings.examsSyncFailedBanner, termCode);
      }
      final json = await _fetchLiveJson(term);
      if (json == null) {
        return await _demo(AppStrings.examsSyncFailedBanner, term);
      }
      final exams = ExamsMapper.fromJson(json);
      AppLogger.info('考试安排拉取成功：${exams.length} 场（不记录明细）');
      return ExamsSnapshot(
        exams: exams,
        live: true,
        banner: AppStrings.liveBanner,
        termCode: term,
      );
    } on Object catch (error) {
      AppLogger.warn('实时考试安排失败，回退演示数据: $error');
      return _demo(AppStrings.examsSyncFailedBanner, termCode);
    }
  }

  Future<ExamsSnapshot> _demo(String banner, String? term) async {
    final demo = await _mock.load(termCode: term);
    return ExamsSnapshot(
      exams: demo.exams,
      live: false,
      banner: banner,
      termCode: term ?? demo.termCode,
    );
  }

  Future<String?> _resolveTerm() async {
    for (final rewrite in _rewriteModes()) {
      for (final url in [
        CampusUrls.jwxtCurrentTerm,
        CampusUrls.ehallCurrentTerm,
      ]) {
        try {
          if (rewrite) await _session.ensureWebVpnSession();
          final json = _session.tryJson(
            await _session.post(
              url,
              rewrite: rewrite,
              headers: {
                'Accept': 'application/json, text/javascript, */*; q=0.01',
              },
            ),
          );
          final term = json?['datas']?['dqxnxq']?['rows']?[0]?['DM']
              ?.toString();
          if (term != null && term.isNotEmpty) return term;
        } on Object catch (error) {
          AppLogger.warn('解析当前学期失败 ($url rewrite=$rewrite): $error');
        }
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _fetchLiveJson(String term) async {
    try {
      final viaWebView =
          await _webViewFetcher.fetchExamsJson(termCode: term);
      if (viaWebView != null && _looksOk(viaWebView)) {
        AppLogger.info('考试安排路径成功: HeadlessInAppWebView');
        return viaWebView;
      }
    } on Object catch (error) {
      AppLogger.warn('WebView 考试安排失败，回退 Dio: $error');
    }

    Object? last;
    for (final rewrite in _rewriteModes()) {
      try {
        await _softWarm(rewrite: rewrite);
        final response = await _session.post(
          CampusUrls.jwxtExams,
          data: {
            'XNXQDM': term,
            '*order': '-KSRQ,-KSSJMS',
          },
          rewrite: rewrite,
          headers: {
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': CampusUrls.jwxtWdksapIndex,
          },
        );
        final json = _session.tryJson(response);
        if (json != null && _looksOk(json)) {
          AppLogger.info('考试安排路径成功: Dio rewrite=$rewrite');
          return json;
        }
        last = StateError('exams json invalid');
      } on Object catch (e) {
        last = e;
        AppLogger.warn('Dio 考试安排失败 (rewrite=$rewrite): $e');
      }
    }
    if (last != null) throw last;
    return null;
  }

  bool _looksOk(Map<String, dynamic> json) {
    final code = json['code']?.toString();
    if (code != null && code != '0' && code != '200') return false;
    final datas = json['datas'];
    if (datas is Map && datas['wdksap'] != null) return true;
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
      CampusUrls.jwxtWdksapIndex,
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
        AppLogger.warn('exams soft-warm 失败: $error');
      }
    }
  }
}
