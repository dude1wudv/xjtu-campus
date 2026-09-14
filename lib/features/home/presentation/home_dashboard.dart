import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../about/presentation/about_sheet.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../notifications/domain/school_notice.dart';
import '../../schedule/domain/course.dart';
import '../../schedule/presentation/schedule_providers.dart';

/// Lightweight peek — mock/local only, no WebView / Dio on home open.
final homeNoticesPeekProvider = FutureProvider<List<SchoolNotice>>((ref) async {
  final snap = await ref.watch(mockNotificationsRepositoryProvider).load();
  return snap.notices.take(3).toList();
});

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
    final noticesPeek = ref.watch(homeNoticesPeekProvider);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
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
      body: ListView(
        padding: AppTokens.pagePadding,
        children: [
          snapshot.when(
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
          const SizedBox(height: AppTokens.spaceLg),
          _GreetingCard(auth: auth, now: now, week: snapshot.value?.week),
          const SizedBox(height: AppTokens.spaceLg),
          AsyncBody(
            value: snapshot,
            onRetry: () => ref.invalidate(scheduleSnapshotProvider),
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
          const SizedBox(height: AppTokens.spaceLg),
          _NoticesPeek(value: noticesPeek),
          const SizedBox(height: AppTokens.spaceMd),
          const _ClassroomShortcutCard(),
          const SizedBox(height: AppTokens.spaceMd),
          const _AcademicsShortcutCard(),
          const SizedBox(height: AppTokens.spaceMd),
          const _CalendarShortcutCard(),
          const SizedBox(height: AppTokens.spaceXl),
          Text(
            AppStrings.quickActions,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          const _QuickActions(),
        ],
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
    final hour = now.hour;
    final hello = hour < 11
        ? '早上好'
        : hour < 14
            ? '中午好'
            : hour < 19
                ? '下午好'
                : '晚上好';
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
            const SizedBox(height: AppTokens.spaceLg),
            if (!auth.isLoggedIn)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.navy,
                  minimumSize: const Size(0, 44),
                ),
                onPressed: () => context.push('/login'),
                child: const Text(AppStrings.openLogin),
              )
            else
              Text(
                '${AppStrings.loggedInAs} ${auth.user.studentId}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
              ),
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

class _NoticesPeek extends StatelessWidget {
  const _NoticesPeek({required this.value});

  final AsyncValue<List<SchoolNotice>> value;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => AppSurfaceCard(
        onTap: () => context.go('/notices'),
        child: const _NoticesPeekHeader(subtitle: AppStrings.noticesPeekSubtitle),
      ),
      error: (_, _) => AppSurfaceCard(
        onTap: () => context.go('/notices'),
        child: const _NoticesPeekHeader(subtitle: AppStrings.noticesPeekSubtitle),
      ),
      data: (notices) {
        if (notices.isEmpty) {
          return AppSurfaceCard(
            onTap: () => context.go('/notices'),
            child: const _NoticesPeekHeader(
              subtitle: AppStrings.noticesPeekSubtitle,
            ),
          );
        }
        return AppSurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => context.go('/notices'),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppTokens.radiusLg),
                ),
                child: const Padding(
                  padding: AppTokens.cardPadding,
                  child: _NoticesPeekHeader(
                    subtitle: AppStrings.noticesPeekMore,
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.line),
              for (var i = 0; i < notices.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.line),
                InkWell(
                  onTap: () => context.go('/notices'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spaceLg,
                      vertical: AppTokens.spaceMd,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notices[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: AppTokens.spaceXs),
                        Text(
                          DateFormat('M月d日', 'zh_CN')
                              .format(notices[i].publishedAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NoticesPeekHeader extends StatelessWidget {
  const _NoticesPeekHeader({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: AppColors.chip,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.campaign_outlined,
            size: 18,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(width: AppTokens.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                AppStrings.noticesPeekTitle,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.ink,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
      ],
    );
  }
}

class _ClassroomShortcutCard extends StatelessWidget {
  const _ClassroomShortcutCard();

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      onTap: () => context.go('/classroom'),
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
              Icons.meeting_room_outlined,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.findClassroomTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: AppTokens.spaceXs),
                Text(
                  AppStrings.findClassroomSubtitle,
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
        ],
      ),
    );
  }
}


class _AcademicsShortcutCard extends StatelessWidget {
  const _AcademicsShortcutCard();

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      onTap: () => context.push('/academics'),
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
              Icons.school_outlined,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.academicsTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: AppTokens.spaceXs),
                Text(
                  AppStrings.academicsSubtitle,
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
        ],
      ),
    );
  }
}

class _CalendarShortcutCard extends StatelessWidget {
  const _CalendarShortcutCard();

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      onTap: () => context.push('/calendar'),
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
              Icons.calendar_month_outlined,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.calendarTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: AppTokens.spaceXs),
                Text(
                  AppStrings.calendarHubSubtitle,
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppTokens.spaceMd,
      crossAxisSpacing: AppTokens.spaceMd,
      childAspectRatio: 1.7,
      children: [
        _ActionTile(
          icon: Icons.calendar_view_week,
          label: AppStrings.navSchedule,
          onTap: () => context.go('/schedule'),
        ),
        _ActionTile(
          icon: Icons.meeting_room_outlined,
          label: AppStrings.classroomTitle,
          onTap: () => context.go('/classroom'),
        ),
        _ActionTile(
          icon: Icons.campaign_outlined,
          label: AppStrings.noticesTitle,
          onTap: () => context.go('/notices'),
        ),
        _ActionTile(
          icon: Icons.alarm,
          label: AppStrings.createAlarms,
          onTap: () => context.go('/alarms'),
        ),
        _ActionTile(
          icon: Icons.school_outlined,
          label: AppStrings.academicsTitle,
          onTap: () => context.push('/academics'),
        ),
        _ActionTile(
          icon: Icons.calendar_month_outlined,
          label: AppStrings.calendarTitle,
          onTap: () => context.push('/calendar'),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppTokens.spaceMd + 2),
      radius: AppTokens.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.chip,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: AppColors.navy),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
