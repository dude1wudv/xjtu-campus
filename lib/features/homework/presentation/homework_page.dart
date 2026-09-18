import '../../../core/widgets/data_status_banner.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_page_scaffold.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/homework_repository.dart';
import '../domain/homework.dart';
import 'homework_providers.dart';
import 'homework_widgets.dart';

Future<void> openHomeworkSite(BuildContext context, WidgetRef ref) async {
  await context.push(
    '/browser',
    extra: {'url': HomeworkRepository.origin, 'title': '思源学堂'},
  );
  if (!context.mounted) return;
  ref.invalidate(homeworkProvider);
  ref.invalidate(homeworkDetailProvider);
  ref.invalidate(homeworkTermProvider);
}

class HomeworkPage extends ConsumerStatefulWidget {
  const HomeworkPage({super.key});
  @override
  ConsumerState<HomeworkPage> createState() => _HomeworkPageState();
}

class _HomeworkPageState extends ConsumerState<HomeworkPage> {
  String? _term;
  String _query = '';
  Future<void> _refresh() async {
    if (_term case final term?) {
      ref.invalidate(homeworkTermProvider(term));
      try {
        await ref.read(homeworkTermProvider(term).future);
      } catch (_) {}
    } else {
      ref.invalidate(homeworkProvider);
      try {
        await ref.read(homeworkProvider.future);
      } catch (_) {}
    }
  }

  int? _course;
  String _filter = '全部';
  @override
  Widget build(BuildContext context) {
    final current = ref.watch(homeworkProvider);
    final value = _term == null
        ? current
        : ref.watch(homeworkTermProvider(_term!));
    final terms = {
      for (final term in current.asData?.value.terms ?? <HomeworkTerm>[])
        term.id: term,
      for (final term in value.asData?.value.terms ?? <HomeworkTerm>[])
        term.id: term,
    };
    final statuses = ref.watch(homeworkStatusesProvider);
    final data = value.asData?.value;
    final courses = <int, String>{
      for (final item in data?.items ?? <Homework>[])
        item.courseId: item.courseName,
    };
    final effectiveCourse = courses.containsKey(_course) ? _course : null;
    final items = (data?.items ?? <Homework>[])
        .map(
          (item) => statuses.containsKey(item.id)
              ? item.withStatus(statuses[item.id]!)
              : item,
        )
        .where(
          (item) =>
              (effectiveCourse == null || item.courseId == effectiveCourse) &&
              '${item.title} ${item.courseName}'.toLowerCase().contains(
                _query.toLowerCase(),
              ) &&
              (_filter == '全部' ||
                  (_filter == '待确认' && item.status == HomeworkStatus.unknown) ||
                  (_filter == '未提交' && item.status == HomeworkStatus.pending) ||
                  (_filter == '已提交' &&
                      item.status == HomeworkStatus.submitted) ||
                  (_filter == '已截止' && item.overdue)),
        )
        .toList();
    return AppPageScaffold(
      appBar: AppBar(
        title: const Text('作业中心'),
        actions: [
          IconButton(
            tooltip: '思源学堂',
            icon: const Icon(Icons.open_in_browser),
            onPressed: () => openHomeworkSite(context, ref),
          ),
          IconButton(
            tooltip: '同步作业',
            icon: const Icon(Icons.refresh),
            onPressed: value.isLoading ? null : _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          padding: AppTokens.pagePadding,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: items.length + 1,
          itemBuilder: (context, index) {
            if (index > 0) {
              final item = items[index - 1];
              return HomeworkTile(item: item);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_term == null) ...[
                  ServiceStatusBanner(
                    service: 'homework',
                    onRetry: _refresh,
                    onLogin: () =>
                        ref.read(authControllerProvider).user.isGuest ||
                            ref.read(authControllerProvider).user.isDemo
                        ? context.push('/login')
                        : openHomeworkSite(context, ref),
                  ),
                  const SizedBox(height: 12),
                ],
                AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '思源学堂 · ${data?.termLabel ?? (_term == null ? '本学期' : terms[_term]?.label ?? '所选学期')}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '默认仅同步本学期作业，其他学期按需加载。打开详情更新提交状态，小组作业请到学校页面确认。',
                      ),
                      if (data != null)
                        Text(
                          '${data.fromCache ? '缓存' : '更新于'} ${DateFormat('M/d HH:mm').format(campusTime(data.updatedAt))}（北京时间）',
                        ),
                      if (data?.fromCache == true)
                        const Text('当前显示缓存，可下拉重新同步。'),
                      if ((data?.failedCourses ?? 0) > 0)
                        Text('${data!.failedCourses} 门课程未同步，当前列表可能不完整。'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButton<String>(
                  isExpanded: true,
                  value: _term,
                  hint: const Text('本学期'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('本学期（默认）'),
                    ),
                    for (final term in terms.values)
                      DropdownMenuItem(
                        value: term.id,
                        child: Text(
                          term.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (_term != null && !terms.containsKey(_term))
                      DropdownMenuItem(value: _term, child: const Text('所选学期')),
                  ],
                  onChanged: (term) => setState(() {
                    _term = term;
                    _course = null;
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (text) => setState(() => _query = text.trim()),
                  decoration: const InputDecoration(
                    hintText: '搜索课程或作业',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 8),
                if (courses.isNotEmpty)
                  DropdownButton<int>(
                    isExpanded: true,
                    value: effectiveCourse,
                    hint: const Text('全部课程'),
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('全部课程'),
                      ),
                      for (final entry in courses.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(
                            entry.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (course) => setState(() => _course = course),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final filter in ['全部', '待确认', '未提交', '已提交', '已截止'])
                      ChoiceChip(
                        label: Text(filter),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (value.isLoading) const LinearProgressIndicator(),
                if (value.hasError && !value.isLoading)
                  _HomeworkError(error: value.error),
                if (data != null && items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('当前筛选范围暂无作业', textAlign: TextAlign.center),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class HomeworkDetailPage extends ConsumerWidget {
  const HomeworkDetailPage({super.key, required this.id, this.initialItem});
  final Homework? initialItem;
  final int id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(homeworkProvider).asData?.value;
    Homework? item = initialItem;
    for (final entry in summary?.items ?? <Homework>[]) {
      if (entry.id == id) {
        item = entry;
        break;
      }
    }
    final detail = ref.watch(homeworkDetailProvider(id));
    ref.listen(homeworkDetailProvider(id), (previous, next) {
      final value = next.asData?.value;
      if (value != null) {
        ref.read(homeworkProvider.notifier).updateStatus(id, value.status);
        ref.read(homeworkStatusesProvider.notifier).update(id, value.status);
      }
    });
    return AppPageScaffold(
      appBar: AppBar(
        title: const Text('作业详情'),
        actions: [
          IconButton(
            tooltip: '刷新详情',
            icon: const Icon(Icons.refresh),
            onPressed: detail.isLoading
                ? null
                : () => ref.invalidate(homeworkDetailProvider(id)),
          ),
        ],
      ),
      body: ListView(
        padding: AppTokens.pagePadding,
        children: [
          if (item != null) ...[
            Text(item.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(item.courseName),
            Text(homeworkDeadline(item)),
            const SizedBox(height: 16),
          ],
          if (detail.isLoading) const LinearProgressIndicator(),
          if (detail.hasError && !detail.isLoading)
            _HomeworkError(error: detail.error),
          if (detail.asData?.value case final data?)
            AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.status.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    data.description.isEmpty
                        ? '学校未提供文字说明，请打开思源学堂查看。'
                        : data.description,
                  ),
                  if (data.attachments.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('附件（在思源学堂中查看或下载）'),
                    for (final name in data.attachments)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('• $name'),
                      ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => openHomeworkSite(context, ref),
            icon: const Icon(Icons.open_in_browser),
            label: const Text('前往思源学堂查看或提交'),
          ),
          const SizedBox(height: 8),
          const Text('返回后自动更新作业。图片、公式、附件和小组提交结果以学校页面为准。'),
        ],
      ),
    );
  }
}

class _HomeworkError extends ConsumerWidget {
  const _HomeworkError({this.error});
  final Object? error;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final needsAccount = user.isGuest || user.isDemo;
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            needsAccount
                ? '请先登录学校账号查看个人作业。'
                : error is HomeworkAuthRequired
                ? '思源学堂需要认证，请登录后返回。'
                : '作业暂未同步，请稍后刷新重试。',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => needsAccount
                ? context.push('/login')
                : openHomeworkSite(context, ref),
            child: Text(needsAccount ? '登录学校账号' : '打开思源学堂'),
          ),
        ],
      ),
    );
  }
}
