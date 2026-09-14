import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/grade_record.dart';
import 'grades_providers.dart';

class GradesPage extends ConsumerWidget {
  const GradesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(gradesSnapshotProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.gradesTitle),
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
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(gradesSnapshotProvider),
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
            if (!auth.isLoggedIn)
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(AppStrings.gradesLoginHint),
                    const SizedBox(height: AppTokens.spaceMd),
                    FilledButton(
                      onPressed: () => context.push('/login'),
                      child: const Text(AppStrings.openLogin),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppTokens.spaceMd),
            AsyncBody(
              value: snap,
              onRetry: () => ref.invalidate(gradesSnapshotProvider),
              builder: (data) {
                if (data.groupedByTerm.isEmpty) {
                  return const AppSurfaceCard(
                    child: Text(AppStrings.emptyGrades),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in data.groupedByTerm.entries) ...[
                      _TermHeader(term: entry.key, count: entry.value.length),
                      const SizedBox(height: AppTokens.spaceSm),
                      for (final g in entry.value) ...[
                        _GradeTile(record: g),
                        const SizedBox(height: AppTokens.spaceSm),
                      ],
                      const SizedBox(height: AppTokens.spaceMd),
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

class _TermHeader extends StatelessWidget {
  const _TermHeader({required this.term, required this.count});

  final String term;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          term,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(width: AppTokens.spaceSm),
        Text(
          '$count ${AppStrings.gradesCourseUnit}',
          style: const TextStyle(color: AppColors.inkSoft, fontSize: 13),
        ),
      ],
    );
  }
}

class _GradeTile extends StatelessWidget {
  const _GradeTile({required this.record});

  final GradeRecord record;

  @override
  Widget build(BuildContext context) {
    final gpa = record.gpaPoints;
    return AppSurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLg,
        vertical: AppTokens.spaceMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.courseName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceXs),
                Text(
                  [
                    '${AppStrings.gradesCredit}: ${record.credit}',
                    if (gpa != null)
                      '${AppStrings.gradesGpaPoints}: ${gpa.toStringAsFixed(gpa.truncateToDouble() == gpa ? 1 : 2)}',
                    if (record.courseNature != null) record.courseNature!,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          Container(
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMd,
              vertical: AppTokens.spaceSm,
            ),
            decoration: BoxDecoration(
              color: AppColors.chip,
              borderRadius: AppTokens.borderPill,
            ),
            child: Text(
              record.score.isEmpty ? '—' : record.score,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
