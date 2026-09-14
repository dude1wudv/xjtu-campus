import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

final noticesSnapshotProvider = FutureProvider((ref) {
  final rule = ref.watch(noticeFilterProvider);
  return ref.watch(notificationsRepositoryProvider).load(rule: rule);
});

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(noticeFilterProvider);
    final snapshot = ref.watch(noticesSnapshotProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.noticesTitle),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => ref.invalidate(noticesSnapshotProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                snapshot.when(
                  data: (data) => DataSourceBanner(
                    live: data.live,
                    message: data.banner,
                  ),
                  loading: () => const DataSourceBanner(),
                  error: (_, _) => const DataSourceBanner(),
                ),
                const SizedBox(height: 12),
                Text(
                  AppStrings.filterRulesHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: const Text(AppStrings.filterAll),
                          selected: filter.category == null,
                          onSelected: (_) => ref
                              .read(noticeFilterProvider.notifier)
                              .setCategory(null),
                        ),
                      ),
                      for (final category in NoticeCategory.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(category.label),
                            selected: filter.category == category,
                            onSelected: (_) => ref
                                .read(noticeFilterProvider.notifier)
                                .setCategory(category),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: snapshot,
              onRetry: () => ref.invalidate(noticesSnapshotProvider),
              builder: (data) {
                final items = data.notices;
                if (items.isEmpty) {
                  return const EmptyHint(
                    icon: Icons.notifications_off_outlined,
                    text: AppStrings.emptyNotices,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
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
    final date = DateFormat('yyyy-MM-dd', 'zh_CN').format(notice.publishedAt);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: notice.url == null
            ? null
            : () {
                final url = Uri.encodeComponent(notice.url!);
                final title = Uri.encodeComponent(notice.title);
                context.push('/browser?url=$url&title=$title');
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.chip,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      notice.category.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    notice.source,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  if (notice.url != null)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.inkSoft.withValues(alpha: 0.7),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                notice.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15.5,
                  height: 1.35,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(notice.summary),
              const SizedBox(height: 8),
              Text(date, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
