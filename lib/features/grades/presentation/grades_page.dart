import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_page_scaffold.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/grade_record.dart';
import '../domain/grade_stats.dart';
import 'grades_providers.dart';
import '../../../core/widgets/manual_refresh_button.dart';

class GradesPage extends ConsumerStatefulWidget {
  const GradesPage({super.key});

  @override
  ConsumerState<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends ConsumerState<GradesPage> {
  /// null = 全部
  String? _selectedTerm;

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(gradesSnapshotProvider);
    final auth = ref.watch(authControllerProvider);

    return AppPageScaffold(
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
        actions: [
          ManualRefreshButton(
            onRefresh: () =>
                ref.read(gradesSnapshotProvider.notifier).refresh(force: true),
          ),
        ],
      ),
      body: AsyncBody(
        value: snap,
        onRetry: () =>
            ref.read(gradesSnapshotProvider.notifier).refresh(force: true),
        builder: (data) {
          final grouped = data.effectiveGrouped;
          final selected = grouped.containsKey(_selectedTerm)
              ? _selectedTerm
              : null;
          final visible = selected == null
              ? data.records
              : grouped[selected] ?? const <GradeRecord>[];
          final groups = selected == null
              ? grouped.entries
              : [MapEntry(selected, visible)];
          // Flatten data, not widgets: only visible transcript rows are built.
          final rows = <({String? term, int count, GradeRecord? record})>[
            for (final group in groups) ...[
              (term: group.key, count: group.value.length, record: null),
              for (final record in group.value)
                (term: null, count: 0, record: record),
            ],
          ];
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(gradesSnapshotProvider.notifier).refresh(force: true),
            child: CustomScrollView(
              key: PageStorageKey('grades-${selected ?? 'all'}'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: AppTokens.pagePadding.copyWith(
                    bottom: AppTokens.spaceMd,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DataSourceBanner(
                          service: 'grades',
                          onRetry: () => ref.invalidate(gradesSnapshotProvider),
                          live: data.live,
                          message: data.banner,
                          fromCache: data.fromCache,
                          cachedAt: data.cachedAt,
                          fetchedAt: data.fetchedAt,
                        ),
                        if (!auth.isLoggedIn) ...[
                          const SizedBox(height: AppTokens.spaceMd),
                          AppSurfaceCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        ],
                        const SizedBox(height: AppTokens.spaceMd),
                        _GpaSummaryCard(
                          filterLabel: selected ?? AppStrings.gradesFilterAll,
                          filterGpa: GradeStats.weightedGpa(visible),
                          filterCredits: GradeStats.countedCredits(visible),
                          overallGpa: selected == null
                              ? null
                              : GradeStats.weightedGpa(data.records),
                        ),
                        const SizedBox(height: AppTokens.spaceMd),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              FilterChip(
                                label: const Text(AppStrings.gradesFilterAll),
                                selected: selected == null,
                                onSelected: (_) =>
                                    setState(() => _selectedTerm = null),
                              ),
                              for (final term in grouped.keys) ...[
                                const SizedBox(width: AppTokens.spaceSm),
                                FilterChip(
                                  label: Text(term),
                                  selected: selected == term,
                                  onSelected: (_) =>
                                      setState(() => _selectedTerm = term),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (data.records.isEmpty)
                          const EmptyHint(
                            icon: Icons.grade_outlined,
                            text: AppStrings.emptyGrades,
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: AppTokens.pagePadding.copyWith(top: 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final row = rows[index];
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppTokens.spaceMd,
                        ),
                        child: row.record == null
                            ? _TermHeader(term: row.term!, count: row.count)
                            : _GradeTile(record: row.record!),
                      );
                    }, childCount: rows.length),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GpaSummaryCard extends StatelessWidget {
  const _GpaSummaryCard({
    required this.filterLabel,
    required this.filterGpa,
    required this.filterCredits,
    this.overallGpa,
  });

  final String filterLabel;
  final double? filterGpa;
  final double filterCredits;
  final double? overallGpa;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            filterLabel,
            style: TextStyle(
              color: AppColors.navy.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Row(
            children: [
              Expanded(
                child: _metric(
                  AppStrings.gradesWeightedGpa,
                  filterGpa == null ? '—' : filterGpa!.toStringAsFixed(2),
                ),
              ),
              Expanded(
                child: _metric(
                  AppStrings.gradesCountedCredits,
                  filterCredits <= 0
                      ? '—'
                      : filterCredits.toStringAsFixed(
                          filterCredits.truncateToDouble() == filterCredits
                              ? 0
                              : 1,
                        ),
                ),
              ),
            ],
          ),
          if (overallGpa != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              '${AppStrings.gradesFilterAll}${AppStrings.gradesWeightedGpa} '
              '${overallGpa!.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
            letterSpacing: -0.3,
          ),
        ),
      ],
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
        Expanded(
          child: Text(term, style: Theme.of(context).textTheme.titleMedium),
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
