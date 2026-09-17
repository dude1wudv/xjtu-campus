import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_page_scaffold.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../about/presentation/about_sheet.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../schedule/domain/course.dart';
import '../../schedule/presentation/schedule_providers.dart';
import '../domain/greeting.dart';
import '../../../core/widgets/app_section_header.dart';
import 'campus_services.dart';
import 'campus_connection_card.dart';
import '../../../core/widgets/manual_refresh_button.dart';

class HomeDashboard extends ConsumerStatefulWidget {
  const HomeDashboard({super.key});

  @override
  ConsumerState<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends ConsumerState<HomeDashboard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      HomeUpdateAutoCheck.runOnce(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final snapshot = ref.watch(scheduleSnapshotProvider);
    final now = DateTime.now();

    return AppPageScaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          ManualRefreshButton(
            onRefresh: () => ref
                .read(scheduleSnapshotProvider.notifier)
                .refresh(force: true),
          ),
          IconButton(
            tooltip: '关于 / 检查更新',
            onPressed: () => showAboutSheet(context),
            icon: const Icon(Icons.info_outline_rounded),
          ),
          IconButton(
            tooltip: AppStrings.openLogin,
            onPressed: () => context.push('/login'),
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(scheduleSnapshotProvider.notifier).refresh(force: true),
        child: ListView(
        key: const PageStorageKey('home-dashboard'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppTokens.pagePadding,
        children: [
          _GreetingCard(auth: auth, now: now, week: snapshot.value?.week),
          const SizedBox(height: AppTokens.spaceMd),
          const CampusConnectionCard(),
          const SizedBox(height: AppTokens.spaceMd),
          snapshot.when(
            data: (data) =>
                DataSourceBanner(
              live: data.live,
              message: data.banner,
              fromCache: data.fromCache,
              cachedAt: data.cachedAt,
              fetchedAt: data.fetchedAt,
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          const AppSectionHeader(title: '今日安排'),
          AsyncBody(
            value: snapshot,
            onRetry: () => ref.read(scheduleSnapshotProvider.notifier).refresh(force: true),
            builder: (data) {
              final todayCount = _todayCourseCount(
                data.courses,
                now,
                weekNumber: data.week,
              );
              final hero = _resolveHeroCourse(
                data.courses,
                now,
                weekNumber: data.week,
              );
              final cacheAge = data.fromCache && data.cachedAt != null
                  ? AppStrings.updatedAtLabel(data.cachedAt!)
                  : (data.live && data.fetchedAt != null
                      ? AppStrings.freshUpdatedLabel(data.fetchedAt)
                      : null);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NextClassHero(
                    hero: hero,
                    now: now,
                    cacheAgeLabel: cacheAge,
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  _TodayStatsRow(
                    todayCount: todayCount,
                    isLoggedIn: auth.isLoggedIn,
                    week: data.week,
                  ),
                ],
              );
            },
          ),
          const AppSectionHeader(title: '学习教务', subtitle: '课程、成绩与考试，集中查看'),
          const CampusServiceGrid(services: CampusService.learning),
          const AppSectionHeader(title: '校园生活', subtitle: '自习、消费与提醒，随手可达'),
          const CampusServiceGrid(services: CampusService.living),
          const AppSectionHeader(title: '校园资讯'),
          AppSurfaceCard(
            onTap: () => context.go('/notices'),
            child: const Row(
              children: [
                Icon(Icons.campaign_outlined, color: AppColors.navy),
                SizedBox(width: AppTokens.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('学校通知', style: TextStyle(fontWeight: FontWeight.w700)),
                      SizedBox(height: AppTokens.spaceXs),
                      Text('查看教务公告与校园动态'),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

int _todayCourseCount(
  List<Course> courses,
  DateTime now, {
  int? weekNumber,
}) {
  return courses.where((c) {
    if (c.weekday != now.weekday) return false;
    if (weekNumber != null &&
        c.weeks.isNotEmpty &&
        !c.weeks.contains(weekNumber)) {
      return false;
    }
    return true;
  }).length;
}

class _HeroCourse {
  const _HeroCourse({
    required this.course,
    required this.inProgress,
    required this.isToday,
  });

  final Course course;
  final bool inProgress;
  final bool isToday;
}

_HeroCourse? _resolveHeroCourse(
  List<Course> courses,
  DateTime now, {
  int? weekNumber,
}) {
  final ofDay = courses.where((c) {
    if (c.weekday != now.weekday) return false;
    if (weekNumber != null &&
        c.weeks.isNotEmpty &&
        !c.weeks.contains(weekNumber)) {
      return false;
    }
    return true;
  }).toList()
    ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));

  for (final c in ofDay) {
    final start = c.startAt(now);
    final end = c.endAt(now);
    if (!start.isAfter(now) && end.isAfter(now)) {
      return _HeroCourse(course: c, inProgress: true, isToday: true);
    }
  }

  final next = Course.nextAfter(courses, now, weekNumber: weekNumber);
  if (next == null) return null;
  final isToday = next.weekday == now.weekday;
  return _HeroCourse(course: next, inProgress: false, isToday: isToday);
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({
    required this.auth,
    required this.now,
    required this.week,
  });

  final AuthState auth;
  final DateTime now;
  final int? week;

  @override
  Widget build(BuildContext context) {
    final hello = greetingForHour(now.hour);
    final name = auth.isLoggedIn ? auth.user.displayName : AppStrings.guestName;
    final date = DateFormat('M月d日 EEEE', 'zh_CN').format(now);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navyDeep, AppColors.navy, Color(0xFF2A5A8C)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.spaceXl,
          AppTokens.spaceXl,
          AppTokens.spaceXl,
          AppTokens.spaceLg + 2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$hello，$name',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              [
                date,
                if (week != null)
                  '${AppStrings.weekPrefix}$week${AppStrings.weekSuffix}',
                AppStrings.termLabel,
              ].join(' · '),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                height: 1.35,
              ),
            ),
            if (!auth.isLoggedIn) ...[
              const SizedBox(height: AppTokens.spaceMd),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.navy,
                  minimumSize: const Size(0, 44),
                ),
                onPressed: () => context.push('/login'),
                icon: const Icon(Icons.person_outline, size: 18),
                label: const Text(AppStrings.openLogin),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NextClassHero extends StatelessWidget {
  const _NextClassHero({
    required this.hero,
    required this.now,
    this.cacheAgeLabel,
  });

  final _HeroCourse? hero;
  final DateTime now;
  final String? cacheAgeLabel;

  @override
  Widget build(BuildContext context) {
    if (hero == null || !hero!.isToday) {
      return AppSurfaceCard(
        onTap: () => context.go('/schedule'),
        softShadow: true,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.chip,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.free_breakfast_outlined,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(width: AppTokens.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.nextClass,
                    style: TextStyle(
                      color: AppColors.navy.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (cacheAgeLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      cacheAgeLabel!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.inkSoft,
                            fontSize: 11.5,
                          ),
                    ),
                  ],
                  const SizedBox(height: AppTokens.spaceXs),
                  Text(
                    hero == null
                        ? AppStrings.noClassToday
                        : AppStrings.noMoreClassToday,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
          ],
        ),
      );
    }

    final item = hero!.course;
    final inProgress = hero!.inProgress;
    String? countdown;
    if (!inProgress) {
      final start = item.startAt(now);
      final mins = start.difference(now).inMinutes;
      if (mins >= 0) {
        if (mins < 60) {
          countdown =
              '${AppStrings.countdownMinutesPrefix}$mins${AppStrings.countdownMinutesSuffix}';
        } else {
          final h = mins ~/ 60;
          final m = mins % 60;
          countdown = m == 0
              ? '${AppStrings.countdownHoursPrefix}$h 小时'
              : '${AppStrings.countdownHoursPrefix}$h 小时 $m 分';
        }
      }
    }

    return AppSurfaceCard(
      onTap: () => context.go('/schedule'),
      softShadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                AppStrings.nextClass,
                style: TextStyle(
                  color: AppColors.navy.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (inProgress)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceSm,
                    vertical: AppTokens.spaceXs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: AppTokens.borderPill,
                  ),
                  child: const Text(
                    AppStrings.classInProgress,
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (countdown != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceSm,
                    vertical: AppTokens.spaceXs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: AppTokens.borderPill,
                  ),
                  child: Text(
                    countdown,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (cacheAgeLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              cacheAgeLabel!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSoft,
                    fontSize: 11.5,
                  ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceMd),
          Text(
            item.name,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  letterSpacing: -0.3,
                ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          _MetaRow(
            icon: Icons.schedule_rounded,
            text: item.periodLabelFor(now),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _MetaRow(
            icon: Icons.place_outlined,
            text: item.location,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _MetaRow(
            icon: Icons.person_outline_rounded,
            text: '${AppStrings.teacher}：${item.teacher}',
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.inkSoft),
        const SizedBox(width: AppTokens.spaceSm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _TodayStatsRow extends StatelessWidget {
  const _TodayStatsRow({
    required this.todayCount,
    required this.isLoggedIn,
    required this.week,
  });

  final int todayCount;
  final bool isLoggedIn;
  final int week;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            label: AppStrings.todayCourseCount,
            value: '$todayCount',
            icon: Icons.menu_book_outlined,
          ),
        ),
        const SizedBox(width: AppTokens.spaceSm),
        Expanded(
          child: _StatChip(
            label: isLoggedIn
                ? AppStrings.loggedInStatus
                : AppStrings.guestStatus,
            value: isLoggedIn ? '✓' : '–',
            icon: isLoggedIn
                ? Icons.verified_user_outlined
                : Icons.person_outline,
          ),
        ),
        const SizedBox(width: AppTokens.spaceSm),
        Expanded(
          child: _StatChip(
            label: '${AppStrings.weekPrefix}$week${AppStrings.weekSuffix}',
            value: '$week',
            icon: Icons.calendar_today_outlined,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMd,
        vertical: AppTokens.spaceMd,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppTokens.borderMd,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.navy),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppColors.ink,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

