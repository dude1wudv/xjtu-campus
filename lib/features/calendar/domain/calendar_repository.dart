import 'school_calendar.dart';

abstract class CalendarRepository {
  /// [scheduleWeek] optional teaching week from live schedule snapshot.
  Future<CalendarSnapshot> load({
    DateTime? now,
    int? scheduleWeek,
  });
}
