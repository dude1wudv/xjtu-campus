import '../../schedule/domain/course.dart';
import 'school_calendar.dart';

/// Classification / helpers for month-grid day cells.
DateTime calendarDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whether [course] meets on [day] given term teaching week (ZC).
bool courseMeetsOnDay(
  Course course,
  DateTime day, {
  SchoolTermInfo? term,
  int? fallbackWeek,
}) {
  if (course.weekday != day.weekday) return false;
  if (course.weeks.isEmpty) return true;
  final week = term != null
      ? term.teachingWeekOf(day)
      : fallbackWeek;
  if (week == null) return true;
  return course.weeks.contains(week);
}

/// Courses that meet on [day].
List<Course> coursesOnDay(
  List<Course> courses,
  DateTime day, {
  SchoolTermInfo? term,
  int? fallbackWeek,
}) {
  final list = courses
      .where(
        (c) => courseMeetsOnDay(
          c,
          day,
          term: term,
          fallbackWeek: fallbackWeek,
        ),
      )
      .toList()
    ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
  return list;
}

bool dayHasClass(
  List<Course> courses,
  DateTime day, {
  SchoolTermInfo? term,
  int? fallbackWeek,
}) =>
    coursesOnDay(
      courses,
      day,
      term: term,
      fallbackWeek: fallbackWeek,
    ).isNotEmpty;

/// Hardcoded China public holidays that commonly overlap academic terms (2025–2027).
final List<(DateTime, String)> kChinaPublicHolidays2025to2027 = [
  // 2025
  (DateTime(2025, 1, 1), '元旦'),
  (DateTime(2025, 1, 28), '春节'),
  (DateTime(2025, 1, 29), '春节'),
  (DateTime(2025, 1, 30), '春节'),
  (DateTime(2025, 1, 31), '春节'),
  (DateTime(2025, 2, 1), '春节'),
  (DateTime(2025, 2, 2), '春节'),
  (DateTime(2025, 2, 3), '春节'),
  (DateTime(2025, 2, 4), '春节'),
  (DateTime(2025, 5, 1), '劳动节'),
  (DateTime(2025, 5, 2), '劳动节'),
  (DateTime(2025, 5, 3), '劳动节'),
  (DateTime(2025, 5, 4), '劳动节'),
  (DateTime(2025, 5, 5), '劳动节'),
  (DateTime(2025, 10, 1), '国庆'),
  (DateTime(2025, 10, 2), '国庆'),
  (DateTime(2025, 10, 3), '国庆'),
  (DateTime(2025, 10, 4), '国庆'),
  (DateTime(2025, 10, 5), '国庆'),
  (DateTime(2025, 10, 6), '中秋'),
  (DateTime(2025, 10, 7), '国庆'),
  (DateTime(2025, 10, 8), '国庆'),
  // 2026
  (DateTime(2026, 1, 1), '元旦'),
  (DateTime(2026, 1, 2), '元旦'),
  (DateTime(2026, 1, 3), '元旦'),
  (DateTime(2026, 2, 15), '春节'),
  (DateTime(2026, 2, 16), '春节'),
  (DateTime(2026, 2, 17), '春节'),
  (DateTime(2026, 2, 18), '春节'),
  (DateTime(2026, 2, 19), '春节'),
  (DateTime(2026, 2, 20), '春节'),
  (DateTime(2026, 2, 21), '春节'),
  (DateTime(2026, 2, 22), '春节'),
  (DateTime(2026, 2, 23), '春节'),
  (DateTime(2026, 5, 1), '劳动节'),
  (DateTime(2026, 5, 2), '劳动节'),
  (DateTime(2026, 5, 3), '劳动节'),
  (DateTime(2026, 5, 4), '劳动节'),
  (DateTime(2026, 5, 5), '劳动节'),
  (DateTime(2026, 9, 25), '中秋'),
  (DateTime(2026, 9, 26), '中秋'),
  (DateTime(2026, 9, 27), '中秋'),
  (DateTime(2026, 10, 1), '国庆'),
  (DateTime(2026, 10, 2), '国庆'),
  (DateTime(2026, 10, 3), '国庆'),
  (DateTime(2026, 10, 4), '国庆'),
  (DateTime(2026, 10, 5), '国庆'),
  (DateTime(2026, 10, 6), '国庆'),
  (DateTime(2026, 10, 7), '国庆'),
  // 2027
  (DateTime(2027, 1, 1), '元旦'),
  (DateTime(2027, 1, 2), '元旦'),
  (DateTime(2027, 1, 3), '元旦'),
  (DateTime(2027, 2, 6), '春节'),
  (DateTime(2027, 2, 7), '春节'),
  (DateTime(2027, 2, 8), '春节'),
  (DateTime(2027, 2, 9), '春节'),
  (DateTime(2027, 2, 10), '春节'),
  (DateTime(2027, 2, 11), '春节'),
  (DateTime(2027, 2, 12), '春节'),
  (DateTime(2027, 2, 13), '春节'),
  (DateTime(2027, 5, 1), '劳动节'),
  (DateTime(2027, 5, 2), '劳动节'),
  (DateTime(2027, 5, 3), '劳动节'),
  (DateTime(2027, 5, 4), '劳动节'),
  (DateTime(2027, 5, 5), '劳动节'),
  (DateTime(2027, 9, 15), '中秋'),
  (DateTime(2027, 10, 1), '国庆'),
  (DateTime(2027, 10, 2), '国庆'),
  (DateTime(2027, 10, 3), '国庆'),
  (DateTime(2027, 10, 4), '国庆'),
  (DateTime(2027, 10, 5), '国庆'),
  (DateTime(2027, 10, 6), '国庆'),
  (DateTime(2027, 10, 7), '国庆'),
];

bool _titleLooksLikeHoliday(String name) {
  return name.contains('假') ||
      name.contains('放假') ||
      name.contains('国庆') ||
      name.contains('中秋') ||
      name.contains('元旦') ||
      name.contains('春节') ||
      name.contains('劳动节') ||
      name.contains('端午') ||
      name.contains('清明');
}

/// Holiday label for [day], if any. Prefers calendar events, then hardcoded list.
String? holidayLabelForDay(DateTime day, List<CalendarEvent> events) {
  final d = calendarDateOnly(day);
  for (final e in events) {
    if (e.covers(d) && _titleLooksLikeHoliday(e.name)) {
      return e.name;
    }
  }
  for (final (date, name) in kChinaPublicHolidays2025to2027) {
    if (calendarDateOnly(date) == d) return name;
  }
  return null;
}

/// All event names covering [day] (for detail panel).
List<CalendarEvent> eventsOnDay(DateTime day, List<CalendarEvent> events) {
  final d = calendarDateOnly(day);
  return events.where((e) => e.covers(d)).toList();
}
