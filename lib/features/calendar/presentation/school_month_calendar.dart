import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../attendance/domain/attendance_record.dart';
import '../../attendance/presentation/attendance_providers.dart';
import '../../attendance/presentation/course_attendance_badge.dart';
import '../../schedule/domain/course.dart';
import '../../homework/domain/homework.dart';
import '../../homework/presentation/homework_providers.dart';
import '../../homework/presentation/homework_widgets.dart';
import '../domain/calendar_day_logic.dart';
import '../domain/school_calendar.dart';

/// Quiet month grid: round selection, tiny event dots, and readable day cards.
class SchoolMonthCalendar extends ConsumerStatefulWidget {
  const SchoolMonthCalendar({super.key, required this.courses,
    required this.events, this.term, this.fallbackWeek, this.teachingWeek});
  final List<Course> courses;
  final List<CalendarEvent> events;
  final SchoolTermInfo? term;
  final int? fallbackWeek, teachingWeek;

  @override
  ConsumerState<SchoolMonthCalendar> createState() => _SchoolMonthCalendarState();
}

class _SchoolMonthCalendarState extends ConsumerState<SchoolMonthCalendar> {
  DateTime _focused = calendarDateOnly(DateTime.now());
  DateTime _selected = calendarDateOnly(DateTime.now());

  void _moveMonth(int offset) => setState(() {
    _focused = DateTime(_focused.year, _focused.month + offset);
  });

  @override
  Widget build(BuildContext context) {
    final attendance = ref.watch(attendanceSnapshotProvider).asData?.value;
    final homeworkValue = ref.watch(homeworkProvider);
    final homework = homeworkValue.asData?.value;
    final deadlines = <DateTime, List<Homework>>{};
    for (final item in homework?.items ?? <Homework>[]) {
      if (item.dueAt == null) continue;
      final day = calendarDateOnly(campusTime(item.dueAt!));
      (deadlines[day] ??= []).add(item);
    }
    final dueToday = deadlines[_selected] ?? <Homework>[];
    final courses = coursesOnDay(widget.courses, _selected,
        term: widget.term, fallbackWeek: widget.fallbackWeek);
    final events = eventsOnDay(_selected, widget.events);
    final records = attendance?.records.where((r) => isSameDay(r.date, _selected)).toList()
        ?? const <AttendanceRecord>[];
    final now = DateTime.now();
    final first = DateTime(now.year - 3);
    final last = DateTime(now.year + 3, 12, 31);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    Widget cell(DateTime day, {bool outside = false}) {
      final selected = isSameDay(day, _selected);
      final today = isSameDay(day, now);
      final hasCourse = dayHasClass(widget.courses, day,
          term: widget.term, fallbackWeek: widget.fallbackWeek);
      final hasHomework = deadlines.containsKey(calendarDateOnly(day));
      final holiday = holidayLabelForDay(day, widget.events);
      final attention = attendance?.records.any((r) => isSameDay(r.date, day) &&
          (r.status == AttendanceStatus.absent || r.status == AttendanceStatus.late ||
              r.status == AttendanceStatus.earlyLeave)) ?? false;
      return Semantics(
        label: '${DateFormat('M月d日').format(day)}${today ? '，今天' : ''}'
            '${hasCourse ? '，有课' : ''}${attention ? '，有考勤异常' : ''}${hasHomework ? '，有作业截止' : ''}',
        selected: selected,
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: largeText ? 42 : 34, height: largeText ? 42 : 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? AppColors.navy : null,
              border: today && !selected ? Border.all(color: AppColors.navy) : null,
            ),
            child: Text('${day.day}', style: TextStyle(
              fontSize: 14, fontWeight: selected || today ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : outside ? AppColors.inkSoft : AppColors.ink,
            )),
          ),
          const SizedBox(height: 3),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (hasCourse && !outside) const _Dot(AppColors.navy),
            if (holiday != null && !outside) const _Dot(AppColors.gold),
            if (hasHomework && !outside) const _Dot(Color(0xFF7755AA)),
            if (attention && !outside) const _Dot(AppColors.alert),
          ]),
        ])),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSurfaceCard(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        child: Column(children: [
          Row(children: [
            IconButton(tooltip: '上个月',
                onPressed: _focused.year == first.year && _focused.month == 1 ? null : () => _moveMonth(-1),
                icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text(DateFormat('yyyy年 M月').format(_focused), textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium)),
            IconButton(tooltip: '下个月',
                onPressed: _focused.year == last.year && _focused.month == 12 ? null : () => _moveMonth(1),
                icon: const Icon(Icons.chevron_right)),
            TextButton(onPressed: () => setState(() {
              _focused = calendarDateOnly(now); _selected = _focused;
            }), child: const Text('今天')),
          ]),
          TableCalendar<void>(
            locale: 'zh_CN', firstDay: first, lastDay: last, focusedDay: _focused,
            headerVisible: false, startingDayOfWeek: StartingDayOfWeek.monday,
            calendarFormat: CalendarFormat.month,
            // Reserve vertical drags for the surrounding page's ListView.
            // This month-only calendar only needs horizontal month swipes.
            availableGestures: AvailableGestures.horizontalSwipe,
            availableCalendarFormats: const {CalendarFormat.month: '月'},
            daysOfWeekHeight: largeText ? 36 : 28, rowHeight: largeText ? 70 : 54,
            selectedDayPredicate: (day) => isSameDay(day, _selected),
            onDaySelected: (selected, focused) => setState(() {
              _selected = calendarDateOnly(selected); _focused = focused;
            }),
            onPageChanged: (day) => setState(() => _focused = day),
            calendarStyle: const CalendarStyle(outsideDaysVisible: false, markersMaxCount: 0),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (_, day, _) => cell(day),
              selectedBuilder: (_, day, _) => cell(day),
              todayBuilder: (_, day, _) => cell(day),
              outsideBuilder: (_, day, _) => cell(day, outside: true),
            ),
          ),
          const SizedBox(height: 8),
          const Wrap(spacing: 16, runSpacing: 8, children: [
            _Legend('有课', AppColors.navy), _Legend('假期', AppColors.gold),
            _Legend('考勤异常', AppColors.alert), _Legend('作业截止', Color(0xFF7755AA)),
          ]),
        ]),
      ),
      const SizedBox(height: 20),
      Text(DateFormat('M月d日 EEEE', 'zh_CN').format(_selected),
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text('${courses.length} 门课程 · ${dueToday.length} 项作业截止 · ${records.length} 条考勤'
          '${attendance?.fromCache == true ? '（缓存）' : ''}',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      if (homeworkValue.isLoading) const Text('正在同步作业截止时间…'),
      if (homeworkValue.hasError && !homeworkValue.isLoading)
        const Text('作业尚未同步，请到作业中心登录或重试。'),
      if (homework?.fromCache == true) const Text('作业截止时间来自缓存'),
      if ((homework?.failedCourses ?? 0) > 0) const Text('部分课程作业未同步，截止标记可能不完整'),
      for (final item in dueToday) HomeworkTile(item: item),
      if (courses.isEmpty) const AppSurfaceCard(child: Text('当前课表中没有这一天的课程')),
      for (final course in courses)
        AppSurfaceCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.chip, borderRadius: AppTokens.borderSm),
              child: Text('${course.startPeriod}–${course.endPeriod}\n节', textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(course.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(course.periodLabelFor(_selected), style: Theme.of(context).textTheme.bodySmall),
              Text(course.location, style: Theme.of(context).textTheme.bodySmall),
              CourseAttendanceBadge(course: course, day: _selected),
            ])),
          ]),
        ),
      // Preserve official records even if a changed timetable cannot be matched.
      for (final record in records.where((r) => !courses.any((c) => r.matches(c, _selected))))
        AppSurfaceCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(record.courseName.isEmpty ? '学校考勤记录' : record.courseName,
                style: Theme.of(context).textTheme.titleMedium),
            Text('第${record.startPeriod}–${record.endPeriod}节 · ${record.location}'),
            Text(record.status.label, style: TextStyle(color: attendanceColor(record.status))),
          ]),
        ),
      for (final event in events)
        AppSurfaceCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            const Icon(Icons.event_outlined, color: AppColors.gold),
            const SizedBox(width: 12),
            Expanded(child: Text(event.remark.isEmpty ? event.name : '${event.name}\n${event.remark}')),
          ]),
        ),
    ]);
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 4, height: 4, margin: const EdgeInsets.symmetric(horizontal: 2),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    _Dot(color), const SizedBox(width: 4), Text(label, style: Theme.of(context).textTheme.bodySmall),
  ]);
}
