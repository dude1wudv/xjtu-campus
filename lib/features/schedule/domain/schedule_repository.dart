import 'course.dart';

/// 课表数据源。后续由 ehall / 一网通办适配器实现。
abstract class ScheduleRepository {
  Future<int> currentWeek({DateTime? now});

  Future<List<Course>> fetchCourses();
}
