import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/network/campus_connection.dart';
import '../../../core/sync/campus_preload.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../notifications/presentation/dean_notices_webview_loader.dart';

class CampusConnectionCard extends ConsumerWidget {
  const CampusConnectionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    ref.watch(campusConnectionRevisionProvider);
    final session = ref.read(campusSessionProvider);
    final progress = ref.watch(campusPreloadProvider);
    final notices = ref.watch(liveDeanNoticesProvider);
    final connecting = ref.watch(campusConnectionBusyProvider);
    const labels = {
      PreloadStatus.waiting: '等待', PreloadStatus.loading: '同步中',
      PreloadStatus.ready: '已更新', PreloadStatus.cached: '已有缓存',
      PreloadStatus.failed: '待重试',
    };
    return AppSurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.vpn_lock_outlined, color: AppColors.navy),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(session.useWebVpn ? 'WebVPN 访问已启用' : '校园服务连接',
                style: Theme.of(context).textTheme.titleMedium),
            Text(session.useWebVpn ? '校园功能统一通过 WebVPN 访问' : '校外使用时，先连接学校 WebVPN',
                style: Theme.of(context).textTheme.bodySmall),
          ])),
        ]),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: auth.initialized && !connecting ? () => context.push('/webvpn') : null,
          icon: const Icon(Icons.link_rounded),
          label: Text(session.useWebVpn ? '重新连接 WebVPN' : '一键连接 WebVPN'),
        ),
        if (session.useWebVpn)
          TextButton(
            onPressed: connecting ? null : () async {
              await session.setUseWebVpn(false);
              ref.read(campusConnectionRevisionProvider.notifier).changed();
            },
            child: const Text('已在校园网？切换为直连'),
          ),
        if (progress.services.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(progress.busy
              ? '后台同步 ${progress.completed}/${progress.services.length} · 可继续使用'
              : '首轮同步已结束 · 未成功项目可单独重试',
              style: Theme.of(context).textTheme.bodySmall),
          if (progress.busy) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress.completed / progress.services.length),
          ],
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('查看同步详情', style: TextStyle(fontSize: 13)),
            children: [
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final entry in progress.services.entries)
                  Chip(label: Text('${entry.key} · ${labels[entry.value]}')),
                Chip(label: Text('通知 · ${notices.isLoading ? '同步中' : notices.isSuccess ? '已更新' : '待重试'}')),
              ]),
              if (!progress.busy)
                TextButton(
                  onPressed: () {
                    ref.read(campusPreloadProvider.notifier).retry();
                    if (notices.isFailed) ref.read(deanNoticesReloadTickProvider.notifier).bump();
                  },
                  child: const Text('重试未同步的项目'),
                ),
            ],
          ),
        ],
      ]),
    );
  }
}
