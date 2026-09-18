import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../domain/schedule_repository.dart';
import 'schedule_providers.dart';

class ScheduleStatus extends ConsumerWidget {
  const ScheduleStatus({super.key, required this.value});
  final AsyncValue<ScheduleSnapshot> value;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = value.asData?.value;
    final expired = data?.failure == ScheduleFailure.sessionExpired;
    final failed = value.hasError || data?.failure != null;
    final cached = data?.fromCache == true;
    final demo = data != null && !data.live && !data.imported && !failed;
    final title = expired
        ? '登录已过期'
        : failed
        ? '暂时无法连接校园服务'
        : data?.imported == true
        ? '本地课表'
        : cached
        ? '上次同步的课表'
        : value.isLoading
        ? '正在同步课表'
        : demo
        ? '正在浏览演示课表'
        : '课表已同步';
    final stamp = data?.cachedAt ?? data?.fetchedAt;
    final detail = expired
        ? '请重新登录。${cached ? '上次课表仍可查看。' : '登录后恢复同步。'}'
        : failed
        ? '${cached ? '已保留上次课表。' : '暂无可用课表。'}请检查网络或校园网连接后重试。'
        : data?.imported == true
        ? '仅保存在当前浏览器；学校调整课程后请重新导入。'
        : demo
        ? (kIsWeb ? '网页端可导入客户端课表；示例课程不代表你的真实安排。' : '登录校园账号后查看自己的课程。')
        : stamp != null
        ? '更新于 ${DateFormat('M月d日 HH:mm').format(stamp.toLocal())}'
        : '正在整理课程安排，请稍候。';
    final color = failed || cached || demo
        ? const Color(0xFF986421)
        : const Color(0xFF176B62);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .065),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            expired
                ? Icons.lock_clock_outlined
                : failed
                ? Icons.cloud_off_outlined
                : demo
                ? Icons.science_outlined
                : Icons.cloud_done_outlined,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w600, color: color),
                ),
                const SizedBox(height: 3),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (expired || (demo && !kIsWeb))
            TextButton(
              onPressed: () => context.push('/login'),
              child: Text(expired ? '重新登录' : '去登录'),
            )
          else if (failed)
            TextButton(
              onPressed: () async {
                try {
                  await ref.read(scheduleSnapshotProvider.notifier).refresh();
                } catch (_) {
                  /* Error stays visible in provider. */
                }
              },
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }
}

class ScheduleSkeleton extends StatelessWidget {
  const ScheduleSkeleton({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在加载课程',
    child: Column(
      children: [
        const LinearProgressIndicator(minHeight: 2),
        for (var i = 0; i < 3; i++)
          Container(
            height: 92,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8EDF1),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
      ],
    ),
  );
}
