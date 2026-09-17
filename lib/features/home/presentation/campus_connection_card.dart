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

class CampusConnectionCard extends ConsumerStatefulWidget {
  const CampusConnectionCard({super.key});

  @override
  ConsumerState<CampusConnectionCard> createState() => _CampusConnectionCardState();
}

class _CampusConnectionCardState extends ConsumerState<CampusConnectionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    ref.watch(campusConnectionRevisionProvider);
    final session = ref.read(campusSessionProvider);
    final progress = ref.watch(campusPreloadProvider);
    final notices = ref.watch(liveDeanNoticesProvider);
    final connecting = ref.watch(campusConnectionBusyProvider);
    const labels = {
      PreloadStatus.waiting: '等待',
      PreloadStatus.loading: '同步中',
      PreloadStatus.ready: '已更新',
      PreloadStatus.cached: '已有缓存',
      PreloadStatus.failed: '待重试',
    };
    final summary = connecting ? '正在连接'
        : progress.busy ? '后台同步 ${progress.completed}/${progress.services.length}'
        : session.useWebVpn ? '已启用 · 点击管理' : '校外访问 · 点击连接';

    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: _expanded,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  const Icon(Icons.vpn_lock_outlined, color: AppColors.navy, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WebVPN', style: Theme.of(context).textTheme.titleSmall),
                      Text(summary, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  )),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.inkSoft),
                ]),
              ),
            ),
          ),
          // Build details only when opened; no offstage expansion subtree or
          // unbounded Column is retained in the dashboard's scrolling list.
          if (_expanded) Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: auth.initialized && !connecting
                      ? () => context.push('/webvpn') : null,
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: Text(session.useWebVpn ? '重新连接 WebVPN' : '一键连接 WebVPN'),
                ),
                if (session.useWebVpn) TextButton(
                  onPressed: connecting ? null : () async {
                    await session.setUseWebVpn(false);
                    if (!mounted) return;
                    ref.read(campusConnectionRevisionProvider.notifier).changed();
                  },
                  child: const Text('切换校园网直连'),
                ),
                if (progress.services.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('校园服务同步', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  if (progress.busy) LinearProgressIndicator(
                    value: progress.completed / progress.services.length,
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final entry in progress.services.entries)
                      _SyncLabel('${entry.key} · ${labels[entry.value]}'),
                    _SyncLabel('通知 · ${notices.isLoading ? '同步中' : notices.isSuccess ? '已更新' : '待重试'}'),
                  ]),
                  if (!progress.busy) TextButton(
                    onPressed: () {
                      ref.read(campusPreloadProvider.notifier).retry();
                      if (notices.isFailed) {
                        ref.read(deanNoticesReloadTickProvider.notifier).bump();
                      }
                    },
                    child: const Text('重试未同步的项目'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncLabel extends StatelessWidget {
  const _SyncLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.chip,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    ),
  );
}
