import 'package:flutter_test/flutter_test.dart';

import 'package:xjtu_campus/features/calendar/domain/calendar_day_logic.dart';
import 'package:xjtu_campus/features/calendar/domain/school_calendar.dart';
import 'package:xjtu_campus/features/schedule/domain/course.dart';

Course _course({
  required int weekday,
  required List<int> weeks,
  String name = '线性代数',
  int startPeriod = 1,
  int endPeriod = 2,
}) {
  return Course(
    id: 'c-$name-$weekday-$startPeriod',
    name: name,
    teacher: '张老师',
    campus: '兴庆',
    building: '主楼',
    room: 'A101',
    weekday: weekday,
    startPeriod: startPeriod,
    endPeriod: endPeriod,
    weeks: weeks,
  );
}

void main() {
  final term = SchoolTermInfo(
    id: 't',
    label: '2026-2027学年第一学期',
    startDate: DateTime(2026, 9, 7),
    endDate: DateTime(2027, 1, 17),
  );

  test('dayHasClass: weekday + teaching week (ZC) match', () {
    // Term Mon 2026-09-07 → teaching week 1.
    // Monday 2026-09-14 is teaching week 2.
    final courses = [
      _course(weekday: DateTime.monday, weeks: const [1, 3, 5]),
    ];
    final week1Mon = DateTime(2026, 9, 7);
    final week2Mon = DateTime(2026, 9, 14);
    expect(term.teachingWeekOf(week1Mon), 1);
    expect(term.teachingWeekOf(week2Mon), 2);

    expect(
      dayHasClass(courses, week1Mon, term: term),
      isTrue,
      reason: 'week 1 Monday should have class',
    );
    expect(
      dayHasClass(courses, week2Mon, term: term),
      isFalse,
      reason: 'week 2 Monday not in weeks list',
    );
    expect(
      dayHasClass(courses, DateTime(2026, 9, 8), term: term),
      isFalse,
      reason: 'Tuesday should not match Monday course',
    );
  });

  test('holidayLabelForDay prefers event titles with 假', () {
    final events = [
      CalendarEvent(
        name: '国庆假期',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 7),
      ),
    ];
    expect(holidayLabelForDay(DateTime(2026, 10, 3), events), '国庆假期');
    expect(holidayLabelForDay(DateTime(2026, 10, 10), events), isNull);
  });

  test('holidayLabelForDay falls back to hardcoded 中秋/国庆', () {
    expect(holidayLabelForDay(DateTime(2026, 9, 25), const []), '中秋');
    expect(holidayLabelForDay(DateTime(2026, 10, 1), const []), '国庆');
  });

  test('coursesOnDay sorts by start period', () {
    final list = [
      _course(
        weekday: DateTime.wednesday,
        weeks: const [1],
        name: '晚课',
        startPeriod: 9,
        endPeriod: 10,
      ),
      _course(
        weekday: DateTime.wednesday,
        weeks: const [1],
        name: '早课',
        startPeriod: 1,
        endPeriod: 2,
      ),
    ];
    final day = DateTime(2026, 9, 9); // Wed week 1
    final ofDay = coursesOnDay(list, day, term: term);
    expect(ofDay.map((c) => c.name).toList(), ['早课', '晚课']);
  });
}
