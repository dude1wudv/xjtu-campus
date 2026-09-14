import 'package:flutter_test/flutter_test.dart';

import 'package:xjtu_campus/core/constants/app_constants.dart';
import 'package:xjtu_campus/features/alarms/domain/alarm_planner.dart';
import 'package:xjtu_campus/features/alarms/domain/alarm_suggestion.dart';
import 'package:xjtu_campus/features/schedule/data/mock_schedule_data.dart';
import 'package:xjtu_campus/features/schedule/domain/course.dart';

void main() {
  const planner = AlarmPlanner();
  final courses = MockScheduleData.courses;

  test('起床闹钟为当天第一节课减去默认 90 分钟', () {
    final now = DateTime(2026, 9, 14, 5); // 周一
    final suggestions = planner.plan(courses: courses, now: now);
    final wake = suggestions.firstWhere(
      (item) => item.kind == AlarmKind.wakeUp,
    );

    expect(wake.course.name, '高等数学A');
    expect(wake.fireAt, DateTime(2026, 9, 14, 6, 30));
    expect(wake.minutesBefore, AppConstants.defaultWakeOffset.inMinutes);
  });

  test('为每门课生成 15/30 分钟课前提醒', () {
    final now = DateTime(2026, 9, 14, 5);
    final mondayReminders = planner
        .plan(courses: courses, now: now, daysAhead: 1)
        .where((item) => item.kind == AlarmKind.classReminder);

    final math = mondayReminders.where((item) => item.course.id == 'math-mon');
    expect(math.map((item) => item.minutesBefore), containsAll([15, 30]));
    expect(
      math.map((item) => item.fireAt),
      containsAll([DateTime(2026, 9, 14, 7, 30), DateTime(2026, 9, 14, 7, 45)]),
    );
  });

  test('已开始的课程不会生成过去的闹钟', () {
    final now = DateTime(2026, 9, 14, 12);
    final suggestions = planner.plan(courses: courses, now: now, daysAhead: 1);
    expect(suggestions.every((item) => item.fireAt.isAfter(now)), isTrue);
    expect(suggestions.where((item) => item.kind == AlarmKind.wakeUp), isEmpty);
  });

  test('周次过滤：不在本周的课程不生成闹钟', () {
    final math = planner.plan(
      courses: [MockScheduleData.courses.first],
      now: DateTime(2026, 9, 14, 5),
      daysAhead: 1,
      weekNumber: 3,
    );
    expect(math, isNotEmpty);

    final physics = planner.plan(
      courses: [
        MockScheduleData.courses.firstWhere(
          (course) => course.id == 'physics-wed',
        ),
      ],
      now: DateTime(2026, 9, 16, 5),
      daysAhead: 1,
      weekNumber: 3,
    );
    expect(physics, isEmpty);
  });

  test('enableWake/enableClass 开关生效', () {
    final now = DateTime(2026, 9, 14, 5);
    final wakeOnly = planner.plan(
      courses: courses,
      now: now,
      daysAhead: 1,
      enableWake: true,
      enableClass: false,
    );
    expect(wakeOnly.every((s) => s.kind == AlarmKind.wakeUp), isTrue);
    expect(wakeOnly, isNotEmpty);

    final classOnly = planner.plan(
      courses: courses,
      now: now,
      daysAhead: 1,
      enableWake: false,
      enableClass: true,
      reminderOffsets: const [Duration(minutes: 10)],
    );
    expect(classOnly.every((s) => s.kind == AlarmKind.classReminder), isTrue);
    expect(classOnly.every((s) => s.minutesBefore == 10), isTrue);

    final none = planner.plan(
      courses: courses,
      now: now,
      daysAhead: 1,
      enableWake: false,
      enableClass: false,
    );
    expect(none, isEmpty);
  });

  test('夏秋季下午第5节 14:30；冬春季 14:00', () {
    final summer = ClassPeriod.byIndex(5, day: DateTime(2026, 6, 1));
    expect(summer.start, const Duration(hours: 14, minutes: 30));
    expect(ClassPeriod.isSummerSeason(DateTime(2026, 6, 1)), isTrue);
    expect(ClassPeriod.seasonLabel(DateTime(2026, 6, 1)), contains('夏秋'));

    final winter = ClassPeriod.byIndex(5, day: DateTime(2026, 11, 1));
    expect(winter.start, const Duration(hours: 14));
    expect(ClassPeriod.isSummerSeason(DateTime(2026, 11, 1)), isFalse);
    expect(ClassPeriod.seasonLabel(DateTime(2026, 11, 1)), contains('冬春'));

    // Afternoon course (道德/法治 Tue 5-6) fires at season clock.
    final moral = MockScheduleData.courses.firstWhere(
      (c) => c.id == 'moral-tue',
    );
    final summerStart = moral.startAt(DateTime(2026, 6, 2)); // Tuesday
    expect(summerStart, DateTime(2026, 6, 2, 14, 30));
    final winterStart = moral.startAt(DateTime(2026, 11, 3)); // Tuesday
    expect(winterStart, DateTime(2026, 11, 3, 14, 0));
  });
}
