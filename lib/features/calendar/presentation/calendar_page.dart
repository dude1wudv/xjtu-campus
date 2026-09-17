import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/app_page_scaffold.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../../core/widgets/manual_refresh_button.dart';
import '../../attendance/presentation/attendance_providers.dart';
import '../../schedule/domain/course.dart';
import '../../schedule/presentation/schedule_providers.dart';
import '../domain/school_calendar.dart';
import 'calendar_providers.dart';
import 'school_month_calendar.dart';

class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(calendarSnapshotProvider);
    final schedule = ref.watch(scheduleSnapshotProvider);

    return AppPageScaffold(
      appBar: AppBar(
        title: const Text(AppStrings.calendarTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        actions: [
          ManualRefreshButton(
            onRefresh: () async {
              ref.invalidate(attendanceSnapshotProvider);
              await ref
                  .read(scheduleSnapshotProvider.notifier)
                  .refresh(force: true);
              await ref
                  .read(calendarSnapshotProvider.notifier)
                  .refresh(force: true);
            },
          ),
          IconButton(
            tooltip: AppStrings.calendarOpenWeb,
            onPressed: () {
              context.push(
                '/browser',
                extra: {
                  'url': CampusUrls.one2020CalendarPage,
                  'title': AppStrings.calendarTitle,
                },
              );
            },
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(attendanceSnapshotProvider);
          await ref.read(scheduleSnapshotProvider.notifier).refresh(force: true);
          await ref.read(calendarSnapshotProvider.notifier).refresh(force: true);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: AppTokens.pagePadding,
          children: [
            snap.when(
              data: (data) =>
                  DataSourceBanner(
                    live: data.live,
                    message: data.banner,
                    fromCache: data.fromCache,
                    cachedAt: data.cachedAt,
                    fetchedAt: data.fetchedAt,
                  ),
              loading: () => const MockDataBanner(),
              error: (_, _) => const MockDataBanner(),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            AsyncBody(
              value: snap,
              onRetry: () => ref.read(calendarSnapshotProvider.notifier).refresh(force: true),
              builder: (data) {
                final term = data.currentTerm;
                final courses = schedule.asData?.value.courses ?? const <Course>[];
                final scheduleWeek = schedule.asData?.value.week;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CompactWeekHeader(
                      week: data.teachingWeek,
                      termLabel: term?.label ?? AppStrings.termLabel,
                      term: term,
                      synced: data.syncedWithScheduleWeek != null,
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    SchoolMonthCalendar(
                      courses: courses,
                      events: data.events,
                      term: term,
                      fallbackWeek: scheduleWeek,
                      teachingWeek: data.teachingWeek,
                    ),
                    if (data.events.isNotEmpty) ...[
                      const SizedBox(height: AppTokens.spaceLg),
                      Text(
                        AppStrings.calendarImportantDates,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      for (final e in data.events) ...[
                        _EventTile(event: e),
                        const SizedBox(height: AppTokens.spaceSm),
                      ],
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactWeekHeader extends StatelessWidget {
  const _CompactWeekHeader({
    required this.week,
    required this.termLabel,
    required this.synced,
    this.term,
  });

  final int week;
  final String termLabel;
  final bool synced;
  final SchoolTermInfo? term;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('M月d日');
    return AppSurfaceCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: AppColors.chip, borderRadius: AppTokens.borderMd),
          child: Column(children: [
            Text('$week', style: const TextStyle(fontSize: 28,
                color: AppColors.navy, fontWeight: FontWeight.w800)),
            const Text('教学周', style: TextStyle(fontSize: 12, color: AppColors.navy)),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(termLabel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          if (term != null)
            Text('${fmt.format(term!.startDate)} — ${fmt.format(term!.endDate)}',
                style: Theme.of(context).textTheme.bodySmall),
          if (synced) ...[
            const SizedBox(height: 6),
            Text(AppStrings.calendarWeekSyncedShort,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ])),
      ]),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('M月d日', 'zh_CN');
    final range = event.startDate == event.endDate
        ? fmt.format(event.startDate)
        : '${fmt.format(event.startDate)} – ${fmt.format(event.endDate)}';
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.name,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            range,
            style: const TextStyle(color: AppColors.inkSoft, fontSize: 13),
          ),
          if (event.remark.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              event.remark,
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ],
        ],
      ),
    );
  }
}
