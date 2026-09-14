import 'package:equatable/equatable.dart';

class CalendarEvent extends Equatable {
  const CalendarEvent({
    required this.name,
    required this.startDate,
    required this.endDate,
    this.remark = '',
  });

  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final String remark;

  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  @override
  List<Object?> get props => [name, startDate, endDate, remark];
}

class SchoolTermInfo extends Equatable {
  const SchoolTermInfo({
    required this.id,
    required this.label,
    required this.startDate,
    required this.endDate,
    this.yearLabel,
  });

  final String id;
  final String label;
  final DateTime startDate;
  final DateTime endDate;
  final String? yearLabel;

  bool contains(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  /// Teaching week: Mon of week containing term start = week 1.
  int teachingWeekOf(DateTime day) {
    final mondayOfStart = startDate.subtract(
      Duration(days: startDate.weekday - DateTime.monday),
    );
    final mondayOfDay = day.subtract(
      Duration(days: day.weekday - DateTime.monday),
    );
    final days = mondayOfDay.difference(mondayOfStart).inDays;
    final week = (days ~/ 7) + 1;
    if (week < 1) return 1;
    return week;
  }

  @override
  List<Object?> get props => [id, label, startDate, endDate];
}

class CalendarSnapshot {
  const CalendarSnapshot({
    required this.terms,
    required this.currentTerm,
    required this.events,
    required this.teachingWeek,
    required this.live,
    required this.banner,
    this.syncedWithScheduleWeek,
  });

  final List<SchoolTermInfo> terms;
  final SchoolTermInfo? currentTerm;
  final List<CalendarEvent> events;
  final int teachingWeek;
  final bool live;
  final String banner;

  /// When non-null, home/schedule ClassPeriod week was preferred.
  final int? syncedWithScheduleWeek;
}
