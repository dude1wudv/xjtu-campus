import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_page_scaffold.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../../core/widgets/app_feedback.dart';
import '../domain/course.dart';
import 'schedule_providers.dart';
import '../../../core/widgets/manual_refresh_button.dart';

class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key});

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  late int _weekday;
  bool _weekView = false;

  @override
  void initState() {
    super.initState();
    _weekday = DateTime.now().weekday;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(scheduleSnapshotProvider);

    return AppPageScaffold(
      appBar: AppBar(
        title: const Text(AppStrings.navSchedule),
        actions: [
          ManualRefreshButton(
            onRefresh: () =>
                ref.read(scheduleSnapshotProvider.notifier).refresh(force: true),
          ),
          IconButton(
            tooltip: _weekView ? AppStrings.listView : AppStrings.weekView,
            onPressed: () => setState(() => _weekView = !_weekView),
            icon: Icon(_weekView ? Icons.view_agenda_outlined : Icons.grid_view),
          ),
        ],
      ),
      body: AsyncBody(
        value: snapshot,
        onRetry: () =>
            ref.read(scheduleSnapshotProvider.notifier).refresh(force: true),
        builder: (data) {
          final week = data.week;
          final items = data.courses
              .where(
                (course) =>
                    course.weeks.isEmpty || course.weeks.contains(week),
              )
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DataSourceBanner(
                      live: data.live,
                      message: data.banner,
                      fromCache: data.fromCache,
                      cachedAt: data.cachedAt,
                      fetchedAt: data.fetchedAt,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${AppStrings.scheduleSubtitle} · ${AppStrings.weekPrefix}$week ${AppStrings.weekSuffix}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    _WeekdayStrip(
                      selected: _weekday,
                      onSelected: (day) => setState(() {
                        _weekday = day;
                        _weekView = false;
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _weekView
                    ? _WeekGrid(courses: items)
                    : _DayList(
                        courses: items
                            .where((course) => course.weekday == _weekday)
                            .toList(),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WeekdayStrip extends StatelessWidget {
  const _WeekdayStrip({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var day = 1; day <= 7; day++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(AppStrings.weekdays[day - 1]),
                selected: selected == day,
                onSelected: (_) => onSelected(day),
                selectedColor: AppColors.navy,
                labelStyle: TextStyle(
                  color: selected == day ? Colors.white : AppColors.navyDeep,
                ),
                avatar: today == day
                    ? const Icon(Icons.circle, size: 8, color: AppColors.gold)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({required this.courses});

  final List<Course> courses;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return const EmptyHint(
        icon: Icons.event_busy,
        text: AppStrings.emptySchedule,
      );
    }
    final sorted = [...courses]
      ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
    return ListView.separated(
      padding: AppTokens.pagePadding,
      itemCount: sorted.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppTokens.spaceMd),
      itemBuilder: (context, index) => _CourseCard(course: sorted[index]),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.chip,
              borderRadius: AppTokens.borderSm,
            ),
            child: Column(
              children: [
                Text('${course.startPeriod}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.navy)),
                Text('至 ${course.endPeriod} 节',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(course.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppTokens.spaceSm),
                Text(course.periodLabel, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppTokens.spaceSm),
                Text(course.location),
                const SizedBox(height: AppTokens.spaceXs),
                Text('${course.teacher} · ${course.weeksLabel}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({required this.courses});

  final List<Course> courses;

  @override
  Widget build(BuildContext context) {
    // Index once instead of scanning all courses for every timetable cell.
    final cells = <(int, int), Course>{};
    for (final course in courses) {
      for (var period = course.startPeriod; period <= course.endPeriod; period++) {
        cells.putIfAbsent((course.weekday, period), () => course);
      }
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      child: SingleChildScrollView(
        child: Table(
          border: TableBorder.all(color: AppColors.navy.withValues(alpha: 0.08)),
          defaultColumnWidth: const FixedColumnWidth(108),
          children: [
            TableRow(
              children: [
                const _HeadCell('节次'),
                for (final label in AppStrings.weekdays) _HeadCell('周$label'),
              ],
            ),
            for (final period in ClassPeriod.catalogFor(DateTime.now()))
              TableRow(
                children: [
                  _HeadCell('${period.index}\n${period.formatClock()}'),
                  for (var day = 1; day <= 7; day++)
                    _Cell(course: cells[(day, period.index)]),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      color: AppColors.navy.withValues(alpha: 0.06),
      padding: const EdgeInsets.all(6),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.course});

  final Course? course;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.all(4),
      color: course == null ? Colors.white : AppColors.navy.withValues(alpha: 0.08),
      child: course == null
          ? const SizedBox.shrink()
          : Text(
              '${course!.name}\n${course!.room}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
    );
  }
}
