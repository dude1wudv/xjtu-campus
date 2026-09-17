import 'dart:convert';

import '../../../core/constants/campus_urls.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import '../domain/course.dart';
import '../domain/schedule_repository.dart';
import 'jwxt_course_mapper.dart';
import 'mock_schedule_data.dart';
import 'mock_schedule_repository.dart';
import 'workflow_kebiao_mapper.dart';
import 'workflow_webview_schedule_fetcher.dart';

class LiveScheduleRepository implements ScheduleRepository {
  LiveScheduleRepository({
    required this._session,
    required this._mock,
    WorkflowWebViewScheduleFetcher? webViewFetcher,
  }) : _webViewFetcher = webViewFetcher ?? WorkflowWebViewScheduleFetcher(session: _session);

  final CampusSession _session;
  final MockScheduleRepository _mock;
  final WorkflowWebViewScheduleFetcher _webViewFetcher;

  @override
  Future<int> currentWeek({DateTime? now}) async {
    final snapshot = await load(now: now);
    return snapshot.week;
  }

  @override
  Future<List<Course>> fetchCourses() async => (await load()).courses;

  @override
  Future<ScheduleSnapshot> load({DateTime? now}) async {
    var loggedIn = false;
    try {
      loggedIn = await _session.hasCasCookie();
    } on Object {
      loggedIn = false;
    }
    if (!loggedIn) {
      return _demo(AppStrings.mockBanner);
    }
    try {
      final live = await _fetchLive(now ?? DateTime.now());
      if (live.courses.isEmpty) {
        AppLogger.warn('已登录但实时课表为空，回退演示数据：课表接口未同步成功，请重新网页登录；校外请开启 WebVPN');
        return await _demo(AppStrings.liveSyncFailedBanner);
      }
      return live;
    } on Object catch (error) {
      AppLogger.warn('实时课表失败，回退演示数据（课表接口未同步/校外请 WebVPN）: $error');
      return await _demo(AppStrings.liveSyncFailedBanner);
    }
  }

  Future<ScheduleSnapshot> _fetchLive(DateTime now) async {
    // 1) YWTB workflow undergraduate GET（浏览器实测路径）优先。
    try {
      final workflow = await _fetchWorkflow(now);
      if (workflow != null && workflow.courses.isNotEmpty) {
        return workflow;
      }
      if (workflow != null) {
        AppLogger.warn('workflow 课表为空或未能解析，回退 ehall/jwxt');
      }
    } on Object catch (error) {
      AppLogger.warn('workflow 课表请求失败，回退 ehall/jwxt: $error');
    }

    // 2) ehall / jwxt POST 旧路径。
    final hosts = [
      (
        term: CampusUrls.ehallCurrentTerm,
        table: CampusUrls.ehallSchedule,
        start: CampusUrls.ehallTermStart,
      ),
      (
        term: CampusUrls.jwxtCurrentTerm,
        table: CampusUrls.jwxtSchedule,
        start: CampusUrls.jwxtTermStart,
      ),
    ];

    Object? lastError;
    for (final host in hosts) {
      try {
        final termJson = _session.tryJson(
          await _session.post(
            host.term,
            headers: {
              'Accept': 'application/json, text/javascript, */*; q=0.01',
            },
          ),
        );
        final term = termJson?['datas']?['dqxnxq']?['rows']?[0]?['DM']
            ?.toString();
        if (term == null) continue;

        final tableJson = _session.tryJson(
          await _session.post(host.table, data: {'XNXQDM': term}),
        );
        final rows = tableJson?['datas']?['xskcb']?['rows'];
        if (rows is! List) continue;

        DateTime? termStart;
        final parts = term.split('-');
        if (parts.length >= 3) {
          final startJson = _session.tryJson(
            await _session.post(
              host.start,
              data: {'XN': '${parts[0]}-${parts[1]}', 'XQ': parts[2]},
            ),
          );
          final startText =
              startJson?['datas']?['cxjcs']?['rows']?[0]?['XQKSRQ']
                  ?.toString()
                  .split(' ')
                  .first;
          if (startText != null) {
            termStart = DateTime.tryParse(startText);
          }
        }

        final courses = JwxtCourseMapper.fromRows(rows);
        final week = _weekOf(now, termStart);
        return ScheduleSnapshot(
          courses: courses,
          week: week,
          live: true,
          banner: '实时课表 · $term',
          termStart: termStart,
        );
      } on Object catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? StateError('no schedule host');
  }

  Future<ScheduleSnapshot?> _fetchWorkflow(DateTime now) async {
    // 0) Headless WebView shares the CAS login cookie jar — try first on phone.
    try {
      final viaWebView = await _tryWorkflowWebView(now);
      if (viaWebView != null && viaWebView.courses.isNotEmpty) {
        AppLogger.info('workflow 课表路径成功: HeadlessInAppWebView');
        return viaWebView;
      }
      if (viaWebView != null) {
        AppLogger.warn('WebView workflow 课表为空或未能解析，回退 Dio');
      }
    } on Object catch (error) {
      AppLogger.warn('WebView workflow 课表失败，回退 Dio: $error');
    }

    return _tryWorkflowPath(now, rewrite: _session.useWebVpn);
  }

  Future<ScheduleSnapshot?> _tryWorkflowWebView(DateTime now) async {
    final range = _weekRangeMonSun(now);
    final start = _ymd(range.$1);
    final end = _ymd(range.$2);
    final raw = await _webViewFetcher.fetchUndergraduateKebiao(
      startDate: start,
      endDate: end,
    );
    if (raw == null || raw.trim().isEmpty) {
      AppLogger.warn('WebView getUndergraduateKebiao 响应为空');
      return null;
    }
    return _snapshotFromWorkflowRaw(raw, pathLabel: 'webview');
  }

  ScheduleSnapshot? _snapshotFromWorkflowRaw(
    String raw, {
    required String pathLabel,
  }) {
    if (_looksLikeLoginHtml(raw)) {
      AppLogger.warn(
        'getUndergraduateKebiao ($pathLabel) 返回登录页/HTML，而非 JSON；'
        '课表会话未同步，请重新网页登录或开启 WebVPN',
      );
      return ScheduleSnapshot(
        courses: const [],
        week: 1,
        live: true,
        banner: '实时课表 · workflow（未登录）',
      );
    }

    final decoded = _decodeJsonText(raw);
    if (decoded == null) {
      AppLogger.warn(
        'workflow 课表响应非 JSON ($pathLabel)（前 120 字: ${_preview(raw)}）',
      );
      return null;
    }

    if (decoded is Map) {
      final code = decoded['e'] ?? decoded['E'] ?? decoded['code'];
      if (code != null && code != 0 && code != '0') {
        AppLogger.warn('workflow 课表业务码异常 ($pathLabel): $code');
        return ScheduleSnapshot(
          courses: const [],
          week: 1,
          live: true,
          banner: '实时课表 · workflow（未授权或失败）',
        );
      }
    }

    final courses = WorkflowKebiaoMapper.fromJson(decoded);
    final term = WorkflowKebiaoMapper.termOf(decoded);
    final weekFromCourses = _weekHintFromCourses(courses);
    return ScheduleSnapshot(
      courses: courses,
      week: weekFromCourses ?? 1,
      live: true,
      banner: term == null ? '实时课表 · workflow' : '实时课表 · $term',
    );
  }

  /// Soft-warm + semester selector + undergraduate kebiao for one rewrite mode.
  Future<ScheduleSnapshot?> _tryWorkflowPath(
    DateTime now, {
    required bool rewrite,
  }) async {
    final pathLabel = rewrite ? 'webvpn' : 'direct';
    // Soft-warm: hit kebiao page (follow redirects) so TGC can establish SSO.
    try {
      final warm = await _session.get(
        CampusUrls.workflowKebiaoPage,
        rewrite: rewrite,
        headers: {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Referer': CampusUrls.ywtbMain,
        },
      );
      final warmText = _session.responseText(warm);
      final warmUri = warm.realUri.toString();
      if (_looksLikeLoginHtml(warmText) || warmUri.contains('/cas/login')) {
        AppLogger.warn(
          'soft-warm workflow 课表页($pathLabel)落到登录页，SSO 未建立（最终 URL: $warmUri）',
        );
      } else {
        AppLogger.info('soft-warm workflow 课表页($pathLabel)完成: $warmUri');
      }
    } on Object catch (error) {
      AppLogger.warn('soft-warm workflow 课表页($pathLabel)失败: $error');
    }

    final range = _weekRangeMonSun(now);
    final start = _ymd(range.$1);
    final end = _ymd(range.$2);

    // Soft-warm semester selector (same XHR order as browser).
    try {
      await _session.get(
        CampusUrls.workflowSelKxueqi,
        rewrite: rewrite,
        query: {'date': start},
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'Referer': CampusUrls.workflowKebiaoPage,
        },
      );
    } on Object {
      // Non-fatal; undergraduate endpoint may still work.
    }

    try {
      final response = await _session.get(
        CampusUrls.workflowUndergraduateKebiao,
        rewrite: rewrite,
        query: {'startDate': start, 'endDate': end},
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'Referer': CampusUrls.workflowKebiaoPage,
        },
      );

      final raw = _session.responseText(response);
      if (raw.trim().isEmpty) {
        AppLogger.warn('getUndergraduateKebiao ($pathLabel) 响应为空');
        return null;
      }
      if (_looksLikeLoginHtml(raw) ||
          response.realUri.toString().contains('/cas/login')) {
        AppLogger.warn(
          'getUndergraduateKebiao ($pathLabel) 返回登录页/HTML，而非 JSON；'
          '课表会话未同步，请重新网页登录或开启 WebVPN',
        );
        return ScheduleSnapshot(
          courses: const [],
          week: 1,
          live: true,
          banner: '实时课表 · workflow（未登录）',
        );
      }

      return _snapshotFromWorkflowRaw(raw, pathLabel: pathLabel);
    } on Object catch (error) {
      AppLogger.warn('workflow 课表请求失败 ($pathLabel): $error');
      return null;
    }
  }

  bool _looksLikeLoginHtml(String raw) {
    final trimmed = raw.trimLeft();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (!(lower.startsWith('<!doctype') ||
        lower.startsWith('<html') ||
        lower.contains('<body'))) {
      return false;
    }
    return lower.contains('cas/login') ||
        lower.contains('统一身份认证') ||
        lower.contains('login.xjtu.edu.cn') ||
        lower.contains('name="execution"') ||
        lower.contains('name=\'execution\'') ||
        lower.contains('passwordlogin') ||
        lower.contains('请输入密码');
  }

  Object? _decodeJsonText(String raw) {
    if (raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } on Object {
      return null;
    }
  }

  String _preview(String raw) {
    final oneLine = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= 120) return oneLine;
    return '${oneLine.substring(0, 120)}…';
  }

  /// Monday–Sunday of the calendar week containing [now].
  (DateTime, DateTime) _weekRangeMonSun(DateTime now) {
    final day = DateTime(now.year, now.month, now.day);
    final monday = day.subtract(Duration(days: day.weekday - DateTime.monday));
    final sunday = monday.add(const Duration(days: 6));
    return (monday, sunday);
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  int? _weekHintFromCourses(List<Course> courses) {
    for (final course in courses) {
      if (course.weeks.isNotEmpty) return course.weeks.first;
    }
    return null;
  }

  int _weekOf(DateTime now, DateTime? termStart) {
    if (termStart == null) return 1;
    final start = DateTime(termStart.year, termStart.month, termStart.day);
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(start).inDays;
    if (days < 0) return 1;
    return (days ~/ 7) + 1;
  }

  Future<ScheduleSnapshot> _demo(String banner) async {
    final courses = await _mock.fetchCourses();
    final week = await _mock.currentWeek();
    return ScheduleSnapshot(
      courses: courses,
      week: week,
      live: false,
      banner: banner,
      termStart: DateTime.tryParse(MockScheduleData.termStart),
    );
  }
}
