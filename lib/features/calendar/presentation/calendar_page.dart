import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../domain/school_calendar.dart';
import 'calendar_providers.dart';

class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(calendarSnapshotProvider);

    return Scaffold(
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
        onRefresh: () async => ref.invalidate(calendarSnapshotProvider),
        child: ListView(
          padding: AppTokens.pagePadding,
          children: [
            snap.when(
              data: (data) =>
                  DataSourceBanner(live: data.live, message: data.banner),
              loading: () => const MockDataBanner(),
              error: (_, _) => const MockDataBanner(),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            AsyncBody(
              value: snap,
              onRetry: () => ref.invalidate(calendarSnapshotProvider),
              builder: (data) {
                final term = data.currentTerm;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WeekHero(
                      week: data.teachingWeek,
                      termLabel: term?.label ?? AppStrings.termLabel,
                      synced: data.syncedWithScheduleWeek != null,
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    if (term != null) _TermCard(term: term),
                    const SizedBox(height: AppTokens.spaceLg),
                    Text(
                      AppStrings.calendarImportantDates,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppTokens.spaceSm),
                    if (data.events.isEmpty)
                      const AppSurfaceCard(
                        child: Text(
                          AppStrings.emptyCalendarEvents,
                          style: TextStyle(color: AppColors.inkSoft),
                        ),
                      )
                    else
                      for (final e in data.events) ...[
                        _EventTile(event: e),
                        const SizedBox(height: AppTokens.spaceSm),
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

class _WeekHero extends StatelessWidget {
  const _WeekHero({
    required this.week,
    required this.termLabel,
    required this.synced,
  });

  final int week;
  final String termLabel;
  final bool synced;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navyDeep, AppColors.navy, Color(0xFF2A5A8C)],
        ),
      ),
      padding: const EdgeInsets.all(AppTokens.spaceXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${AppStrings.weekPrefix}$week${AppStrings.weekSuffix}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            termLabel,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.35,
            ),
          ),
          if (synced) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              AppStrings.calendarWeekSynced,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TermCard extends StatelessWidget {
  const _TermCard({required this.term});

  final SchoolTermInfo term;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd');
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.calendarTermRange,
            style: TextStyle(
              color: AppColors.navy.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            '${fmt.format(term.startDate)}  —  ${fmt.format(term.endDate)}',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ],
      ),
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
