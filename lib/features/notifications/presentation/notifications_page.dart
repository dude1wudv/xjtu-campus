import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_feedback.dart';
import '../domain/notice_filter.dart';
import '../domain/school_notice.dart';

class NoticeFilterController extends Notifier<NoticeFilterRule> {
  @override
  NoticeFilterRule build() => const NoticeFilterRule();

  void setCategory(NoticeCategory? category) {
    state = NoticeFilterRule(category: category, keyword: state.keyword);
  }
}

final noticeFilterProvider =
    NotifierProvider<NoticeFilterController, NoticeFilterRule>(
      NoticeFilterController.new,
    );

final noticesProvider = FutureProvider<List<SchoolNotice>>((ref) {
  final rule = ref.watch(noticeFilterProvider);
  return ref.watch(notificationsRepositoryProvider).fetchNotices(rule: rule);
});

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(noticeFilterProvider);
    final notices = ref.watch(noticesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.noticesTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MockDataBanner(),
                const SizedBox(height: 8),
                const Text(AppStrings.filterRulesHint),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: const Text(AppStrings.filterAll),
                      selected: filter.category == null,
                      onSelected: (_) => ref
                          .read(noticeFilterProvider.notifier)
                          .setCategory(null),
                    ),
                    for (final category in NoticeCategory.values)
                      FilterChip(
                        label: Text(category.label),
                        selected: filter.category == category,
                        onSelected: (_) => ref
                            .read(noticeFilterProvider.notifier)
                            .setCategory(category),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: notices,
              onRetry: () => ref.invalidate(noticesProvider),
              builder: (items) {
                if (items.isEmpty) {
                  return const EmptyHint(
                    icon: Icons.notifications_off_outlined,
                    text: AppStrings.emptyNotices,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _NoticeCard(notice: items[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});

  final SchoolNotice notice;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('M月d日 HH:mm', 'zh_CN').format(notice.publishedAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(notice.category.label),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                ),
                const SizedBox(width: 8),
                Text(notice.source, style: Theme.of(context).textTheme.bodySmall),
                const Spacer(),
                if (notice.pinned)
                  const Icon(Icons.push_pin, size: 16, color: AppColors.gold),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              notice.title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 6),
            Text(notice.summary),
            const SizedBox(height: 6),
            Text(date, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
