import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../schedule/domain/course.dart';
import '../domain/calendar_day_logic.dart';
import '../domain/school_calendar.dart';

/// Month grid with class / free / holiday markers and selected-day detail.
class SchoolMonthCalendar extends StatefulWidget {
  const SchoolMonthCalendar({
    super.key,
    required this.courses,
    required this.events,
    this.term,
    this.fallbackWeek,
    this.teachingWeek,
  });

  final List<Course> courses;
  final List<CalendarEvent> events;
  final SchoolTermInfo? term;
  final int? fallbackWeek;
  final int? teachingWeek;

  @override
  State<SchoolMonthCalendar> createState() => _SchoolMonthCalendarState();
}

class _SchoolMonthCalendarState extends State<SchoolMonthCalendar> {
  late DateTime _focused;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = calendarDateOnly(DateTime.now());
    _focused = now;
    _selected = now;
  }

  bool _hasClass(DateTime day) => dayHasClass(
        widget.courses,
        day,
        term: widget.term,
        fallbackWeek: widget.fallbackWeek,
      );

  String? _holiday(DateTime day) =>
      holidayLabelForDay(day, widget.events);

  @override
  Widget build(BuildContext context) {
    final selectedCourses = coursesOnDay(
      widget.courses,
      _selected,
      term: widget.term,
      fallbackWeek: widget.fallbackWeek,
    );
    final holiday = _holiday(_selected);
    final dayEvents = eventsOnDay(_selected, widget.events);
    final weekOfSelected = widget.term?.teachingWeekOf(_selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSurfaceCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Column(
            children: [
              if (widget.teachingWeek != null || weekOfSelected != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    children: [
                      _WeekChip(
                        label:
                            '第${weekOfSelected ?? widget.teachingWeek}${AppStrings.weekSuffix}',
                      ),
                      const Spacer(),
                      Text(
                        DateFormat('yyyy年M月', 'zh_CN').format(_focused),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              TableCalendar<void>(
                locale: 'zh_CN',
                firstDay: DateTime.utc(2024, 1, 1),
                lastDay: DateTime.utc(2028, 12, 31),
                focusedDay: _focused,
                selectedDayPredicate: (d) => isSameDay(d, _selected),
                calendarFormat: CalendarFormat.month,
                availableCalendarFormats: const {
                  CalendarFormat.month: '月',
                },
                startingDayOfWeek: StartingDayOfWeek.monday,
                headerVisible: false,
                daysOfWeekHeight: 28,
                rowHeight: 52,
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selected = calendarDateOnly(selected);
                    _focused = focused;
                  });
                },
                onPageChanged: (focused) {
                  setState(() => _focused = focused);
                },
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, focused) =>
                      _DayCell(
                    day: day,
                    hasClass: _hasClass(day),
                    holiday: _holiday(day),
                    selected: false,
                    today: false,
                  ),
                  todayBuilder: (context, day, focused) =>
                      _DayCell(
                    day: day,
                    hasClass: _hasClass(day),
                    holiday: _holiday(day),
                    selected: isSameDay(day, _selected),
                    today: true,
                  ),
                  selectedBuilder: (context, day, focused) =>
                      _DayCell(
                    day: day,
                    hasClass: _hasClass(day),
                    holiday: _holiday(day),
                    selected: true,
                    today: isSameDay(day, DateTime.now()),
                  ),
                  outsideBuilder: (context, day, focused) =>
                      _DayCell(
                    day: day,
                    hasClass: false,
                    holiday: null,
                    selected: false,
                    today: false,
                    outside: true,
                  ),
                ),
                calendarStyle: const CalendarStyle(
                  outsideDaysVisible: false,
                  markersMaxCount: 0,
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: TextStyle(
                    fontSize: 12,
                    color: AppColors.inkSoft.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                  weekendStyle: TextStyle(
                    fontSize: 12,
                    color: AppColors.inkSoft.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              const _LegendRow(),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        _SelectedDayDetail(
          day: _selected,
          courses: selectedCourses,
          holidayLabel: holiday,
          events: dayEvents,
          teachingWeek: weekOfSelected,
        ),
      ],
    );
  }
}

class _WeekChip extends StatelessWidget {
  const _WeekChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.1),
        borderRadius: AppTokens.borderPill,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.hasClass,
    required this.holiday,
    required this.selected,
    required this.today,
    this.outside = false,
  });

  final DateTime day;
  final bool hasClass;
  final String? holiday;
  final bool selected;
  final bool today;
  final bool outside;

  @override
  Widget build(BuildContext context) {
    Color? fill;
    if (outside) {
      fill = Colors.transparent;
    } else if (holiday != null) {
      fill = AppColors.gold.withValues(alpha: 0.22);
    } else if (hasClass) {
      fill = AppColors.navy.withValues(alpha: 0.12);
    } else if (day.weekday <= DateTime.friday) {
      fill = AppColors.success.withValues(alpha: 0.08);
    }

    final border = selected
        ? Border.all(color: AppColors.navy, width: 2)
        : today
            ? Border.all(color: AppColors.accent, width: 1.6)
            : null;

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        border: border,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${day.day}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: outside
                  ? AppColors.inkSoft.withValues(alpha: 0.35)
                  : holiday != null
                      ? const Color(0xFF8A6A00)
                      : AppColors.ink,
            ),
          ),
          if (holiday != null && !outside)
            Text(
              holiday!.length > 2 ? holiday!.substring(0, 2) : holiday!,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A6A00),
                height: 1.1,
              ),
            )
          else if (hasClass && !outside)
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(top: 2),
              decoration: const BoxDecoration(
                color: AppColors.navy,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: const [
          _LegendItem(
            color: Color(0x1F1A3A5C),
            dot: AppColors.navy,
            label: AppStrings.calendarLegendHasClass,
          ),
          SizedBox(width: 12),
          _LegendItem(
            color: Color(0x141F7A4C),
            label: AppStrings.calendarLegendNoClass,
          ),
          SizedBox(width: 12),
          _LegendItem(
            color: Color(0x38D4A017),
            label: AppStrings.calendarLegendHoliday,
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.dot,
  });

  final Color color;
  final String label;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: dot == null
              ? null
              : Center(
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
        ),
      ],
    );
  }
}

class _SelectedDayDetail extends StatelessWidget {
  const _SelectedDayDetail({
    required this.day,
    required this.courses,
    required this.holidayLabel,
    required this.events,
    this.teachingWeek,
  });

  final DateTime day;
  final List<Course> courses;
  final String? holidayLabel;
  final List<CalendarEvent> events;
  final int? teachingWeek;

  @override
  Widget build(BuildContext context) {
    final title = DateFormat('M月d日 EEEE', 'zh_CN').format(day);
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              if (teachingWeek != null)
                Text(
                  '${AppStrings.weekPrefix}$teachingWeek${AppStrings.weekSuffix}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          if (holidayLabel != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.15),
                borderRadius: AppTokens.borderPill,
              ),
              child: Text(
                '节假日 · $holidayLabel',
                style: const TextStyle(
                  color: Color(0xFF8A6A00),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceMd),
          Text(
            AppStrings.calendarDayCourses,
            style: TextStyle(
              color: AppColors.navy.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          if (courses.isEmpty)
            const Text(
              AppStrings.calendarNoClassThatDay,
              style: TextStyle(color: AppColors.inkSoft, height: 1.4),
            )
          else
            for (final c in courses) ...[
              _CourseLine(course: c, day: day),
              const SizedBox(height: AppTokens.spaceSm),
            ],
          if (events.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              AppStrings.calendarDayEvents,
              style: TextStyle(
                color: AppColors.navy.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            for (final e in events)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  e.remark.isEmpty ? e.name : '${e.name}（${e.remark}）',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.inkSoft,
                    height: 1.35,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CourseLine extends StatelessWidget {
  const _CourseLine({required this.course, required this.day});

  final Course course;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                course.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${course.periodLabelFor(day)} · ${course.location}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
