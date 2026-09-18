import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/widgets/app_page_scaffold.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../attendance/presentation/course_attendance_badge.dart';
import '../../homework/presentation/homework_providers.dart';
import '../../homework/presentation/homework_widgets.dart';
import '../domain/course.dart';
import 'course_tile.dart';
import 'schedule_providers.dart';
import 'schedule_status.dart';

class CourseDetailPage extends ConsumerWidget {
  const CourseDetailPage({super.key, required this.id, required this.day});
  final String id;
  final DateTime day;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(scheduleSnapshotProvider);
    final data = value.asData?.value;
    final matches = data?.courses.where((c) => c.id == id);
    final course = matches == null || matches.isEmpty ? null : matches.first;
    final auth = ref.watch(authControllerProvider);
    final actual = !kIsWeb && auth.isLoggedIn && !auth.user.isDemo;
    return AppPageScaffold(
      appBar: AppBar(
        title: const Text('课程详情'),
        leading: IconButton(
          tooltip: '返回课表',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/schedule');
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ScheduleStatus(value: value),
          if (course == null && value.isLoading)
            const ScheduleSkeleton()
          else if (course == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text('当前课表中未找到这门课。课表可能已经更新，或尚未导入。'),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => context.go('/schedule'),
                      child: const Text('返回课表'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: courseColor(course).withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.menu_book_outlined,
                    color: courseColor(course),
                    size: 32,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.name,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${course.teacher.isEmpty ? '教师待同步' : course.teacher} · ${course.weeksLabel}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _Info(
                      icon: Icons.schedule,
                      title: '上课时间',
                      text:
                          '${day.month}月${day.day}日 · 周${'一二三四五六日'[course.weekday - 1]}\n${course.periodLabelFor(day)}',
                    ),
                    const Divider(height: 30),
                    _Info(
                      icon: Icons.location_on_outlined,
                      title: '上课地点',
                      text: course.location,
                    ),
                    if (actual) ...[
                      const Divider(height: 30),
                      CourseAttendanceBadge(course: course, day: day),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _CourseNotes(
              key: ValueKey(
                '${auth.user.studentId}|${data?.termStart}|${course.name}|${course.teacher}',
              ),
              storageKey:
                  'course.notes.v1.${Uri.encodeComponent('${auth.user.studentId}|${data?.termStart}|${course.name}|${course.teacher}')}',
            ),
            const SizedBox(height: 24),
            if (actual)
              _RelatedHomework(course: course)
            else
              const Text('作业与考勤需在客户端登录校园账号后查看。当前页面不会把演示数据当作真实记录。'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (!kIsWeb)
                  OutlinedButton.icon(
                    onPressed: () => context.push('/alarms'),
                    icon: const Icon(Icons.alarm),
                    label: const Text('管理课程提醒'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/schedule'),
                  icon: const Icon(Icons.calendar_view_week),
                  label: const Text('查看完整课表'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 22),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(text),
          ],
        ),
      ),
    ],
  );
}

class _RelatedHomework extends ConsumerWidget {
  const _RelatedHomework({required this.course});
  final Course course;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(homeworkProvider);
    final items = value.asData?.value.items
        .where((h) => h.courseName.trim() == course.name.trim())
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('课程作业', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('按课程名称匹配，请以思源学堂记录为准。'),
        const SizedBox(height: 12),
        if (value.isLoading)
          const LinearProgressIndicator()
        else if (value.hasError)
          TextButton(
            onPressed: () => context.push('/homework'),
            child: const Text('作业暂未同步，前往作业中心重试'),
          )
        else if (items == null || items.isEmpty)
          const Text('暂无已同步的相关作业')
        else
          for (final item in items) HomeworkTile(item: item),
      ],
    );
  }
}

class _CourseNotes extends StatefulWidget {
  const _CourseNotes({super.key, required this.storageKey});
  final String storageKey;
  @override
  State<_CourseNotes> createState() => _CourseNotesState();
}

class _CourseNotesState extends State<_CourseNotes> {
  final controller = TextEditingController();
  String status = '正在读取笔记';
  bool loaded = false;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      controller.text = prefs.getString(widget.storageKey) ?? '';
      setState(() {
        loaded = true;
        status = '仅保存在当前设备，请点击保存';
      });
    } catch (_) {
      if (mounted) setState(() => status = '无法读取本地存储，请检查浏览器设置');
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setString(widget.storageKey, controller.text);
      if (mounted) setState(() => status = ok ? '已保存到当前设备' : '保存失败，请重试');
    } catch (_) {
      if (mounted) setState(() => status = '保存失败，请检查存储权限后重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('我的课程笔记', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            enabled: loaded && !saving,
            maxLines: 5,
            maxLength: 10000,
            onChanged: (_) => setState(() => status = '有未保存的修改'),
            decoration: const InputDecoration(
              hintText: '记下教材、上课要求，或下次想问老师的问题…',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: loaded && !saving ? save : null,
                style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
                child: Text(saving ? '保存中' : '保存笔记'),
              ),
              Text(status, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    ),
  );
}
