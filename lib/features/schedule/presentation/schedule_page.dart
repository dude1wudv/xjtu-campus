import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_page_scaffold.dart';
import '../domain/course.dart';
import '../domain/schedule_repository.dart';
import '../domain/timetable_logic.dart';
import 'course_tile.dart';
import 'schedule_providers.dart';
import 'schedule_status.dart';
import 'schedule_transfer.dart';

class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key});
  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  int offset = 0;
  int weekday = DateTime.now().weekday;
  bool weekView = true;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(scheduleSnapshotProvider);
    final data = value.asData?.value;
    final now = DateTime.now();
    final monday = mondayOf(now).add(Duration(days: offset * 7));
    final week = data == null ? null : teachingWeek(data, monday, now);
    final unavailableWeek =
        data?.currentWeekOnly == true &&
        monday != mondayOf(data!.sourceMonday ?? data.cachedAt ?? now);
    return AppPageScaffold(
      appBar: AppBar(
        title: const Text('一周课表'),
        actions: [
          IconButton(
            tooltip: '导入与导出课表',
            onPressed: () => showScheduleTransfer(context, ref, data),
            icon: const Icon(Icons.import_export),
          ),
          IconButton(
            tooltip: '刷新课表',
            onPressed: () async {
              try {
                await ref.read(scheduleSnapshotProvider.notifier).refresh();
              } catch (_) {}
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 110),
        children: [
          ScheduleStatus(value: value),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                week == null ? '本周安排' : '第 $week 教学周',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(
                '${monday.month}.${monday.day} — ${monday.add(const Duration(days: 6)).month}.${monday.add(const Duration(days: 6)).day}',
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '上一周',
                    onPressed: offset > -52
                        ? () => setState(() => offset--)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  TextButton(
                    onPressed: () => setState(() => offset = 0),
                    child: const Text('回到本周'),
                  ),
                  IconButton(
                    tooltip: '下一周',
                    onPressed: offset < 52
                        ? () => setState(() => offset++)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('周视图'),
                    icon: Icon(Icons.calendar_view_week),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('日列表'),
                    icon: Icon(Icons.view_agenda_outlined),
                  ),
                ],
                selected: {weekView},
                onSelectionChanged: (v) => setState(() => weekView = v.first),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (data == null && value.isLoading)
            const ScheduleSkeleton()
          else if (data != null && unavailableWeek)
            const _Empty('当前数据源仅包含一次同步周的课程，所选周尚未获取。请同步最新课表或重新导入。')
          else if (data != null &&
              (data.failure == null || data.fromCache)) ...[
            if (weekView)
              _WeekGrid(data: data, monday: monday, now: now)
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var d = 1; d <= 7; d++)
                    ChoiceChip(
                      label: Text('周${'一二三四五六日'[d - 1]}'),
                      selected: weekday == d,
                      onSelected: (_) => setState(() => weekday = d),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (coursesForDay(
                data,
                monday.add(Duration(days: weekday - 1)),
                now,
              ).isEmpty)
                const _Empty('这一天没有已知课程，留一点时间给自己。'),
              for (final c in coursesForDay(
                data,
                monday.add(Duration(days: weekday - 1)),
                now,
              ))
                CourseTile(
                  course: c,
                  day: monday.add(Duration(days: weekday - 1)),
                ),
            ],
            const SizedBox(height: 16),
            Text(
              '${ClassPeriod.seasonLabel(monday)} · 点击课程查看详情；重叠课程并排显示。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(child: Text(message, textAlign: TextAlign.center)),
  );
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.data,
    required this.monday,
    required this.now,
  });
  final ScheduleSnapshot data;
  final DateTime monday;
  final DateTime now;
  static const rowHeight = 68.0;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.max(constraints.maxWidth, 780.0);
      final dayWidth = (width - 56) / 7;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (constraints.maxWidth < 780)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '左右滑动查看完整一周，或切换日列表',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 56),
                      for (var i = 0; i < 7; i++)
                        SizedBox(
                          width: dayWidth,
                          height: 64,
                          child: Center(
                            child: Text(
                              '周${'一二三四五六日'[i]}\n${monday.add(Duration(days: i)).month}/${monday.add(Duration(days: i)).day}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color:
                                    DateUtils.isSameDay(
                                      monday.add(Duration(days: i)),
                                      now,
                                    )
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(
                    height: rowHeight * 11,
                    child: Stack(
                      children: [
                        for (var p = 0; p < 11; p++)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: p * rowHeight,
                            height: rowHeight,
                            child: Container(
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: Color(0xFFE3E8EE)),
                                ),
                              ),
                            ),
                          ),
                        for (var p = 1; p <= 11; p++)
                          Positioned(
                            left: 0,
                            top: (p - 1) * rowHeight + 10,
                            width: 50,
                            child: Text(
                              '$p\n${ClassPeriod.byIndex(p, day: monday).formatClock().split('–').first}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        for (var d = 0; d < 7; d++)
                          ..._dayBlocks(context, d, dayWidth),
                        if (mondayOf(now) == monday) ..._timeLine(dayWidth),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
  List<Widget> _dayBlocks(BuildContext context, int d, double dayWidth) {
    final day = monday.add(Duration(days: d));
    final lanes = courseLanes(coursesForDay(data, day, now));
    return [
      for (var lane = 0; lane < lanes.length; lane++)
        for (final c in lanes[lane])
          Positioned(
            left: 56 + d * dayWidth + lane * dayWidth / lanes.length + 3,
            top: (c.startPeriod - 1) * rowHeight + 3,
            width: dayWidth / lanes.length - 6,
            height: (c.endPeriod - c.startPeriod + 1) * rowHeight - 6,
            child: Semantics(
              button: true,
              label: '${c.name}，${c.periodLabelFor(day)}，${c.location}',
              child: Material(
                color: courseColor(c).withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push(courseRoute(c, day)),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: courseColor(c), width: 3),
                      ),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            c.name,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: courseColor(c),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.room,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
    ];
  }

  List<Widget> _timeLine(double dayWidth) {
    final minute = now.hour * 60 + now.minute;
    for (final p in ClassPeriod.catalogFor(now)) {
      if (minute >= p.start.inMinutes && minute <= p.end.inMinutes) {
        final top =
            (p.index -
                1 +
                (minute - p.start.inMinutes) /
                    (p.end.inMinutes - p.start.inMinutes)) *
            rowHeight;
        return [
          Positioned(
            left: 56 + (now.weekday - 1) * dayWidth,
            width: dayWidth,
            top: top,
            child: IgnorePointer(
              child: Container(height: 2, color: const Color(0xFFB74747)),
            ),
          ),
        ];
      }
    }
    return [];
  }
}
