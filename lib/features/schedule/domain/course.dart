import 'package:equatable/equatable.dart';

/// 交大常见 45 分钟小节，含课间。
class ClassPeriod extends Equatable {
  const ClassPeriod({
    required this.index,
    required this.start,
    required this.end,
  });

  final int index;
  final Duration start;
  final Duration end;

  String get label => '第$index节';

  String formatClock() => '${_clock(start)}–${_clock(end)}';

  static String _clock(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  static const catalog = [
    ClassPeriod(index: 1, start: Duration(hours: 8), end: Duration(hours: 8, minutes: 45)),
    ClassPeriod(index: 2, start: Duration(hours: 8, minutes: 55), end: Duration(hours: 9, minutes: 40)),
    ClassPeriod(index: 3, start: Duration(hours: 10, minutes: 10), end: Duration(hours: 10, minutes: 55)),
    ClassPeriod(index: 4, start: Duration(hours: 11, minutes: 5), end: Duration(hours: 11, minutes: 50)),
    ClassPeriod(index: 5, start: Duration(hours: 14), end: Duration(hours: 14, minutes: 45)),
    ClassPeriod(index: 6, start: Duration(hours: 14, minutes: 55), end: Duration(hours: 15, minutes: 40)),
    ClassPeriod(index: 7, start: Duration(hours: 16, minutes: 10), end: Duration(hours: 16, minutes: 55)),
    ClassPeriod(index: 8, start: Duration(hours: 17, minutes: 5), end: Duration(hours: 17, minutes: 50)),
    ClassPeriod(index: 9, start: Duration(hours: 19), end: Duration(hours: 19, minutes: 45)),
    ClassPeriod(index: 10, start: Duration(hours: 19, minutes: 55), end: Duration(hours: 20, minutes: 40)),
  ];

  static ClassPeriod byIndex(int index) =>
      catalog.firstWhere((period) => period.index == index);

  @override
  List<Object?> get props => [index, start, end];
}

class Course extends Equatable {
  const Course({
    required this.id,
    required this.name,
    required this.teacher,
    required this.campus,
    required this.building,
    required this.room,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeks,
    this.weeksLabel = '1-16周',
  });

  final String id;
  final String name;
  final String teacher;
  final String campus;
  final String building;
  final String room;
  final int weekday; // DateTime.monday = 1
  final int startPeriod;
  final int endPeriod;
  final List<int> weeks;
  final String weeksLabel;

  ClassPeriod get start => ClassPeriod.byIndex(startPeriod);
  ClassPeriod get end => ClassPeriod.byIndex(endPeriod);

  String get location => '$campus $building $room';

  String get periodLabel =>
      '第$startPeriod${startPeriod == endPeriod ? '' : '-$endPeriod'}节 ${start.formatClock().split('–').first}–${end.formatClock().split('–').last}';

  DateTime startAt(DateTime day) => DateTime(
    day.year,
    day.month,
    day.day,
  ).add(start.start);

  DateTime endAt(DateTime day) => DateTime(
    day.year,
    day.month,
    day.day,
  ).add(end.end);

  static Course? nextAfter(List<Course> courses, DateTime now) {
    Course? best;
    DateTime? bestStart;
    for (var offset = 0; offset < 8; offset++) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: offset));
      final ofDay =
          courses.where((course) => course.weekday == day.weekday).toList()
            ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
      for (final course in ofDay) {
        final start = course.startAt(day);
        if (start.isAfter(now) &&
            (bestStart == null || start.isBefore(bestStart))) {
          best = course;
          bestStart = start;
        }
      }
    }
    return best;
  }

  @override
  List<Object?> get props => [
    id,
    name,
    teacher,
    campus,
    building,
    room,
    weekday,
    startPeriod,
    endPeriod,
    weeks,
    weeksLabel,
  ];
}
