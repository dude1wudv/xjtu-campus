import '../../../core/constants/campus_urls.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import '../domain/course.dart';
import '../domain/schedule_repository.dart';
import 'jwxt_course_mapper.dart';
import 'mock_schedule_data.dart';
import 'mock_schedule_repository.dart';

class LiveScheduleRepository implements ScheduleRepository {
  LiveScheduleRepository({
    required this._session,
    required this._mock,
  });

  final CampusSession _session;
  final MockScheduleRepository _mock;

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
        return await _demo(AppStrings.liveFallbackBanner);
      }
      return live;
    } on Object {
      AppLogger.warn('实时课表失败，回退演示数据（校外请使用 WebVPN）');
      return await _demo(AppStrings.liveFallbackBanner);
    }
  }

  Future<ScheduleSnapshot> _fetchLive(DateTime now) async {
    final hosts = [
      (
        term: CampusUrls.jwxtCurrentTerm,
        table: CampusUrls.jwxtSchedule,
        start: CampusUrls.jwxtTermStart,
      ),
      (
        term: CampusUrls.ehallCurrentTerm,
        table: CampusUrls.ehallSchedule,
        start: CampusUrls.ehallTermStart,
      ),
    ];

    Object? lastError;
    for (final host in hosts) {
      try {
        final termJson = _session.tryJson(
          await _session.post(
            host.term,
            headers: {'Accept': 'application/json, text/javascript, */*; q=0.01'},
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
