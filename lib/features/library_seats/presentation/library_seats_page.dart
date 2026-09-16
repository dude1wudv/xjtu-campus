import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../../core/widgets/manual_refresh_button.dart';
import '../data/library_seat_areas.dart';
import '../domain/library_seat.dart';
import 'library_seats_providers.dart';

class LibrarySeatsPage extends ConsumerStatefulWidget {
  const LibrarySeatsPage({super.key});

  @override
  ConsumerState<LibrarySeatsPage> createState() => _LibrarySeatsPageState();
}

class _LibrarySeatsPageState extends ConsumerState<LibrarySeatsPage> {
  bool _booking = false;

  Future<void> _confirmBook(LibrarySeat seat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认预约座位'),
        content: Text(
          '座位 ${seat.id}（${LibrarySeatAreas.labelFor(seat.areaCode) ?? seat.areaCode}）\n\n'
          '${AppStrings.librarySeatsFairUse}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认预约'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _booking = true);
    try {
      final result = await ref.read(librarySeatsRepositoryProvider).reserve(
            seatId: seat.id,
            areaCode: seat.areaCode,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      await ref.read(librarySeatsSnapshotProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  Future<void> _openScheduleSheet() async {
    final area = ref.read(librarySeatAreaProvider);
    final existing = await ref.read(librarySeatScheduleStoreProvider).load();
    if (!mounted) return;
    final seatCtrl = TextEditingController(
      text: existing?.preferredSeatId ?? '',
    );
    var areaCode = existing?.preferredAreaCode ?? area;
    var startAt = existing?.startAt.isAfter(DateTime.now()) == true
        ? existing!.startAt
        : DateTime.now().add(const Duration(minutes: 5));
    var maxAttempts = existing?.maxAttempts ?? 8;
    var delayMs = existing?.delayMs ?? 1500;
    final fallback = List<String>.from(
      existing?.fallbackAreaCodes ?? [areaCode],
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '定时预约',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      AppStrings.librarySeatsFairUse,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: seatCtrl,
                      decoration: const InputDecoration(
                        labelText: '偏好座位号（如 Y002）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: areaCode,
                      decoration: const InputDecoration(
                        labelText: '偏好区域',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final a in LibrarySeatAreas.all)
                          DropdownMenuItem(
                            value: a.code,
                            child: Text(a.label, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setModal(() => areaCode = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '开始时间：${DateFormat('M/d HH:mm').format(startAt)}',
                      ),
                      trailing: const Icon(Icons.schedule),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: startAt,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 7)),
                        );
                        if (d == null) return;
                        if (!ctx.mounted) return;
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.fromDateTime(startAt),
                        );
                        if (t == null) return;
                        setModal(() {
                          startAt = DateTime(
                            d.year,
                            d.month,
                            d.day,
                            t.hour,
                            t.minute,
                          );
                        });
                      },
                    ),
                    Text('最大尝试次数：$maxAttempts'),
                    Slider(
                      value: maxAttempts.toDouble(),
                      min: 1,
                      max: 20,
                      divisions: 19,
                      label: '$maxAttempts',
                      onChanged: (v) =>
                          setModal(() => maxAttempts = v.round()),
                    ),
                    Text('尝试间隔：${(delayMs / 1000).toStringAsFixed(1)} 秒'),
                    Slider(
                      value: delayMs.toDouble(),
                      min: 1000,
                      max: 5000,
                      divisions: 8,
                      label: '${(delayMs / 1000).toStringAsFixed(1)}s',
                      onChanged: (v) => setModal(() => delayMs = v.round()),
                    ),
                    const Text(
                      '回退区域（偏好被占时，在勾选区域内找空座）',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final a in LibrarySeatAreas.all)
                          FilterChip(
                            label: Text(a.label, style: const TextStyle(fontSize: 11)),
                            selected: fallback.contains(a.code),
                            onSelected: (sel) {
                              setModal(() {
                                if (sel) {
                                  fallback.add(a.code);
                                } else {
                                  fallback.remove(a.code);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        final seat = seatCtrl.text.trim();
                        if (seat.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('请填写偏好座位号')),
                          );
                          return;
                        }
                        final config = LibrarySeatScheduleConfig(
                          preferredSeatId: seat.toUpperCase(),
                          preferredAreaCode: areaCode,
                          startAt: startAt,
                          fallbackAreaCodes: fallback.isEmpty
                              ? [areaCode]
                              : List<String>.from(fallback),
                          maxAttempts: maxAttempts,
                          delayMs: delayMs,
                        );
                        await ref
                            .read(librarySeatScheduleRunnerProvider.notifier)
                            .arm(config);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('保存并设置提醒'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(librarySeatScheduleRunnerProvider.notifier)
                            .clear();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('清除定时'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final area = ref.watch(librarySeatAreaProvider);
    final snap = ref.watch(librarySeatsSnapshotProvider);
    final scheduleMsg = ref.watch(librarySeatScheduleRunnerProvider);
    final schedule = ref.watch(librarySeatScheduleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.librarySeatsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        actions: [
          ManualRefreshButton(
            onRefresh: () =>
                ref.read(librarySeatsSnapshotProvider.notifier).refresh(),
          ),
          IconButton(
            tooltip: '网页入口',
            icon: const Icon(Icons.open_in_browser_rounded),
            onPressed: () {
              context.push(
                '/browser',
                extra: {
                  'url': 'http://rg.lib.xjtu.edu.cn:8086/seat/',
                  'title': AppStrings.librarySeatsTitle,
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_booking) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: AppTokens.pagePadding,
              children: [
                AppSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        AppStrings.librarySeatsFairUse,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      Text(
                        AppStrings.librarySeatsCampusNetHint,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.inkSoft,
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                snap.when(
                  data: (data) => DataSourceBanner(
                    live: data.live,
                    message: data.banner,
                    fetchedAt: data.fetchedAt,
                  ),
                  loading: () => const MockDataBanner(),
                  error: (e, _) => DataSourceBanner(
                    live: false,
                    message: e.toString().contains('unreachable')
                        ? AppStrings.librarySeatsCampusNetHint
                        : AppStrings.librarySeatsAuthHint,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: area,
                  decoration: const InputDecoration(
                    labelText: '区域',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final a in LibrarySeatAreas.all)
                      DropdownMenuItem(value: a.code, child: Text(a.label)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    ref.read(librarySeatAreaProvider.notifier).setArea(v);
                  },
                ),
                const SizedBox(height: AppTokens.spaceMd),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openScheduleSheet,
                        icon: const Icon(Icons.alarm_add_outlined),
                        label: const Text('定时预约'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final r = await ref
                              .read(librarySeatScheduleRunnerProvider.notifier)
                              .runConfigured();
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text(r.message)),
                          );
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('立即执行配置'),
                      ),
                    ),
                  ],
                ),
                if (scheduleMsg != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    scheduleMsg,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
                schedule.when(
                  data: (cfg) {
                    if (cfg == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '已存配置：${cfg.preferredSeatId} @ '
                        '${DateFormat('M/d HH:mm').format(cfg.startAt)} · '
                        '最多 ${cfg.maxAttempts} 次',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                AsyncBody(
                  value: snap,
                  onRetry: () => ref
                      .read(librarySeatsSnapshotProvider.notifier)
                      .refresh(),
                  builder: (data) {
                    if (!data.reachable) {
                      return const AppSurfaceCard(
                        child: Text(AppStrings.librarySeatsCampusNetHint),
                      );
                    }
                    if (data.needsAuth) {
                      return AppSurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(AppStrings.librarySeatsAuthHint),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () {
                                context.push(
                                  '/browser',
                                  extra: {
                                    'url': 'http://www.lib.xjtu.edu.cn/',
                                    'title': '图书馆登录',
                                  },
                                );
                              },
                              child: const Text('打开图书馆登录页'),
                            ),
                          ],
                        ),
                      );
                    }
                    if (data.seats.isEmpty) {
                      return const AppSurfaceCard(
                        child: Text('该区域暂无座位数据（或接口形状有变，请校园网下重试）'),
                      );
                    }
                    final free = data.freeSeats;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '空闲 ${free.length} / 共 ${data.seats.length}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final seat in data.seats)
                              FilterChip(
                                label: Text(seat.id),
                                selected: seat.isFree,
                                showCheckmark: false,
                                backgroundColor: seat.isFree
                                    ? AppColors.chip
                                    : Colors.grey.shade200,
                                selectedColor: AppColors.chip,
                                labelStyle: TextStyle(
                                  color: seat.isFree
                                      ? AppColors.navy
                                      : AppColors.inkSoft,
                                  fontWeight: seat.isFree
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                                onSelected: seat.isFree
                                    ? (_) => _confirmBook(seat)
                                    : null,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '点选绿色/可选座位将弹出确认框后预约',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
