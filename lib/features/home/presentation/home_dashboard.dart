import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../schedule/domain/course.dart';
import '../../schedule/presentation/schedule_providers.dart';

class HomeDashboard extends ConsumerWidget {
  const HomeDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final snapshot = ref.watch(scheduleSnapshotProvider);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          IconButton(
            tooltip: AppStrings.openLogin,
            onPressed: () => context.push('/login'),
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          snapshot.when(
            data: (data) =>
                DataSourceBanner(live: data.live, message: data.banner),
            loading: () => const MockDataBanner(),
            error: (_, _) => const MockDataBanner(),
          ),
          const SizedBox(height: 16),
          _GreetingCard(auth: auth, now: now, week: snapshot.value?.week),
          const SizedBox(height: 16),
          AsyncBody(
            value: snapshot,
            onRetry: () => ref.invalidate(scheduleSnapshotProvider),
            builder: (data) {
              final next = Course.nextAfter(
                data.courses,
                now,
                weekNumber: data.week,
              );
              return _NextClassCard(course: next, now: now);
            },
          ),
          const SizedBox(height: 20),
          Text(
            AppStrings.quickActions,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const _QuickActions(),
        ],
      ),
    );
  }
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

    return Card(
      color: AppColors.navy,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$hello，$name',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              [
                date,
                if (week != null) '${AppStrings.weekPrefix}$week${AppStrings.weekSuffix}',
                AppStrings.termLabel,
              ].join(' · '),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.82)),
            ),
            const SizedBox(height: 12),
            if (!auth.isLoggedIn)
              FilledButton.tonal(
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

class _NextClassCard extends StatelessWidget {
  const _NextClassCard({required this.course, required this.now});

  final Course? course;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (course == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.free_breakfast_outlined),
          title: Text(AppStrings.noClassToday),
        ),
      );
    }
    final item = course!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              AppStrings.nextClass,
              style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              item.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('${item.periodLabel}  ·  ${item.location}'),
            Text(
              '${AppStrings.teacher}：${item.teacher}'
              '${item.weekday == now.weekday ? '  ·  ${AppStrings.today}' : ''}',
            ),
          ],
        ),
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
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
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
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.navy),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
