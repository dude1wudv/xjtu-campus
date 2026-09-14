import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_surface_card.dart';

/// Hub for grades + exams (keeps bottom tabs at 5).
class AcademicsPage extends StatelessWidget {
  const AcademicsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.academicsTitle),
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
      ),
      body: ListView(
        padding: AppTokens.pagePadding,
        children: [
          Text(
            AppStrings.academicsSubtitle,
            style: const TextStyle(color: AppColors.inkSoft, height: 1.4),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          _HubTile(
            icon: Icons.grade_outlined,
            title: AppStrings.gradesTitle,
            subtitle: AppStrings.gradesHubSubtitle,
            onTap: () => context.push('/grades'),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          _HubTile(
            icon: Icons.edit_calendar_outlined,
            title: AppStrings.examsTitle,
            subtitle: AppStrings.examsHubSubtitle,
            onTap: () => context.push('/exams'),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          _HubTile(
            icon: Icons.calendar_month_outlined,
            title: AppStrings.calendarTitle,
            subtitle: AppStrings.calendarHubSubtitle,
            onTap: () => context.push('/calendar'),
          ),
          const SizedBox(height: AppTokens.spaceXl),
          const Text(
            // TODO(ncard): 校园卡余额/流水 — deferred; see docs/grades-exams-calendar.md
            AppStrings.campusCardDeferredNote,
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      onTap: onTap,
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
            child: Icon(icon, color: AppColors.navy),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceXs),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkSoft,
                  ),
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
