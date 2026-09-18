import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_page_scaffold.dart';
import '../../schedule/presentation/schedule_providers.dart';
import '../../schedule/presentation/schedule_transfer.dart';

class WebInfoPage extends ConsumerWidget {
  const WebInfoPage({super.key, this.settings = false});
  final bool settings;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AppPageScaffold(
    appBar: AppBar(
      title: Text(settings ? '网页端设置' : '在网页端使用校园助手'),
      leading: settings
          ? null
          : IconButton(
              tooltip: '返回首页',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/home'),
            ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.laptop_mac, size: 56),
        const SizedBox(height: 24),
        Text('课表随行，大屏更清晰', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        const Text('网页端支持首页、周课表、课程详情和本地笔记。可以浏览示例，或从客户端导出课表 JSON 后导入自己的课程。'),
        const SizedBox(height: 20),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              '学校登录与实时服务暂限客户端使用。浏览器的跨域和会话限制使静态网页无法直接复用客户端登录。本页不会收集校园密码。\n\n导入课表和笔记仅保存在当前浏览器，不会跨设备同步；清除浏览器数据也会删除它们。',
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => showScheduleTransfer(
            context,
            ref,
            ref.read(scheduleSnapshotProvider).asData?.value,
          ),
          child: const Text('管理本地课表'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.go('/schedule'),
          child: const Text('查看周课表'),
        ),
      ],
    ),
  );
}
