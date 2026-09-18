import 'course.dart';
import 'schedule_repository.dart';

DateTime mondayOf(DateTime date) => DateTime(
  date.year,
  date.month,
  date.day,
).subtract(Duration(days: date.weekday - 1));

int teachingWeek(ScheduleSnapshot data, DateTime day, DateTime now) {
  final anchor = data.termStart;
  return anchor == null
      ? data.week + mondayOf(day).difference(mondayOf(now)).inDays ~/ 7
      : 1 + mondayOf(day).difference(mondayOf(anchor)).inDays ~/ 7;
}

List<Course> coursesForDay(ScheduleSnapshot data, DateTime day, DateTime now) {
  if (data.currentWeekOnly &&
      mondayOf(day) != mondayOf(data.sourceMonday ?? data.cachedAt ?? now))
    return [];
  final week = teachingWeek(data, day, now);
  return data.courses
      .where(
        (c) =>
            c.weekday == day.weekday &&
            (c.weeks.isEmpty || c.weeks.contains(week)),
      )
      .toList()
    ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
}

/// Greedy interval lanes keep overlapping courses visible and tappable.
List<List<Course>> courseLanes(List<Course> courses) {
  final sorted = [...courses]
    ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
  final lanes = <List<Course>>[];
  for (final course in sorted) {
    final available = lanes.where(
      (lane) => lane.last.endPeriod < course.startPeriod,
    );
    if (available.isEmpty) {
      lanes.add([course]);
    } else {
      available.first.add(course);
    }
  }
  return lanes;
}

String courseRoute(Course course, DateTime day) => Uri(
  path: '/course',
  queryParameters: {
    'id': course.id,
    'day':
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
  },
).toString();
