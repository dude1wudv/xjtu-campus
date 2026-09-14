import 'course.dart';

class ScheduleSnapshot {
  const ScheduleSnapshot({
    required this.courses,
    required this.week,
    required this.live,
    required this.banner,
    this.termStart,
  });

  final List<Course> courses;
  final int week;
  final bool live;
  final String banner;
  final DateTime? termStart;
}

/// 课表数据源。登录后走 ehall / jwxt；失败或未登录回退演示数据。
abstract class ScheduleRepository {
  Future<int> currentWeek({DateTime? now});

  Future<List<Course>> fetchCourses();

  Future<ScheduleSnapshot> load({DateTime? now});
}
