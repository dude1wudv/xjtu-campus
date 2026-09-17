import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/homework.dart';
import 'homework_providers.dart';

String homeworkDeadline(Homework item) => item.dueAt == null ? '未设置截止时间'
    : '${DateFormat('M月d日 HH:mm').format(campusTime(item.dueAt!))} 截止（北京时间）';

class HomeworkTile extends StatelessWidget {
  const HomeworkTile({super.key, required this.item});
  final Homework item;
  @override
  Widget build(BuildContext context) => AppSurfaceCard(
    margin: const EdgeInsets.only(bottom: 10),
    onTap: () => context.push('/homework/${item.id}', extra: item),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.assignment_outlined, color: AppColors.accent),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('${item.courseName}${item.group ? ' · 小组作业' : ''}'),
        Text(homeworkDeadline(item), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Text('${item.status.label}${item.overdue && item.status != HomeworkStatus.submitted ? ' · 已过截止时间' : ''}',
          style: TextStyle(fontSize: 12, color: item.status == HomeworkStatus.submitted
              ? AppColors.success : item.overdue ? AppColors.gold : AppColors.inkSoft)),
      ])),
      const Icon(Icons.chevron_right, color: AppColors.inkSoft),
    ]),
  );
}

class HomeworkHomeCard extends ConsumerWidget {
  const HomeworkHomeCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (!auth.initialized || !auth.isLoggedIn || auth.user.isDemo) return const SizedBox.shrink();
    final value = ref.watch(homeworkProvider);
    final data = value.asData?.value;
    final now = DateTime.now();
    final upcoming = (data?.items ?? const <Homework>[]).where((item) =>
      item.status != HomeworkStatus.submitted && item.dueAt != null &&
      !item.dueAt!.isBefore(now) && item.dueAt!.isBefore(now.add(const Duration(days: 7))))
      .take(3).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('近期作业', style: Theme.of(context).textTheme.titleMedium)),
          TextButton(onPressed: () => context.push('/homework'), child: const Text('全部作业')),
        ]),
        if (data?.fromCache == true)
          const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('正在显示缓存，截止时间及提交状态请以学校最新信息为准')),
        if (upcoming.isEmpty) AppSurfaceCard(
          onTap: () => context.push('/homework'),
          child: Text(value.isLoading ? '正在同步思源学堂作业…'
              : value.hasError ? '作业暂未同步，点击登录或重试'
              : data?.failedCourses != 0 && data != null ? '部分课程未同步，点击查看'
              : '未来 7 天暂无已知截止作业'),
        ),
        for (final item in upcoming) HomeworkTile(item: item),
      ]),
    );
  }
}
