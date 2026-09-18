import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/data/data_status.dart';
import '../../../core/data/data_status_provider.dart';
import '../../../core/widgets/app_page_scaffold.dart';
import '../../../core/widgets/data_status_banner.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../homework/domain/homework.dart';
import '../../homework/presentation/homework_page.dart';
import '../domain/task_item.dart';
import 'task_providers.dart';

Future<bool> saveTaskAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未能保存，请检查本机存储后重试。当前内容未更改。')));
    return false;
  }
}

class TodayTaskSummary extends ConsumerWidget {
  const TodayTaskSummary({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(taskClockProvider).asData?.value ?? DateTime.now();
    final items = filterTasks(ref.watch(agendaProvider), TaskFilter.today, now);
    final overdue = items.where((i) => i.overdue(now)).length;
    final upcoming = items
        .where((i) => i.end == null || i.end!.isAfter(now))
        .toList();
    final statuses = ref.watch(dataStatusesProvider);
    final unavailable = ['schedule', 'homework', 'exams'].any((key) {
      final s = statuses[key];
      return s != null && (s.phase != DataPhase.ready || s.problem != null);
    });
    final personal = ref.watch(personalTasksProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.checklist_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '今日任务',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/tasks'),
                  child: const Text('全部任务'),
                ),
              ],
            ),
            Text(
              overdue > 0 ? '$overdue 项已过期 · 优先处理截止事项' : '课程、截止事项与个人待办，一起安排',
            ),
            const SizedBox(height: 12),
            if (personal.isLoading) const LinearProgressIndicator(),
            if (personal.hasError) const Text('个人待办读取失败，请进入任务中心重试。'),
            if (upcoming.isEmpty) const Text('当前没有已知待办；未同步的数据不计入统计。'),
            for (final item in upcoming.take(3))
              TaskTile(item: item, now: now, compact: true),
            if (unavailable)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('部分来源正在同步或需要处理，可在任务中心查看状态。'),
              ),
          ],
        ),
      ),
    );
  }
}

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});
  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  TaskFilter filter = TaskFilter.today;
  bool refreshing = false;
  Future<void> refresh() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    await refreshTaskSources(ref);
    if (mounted) setState(() => refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(taskClockProvider).asData?.value ?? DateTime.now();
    final all = ref.watch(agendaProvider);
    final items = filterTasks(all, filter, now);
    final personal = ref.watch(personalTasksProvider);
    final auth = ref.watch(authControllerProvider);
    final actual = !kIsWeb && auth.isLoggedIn && !auth.user.isDemo;
    return AppPageScaffold(
      appBar: AppBar(
        title: const Text('今日任务中心'),
        actions: [
          IconButton(
            tooltip: '同步校园数据',
            onPressed: refreshing ? null : refresh,
            icon: refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
          children: [
            Text(
              DateFormat('M月d日 EEEE', 'zh_CN').format(campusTime(now)),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '让今天，有条不紊。',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text('统一使用校园时间（UTC+8）。个人待办只保存在本机，清除应用或浏览器数据会丢失。'),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed:
                    !auth.initialized || !personal.hasValue || personal.hasError
                    ? null
                    : () => editPersonalTask(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('添加个人待办'),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ExpansionTile(
                title: const Text('数据来源与同步状态'),
                subtitle: Text(
                  actual
                      ? '课表 · 思源学堂 · 考试安排 · 本机待办'
                      : kIsWeb
                      ? '导入课表 · 本机待办'
                      : '示例课表 · 本机待办',
                ),
                children: [
                  ServiceStatusBanner(service: 'schedule', onRetry: refresh),
                  if (actual) ...[
                    ServiceStatusBanner(
                      service: 'homework',
                      onRetry: refresh,
                      onLogin: () => openHomeworkSite(context, ref),
                    ),
                    ServiceStatusBanner(service: 'exams', onRetry: refresh),
                  ] else
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        kIsWeb
                            ? '网页端暂不连接学校登录，作业和考试未接入。请在课表页导入个人课表。'
                            : '登录真实账号后同步作业和考试；示例课程不代表个人安排。',
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('只展示来源已提供的数据；当前周缓存不能推算未来周。作业提交状态以思源学堂为准。'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in TaskFilter.values)
                  ChoiceChip(
                    label: Text(switch (f) {
                      TaskFilter.today => '今天',
                      TaskFilter.week => '未来 7 天',
                      TaskFilter.overdue => '已过期',
                      TaskFilter.completed => '已完成',
                    }),
                    selected: filter == f,
                    onSelected: (_) => setState(() => filter = f),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('今天 / 未来 7 天包含过期事项和时间待确认事项。'),
            if (personal.isLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            if (personal.hasError)
              DataStatusBanner(
                status: const DataStatus(
                  phase: DataPhase.failed,
                  source: DataSource.none,
                  problem: DataProblem.storage,
                ),
                onRetry: () => ref.invalidate(personalTasksProvider),
              ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text('此范围内没有已知任务。请查看来源状态，确认需要的数据已同步。'),
                ),
              ),
            for (final item in items) TaskTile(item: item, now: now),
          ],
        ),
      ),
    );
  }
}

class TaskTile extends ConsumerWidget {
  const TaskTile({
    super.key,
    required this.item,
    required this.now,
    this.compact = false,
  });
  final AgendaItem item;
  final DateTime now;
  final bool compact;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final late = item.overdue(now);
    final ended =
        item.kind == TaskKind.course &&
        item.end != null &&
        !item.end!.isAfter(now);
    final time = item.at == null
        ? '时间待确认'
        : DateFormat('M/d HH:mm').format(campusTime(item.at!));
    final label =
        '${item.kindLabel} · ${item.source} · ${item.kind == TaskKind.exam ? '时间见考试安排' : time}${late
            ? ' · 已过期'
            : ended
            ? ' · 已结束'
            : ''}';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: item.personal != null
            ? Checkbox(
                value: item.completed,
                onChanged: (_) => saveTaskAction(
                  context,
                  () => ref
                      .read(personalTasksProvider.notifier)
                      .toggle(item.personal!.id),
                ),
              )
            : Icon(switch (item.kind) {
                TaskKind.course => Icons.school_outlined,
                TaskKind.homework => Icons.assignment_outlined,
                TaskKind.exam => Icons.edit_calendar_outlined,
                TaskKind.personal => Icons.check_circle_outline,
              }, color: late ? Theme.of(context).colorScheme.error : null),
        title: Text(
          item.title,
          style: TextStyle(
            decoration: item.completed ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          '$label${item.detail.isEmpty ? '' : '\n${item.detail}'}',
          maxLines: compact ? 3 : null,
          overflow: compact ? TextOverflow.ellipsis : null,
        ),
        onTap: item.personal != null
            ? () => editPersonalTask(context, ref, item.personal)
            : item.route == null
            ? null
            : () => context.push(item.route!, extra: item.extra),
        trailing: item.personal != null && !compact
            ? IconButton(
                tooltip: '删除待办',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final task = item.personal!;
                  final scope = ref.read(taskScopeProvider);
                  final saved = await saveTaskAction(
                    context,
                    () => ref
                        .read(personalTasksProvider.notifier)
                        .remove(task.id),
                  );
                  if (saved && context.mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('待办已删除'),
                        action: SnackBarAction(
                          label: '撤销',
                          onPressed: () => saveTaskAction(context, () {
                            if (ref.read(taskScopeProvider) != scope)
                              throw StateError('账号已切换');
                            return ref
                                .read(personalTasksProvider.notifier)
                                .save(task);
                          }),
                        ),
                      ),
                    );
                },
              )
            : const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}

Future<void> editPersonalTask(
  BuildContext context,
  WidgetRef ref, [
  PersonalTask? task,
]) async {
  final scope = ref.read(taskScopeProvider);
  final result = await showDialog<PersonalTask>(
    context: context,
    builder: (_) => _TaskEditor(task: task),
  );
  if (result == null || !context.mounted) return;
  if (scope != ref.read(taskScopeProvider)) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('账号已切换，请重新添加待办。')));
    return;
  }
  final saved = await saveTaskAction(
    context,
    () => ref.read(personalTasksProvider.notifier).save(result),
  );
  if (!saved && context.mounted) await editPersonalTask(context, ref, result);
}

class _TaskEditor extends StatefulWidget {
  const _TaskEditor({this.task});
  final PersonalTask? task;
  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  late final title = TextEditingController(text: widget.task?.title);
  late final notes = TextEditingController(text: widget.task?.notes);
  late DateTime? due = widget.task?.dueAt;
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.task == null ? '添加个人待办' : '编辑个人待办'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: title,
                autofocus: true,
                maxLength: 120,
                decoration: const InputDecoration(labelText: '要做什么'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请输入待办内容' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: notes,
                minLines: 2,
                maxLines: 4,
                maxLength: 2000,
                decoration: const InputDecoration(labelText: '备注（可选）'),
              ),
              Text(
                due == null
                    ? '未设置截止时间'
                    : '${DateFormat('yyyy/M/d HH:mm').format(campusTime(due!))} · 校园时间',
              ),
              Wrap(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: const Text('设置截止时间'),
                    onPressed: () async {
                      final initial = due == null
                          ? campusTime(DateTime.now())
                          : campusTime(due!);
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime(
                          initial.year,
                          initial.month,
                          initial.day,
                        ),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (date == null || !context.mounted) return;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: initial.hour,
                          minute: initial.minute,
                        ),
                      );
                      if (time != null && mounted)
                        setState(
                          () => due = campusInstant(
                            DateTime(
                              date.year,
                              date.month,
                              date.day,
                              time.hour,
                              time.minute,
                            ),
                          ),
                        );
                    },
                  ),
                  if (due != null)
                    TextButton(
                      onPressed: () => setState(() => due = null),
                      child: const Text('清除时间'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(
            context,
            PersonalTask(
              id: widget.task?.id ?? newTaskId(),
              title: title.text.trim(),
              notes: notes.text.trim(),
              dueAt: due,
              completed: widget.task?.completed ?? false,
            ),
          );
        },
        child: const Text('保存'),
      ),
    ],
  );
}
