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
import '../domain/exam_arrangement.dart';
import 'exams_providers.dart';
import '../../../core/widgets/manual_refresh_button.dart';

class ExamsPage extends ConsumerWidget {
  const ExamsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(examsSnapshotProvider);
    final auth = ref.watch(authControllerProvider);

    return AppPageScaffold(
      appBar: AppBar(
        title: const Text(AppStrings.examsTitle),
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
                ref.read(examsSnapshotProvider.notifier).refresh(force: true),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(examsSnapshotProvider.notifier).refresh(force: true),
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
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              AppStrings.examsSubtitle,
              style: const TextStyle(color: AppColors.inkSoft, fontSize: 13),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            if (!auth.isLoggedIn)
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(AppStrings.examsLoginHint),
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
              onRetry: () => ref.read(examsSnapshotProvider.notifier).refresh(force: true),
              builder: (data) {
                if (data.exams.isEmpty) {
                  return const AppSurfaceCard(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: AppTokens.spaceLg),
                      child: Center(
                        child: Text(
                          AppStrings.emptyExams,
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final exam in data.exams) ...[
                      _ExamTile(exam: exam),
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

class _ExamTile extends StatelessWidget {
  const _ExamTile({required this.exam});

  final ExamArrangement exam;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exam.courseName,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          _row(Icons.schedule_rounded, exam.dateTimeLabel),
          const SizedBox(height: AppTokens.spaceSm),
          _row(Icons.place_outlined, exam.location),
          if (exam.campus != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            _row(Icons.apartment_outlined, exam.campus!),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.inkSoft),
        const SizedBox(width: AppTokens.spaceSm),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13.5, color: AppColors.ink),
          ),
        ),
      ],
    );
  }
}
