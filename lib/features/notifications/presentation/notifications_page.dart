import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_page_scaffold.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_feedback.dart';
import '../domain/notice_filter.dart';
import '../domain/school_notice.dart';
import 'dean_notices_webview_loader.dart';
import '../../../core/widgets/manual_refresh_button.dart';
import '../../../core/cache/snapshot_cache.dart';

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

/// Dio / mock fallback after embedded WebView fails.
final noticesFallbackProvider = FutureProvider<NoticesSnapshot>((ref) {
  final rule = ref.watch(noticeFilterProvider);
  return ref.watch(notificationsRepositoryProvider).load(rule: rule);
});

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  Future<void> _refresh(WidgetRef ref, {bool force = true}) async {
    if (force) {
      await ref.read(snapshotCacheProvider).remove(SnapshotCache.notices);
    }
    ref.read(liveDeanNoticesProvider.notifier).markLoading();
    ref.read(deanNoticesReloadTickProvider.notifier).bump();
    // Clear stale Dio fallback so a later failure reloads.
    ref.invalidate(noticesFallbackProvider);
  }

  NoticesSnapshot _filterNotices(
    List<SchoolNotice> notices,
    NoticeFilterRule rule, {
    required bool live,
    required bool fromCache,
    DateTime? cachedAt,
    DateTime? fetchedAt,
    String? banner,
  }) {
    final filtered = notices.where(rule.matches).toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.publishedAt.compareTo(a.publishedAt);
      });
    return NoticesSnapshot(
      notices: filtered,
      live: live,
      banner: banner ??
          (fromCache
              ? (cachedAt != null
                  ? AppStrings.cacheBanner(cachedAt)
                  : AppStrings.classroomCacheBanner)
              : AppStrings.noticesLiveBanner),
      fromCache: fromCache,
      cachedAt: cachedAt,
      fetchedAt: fetchedAt,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(noticeFilterProvider);
    final live = ref.watch(liveDeanNoticesProvider);

    final AsyncValue<NoticesSnapshot> snapshot;
    if (live.isSuccess && !live.fromCache) {
      snapshot = AsyncValue.data(
        _filterNotices(
          live.notices,
          filter,
          live: true,
          fromCache: false,
          fetchedAt: live.fetchedAt ?? DateTime.now(),
          banner: AppStrings.noticesLiveBanner,
        ),
      );
    } else if (live.notices.isNotEmpty && (live.fromCache || live.isLoading)) {
      // Show cached notices immediately while WebView loads (or after soft fail).
      snapshot = AsyncValue.data(
        _filterNotices(
          live.notices,
          filter,
          live: true,
          fromCache: true,
          cachedAt: live.cachedAt,
          banner: live.isFailed
              ? AppStrings.cacheRefreshFailed
              : (live.cachedAt != null
                  ? AppStrings.cacheBanner(live.cachedAt!)
                  : null),
        ),
      );
    } else if (live.isFailed) {
      snapshot = ref.watch(noticesFallbackProvider);
    } else {
      snapshot = const AsyncValue.loading();
    }

    return AppPageScaffold(
      appBar: AppBar(
        title: const Text(AppStrings.noticesTitle),
        actions: [
          ManualRefreshButton(onRefresh: () => _refresh(ref, force: true)),
        ],
      ),
      body: Stack(
        children: [
          // Real WebView (not Headless): shares CookieManager, runs page JS.
          const Positioned(
            left: 0,
            top: 0,
            child: Opacity(
              opacity: 0,
              child: IgnorePointer(
                child: DeanNoticesWebViewLoader(),
              ),
            ),
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    snapshot.when(
                      skipLoadingOnReload: true,
                      data: (data) => DataSourceBanner(
                        live: data.live,
                        message: data.banner,
                        fromCache: data.fromCache,
                        cachedAt: data.cachedAt,
                        fetchedAt: data.fetchedAt,
                      ),
                      loading: () => const DataSourceBanner(
                        message: '正在通过浏览器加载教务通知…',
                      ),
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
                              showCheckmark: true,
                              checkmarkColor: Colors.white,
                              selectedColor: AppColors.navy,
                              backgroundColor: AppColors.chip,
                              side: const BorderSide(color: AppColors.line),
                              labelStyle: TextStyle(
                                color: filter.category == null
                                    ? Colors.white
                                    : AppColors.navyDeep,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
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
                                showCheckmark: true,
                                checkmarkColor: Colors.white,
                                selectedColor: AppColors.navy,
                                backgroundColor: AppColors.chip,
                                side: const BorderSide(color: AppColors.line),
                                labelStyle: TextStyle(
                                  color: filter.category == category
                                      ? Colors.white
                                      : AppColors.navyDeep,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
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
                  onRetry: () { _refresh(ref, force: true); },
                  builder: (data) {
                    final items = data.notices;
                    if (items.isEmpty) {
                      return RefreshIndicator(
                        onRefresh: () => _refresh(ref, force: true),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          children: const [
                            SizedBox(height: 120),
                            EmptyHint(
                              icon: Icons.notifications_off_outlined,
                              text: AppStrings.emptyNotices,
                            ),
                          ],
                        ),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () => _refresh(ref, force: true),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: AppTokens.pagePadding,
                        itemCount: items.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _NoticeCard(notice: items[index]),
                      ),
                    );
                  },
                ),
              ),
            ],
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
                context.push(
                  '/browser',
                  extra: {
                    'url': notice.url!,
                    'title': notice.title,
                  },
                );
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
