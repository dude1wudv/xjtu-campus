import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../schedule/presentation/schedule_providers.dart';
import '../domain/alarm_suggestion.dart';

class WakeOffsetController extends Notifier<int> {
  @override
  int build() => AppConstants.defaultWakeOffset.inMinutes;

  void setMinutes(int minutes) => state = minutes;
}

final wakeOffsetProvider = NotifierProvider<WakeOffsetController, int>(
  WakeOffsetController.new,
);

final alarmPreviewProvider = Provider<AsyncValue<List<AlarmSuggestion>>>((ref) {
  final snapshot = ref.watch(scheduleSnapshotProvider);
  final offsetMinutes = ref.watch(wakeOffsetProvider);
  final planner = ref.watch(alarmPlannerProvider);
  return snapshot.whenData(
    (data) => planner.plan(
      courses: data.courses,
      now: DateTime.now(),
      wakeOffset: Duration(minutes: offsetMinutes),
      weekNumber: data.week,
    ),
  );
});

class AlarmsPage extends ConsumerWidget {
  const AlarmsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offset = ref.watch(wakeOffsetProvider);
    final preview = ref.watch(alarmPreviewProvider);
    final snapshot = ref.watch(scheduleSnapshotProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.alarmsTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                snapshot.when(
                  data: (data) =>
                      DataSourceBanner(live: data.live, message: data.banner),
                  loading: () => const MockDataBanner(),
                  error: (_, _) => const MockDataBanner(),
                ),
                const SizedBox(height: 8),
                const Text(AppStrings.alarmStubHint),
                const SizedBox(height: 12),
                Text('${AppStrings.wakeOffsetLabel}：$offset ${AppStrings.minutesUnit}'),
                Slider(
                  min: 45,
                  max: 150,
                  divisions: 7,
                  value: offset.toDouble(),
                  label: '$offset',
                  onChanged: (value) => ref
                      .read(wakeOffsetProvider.notifier)
                      .setMinutes(value.round()),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: preview,
              onRetry: () => ref.invalidate(scheduleSnapshotProvider),
              builder: (items) {
                if (items.isEmpty) {
                  return const EmptyHint(
                    icon: Icons.alarm_off,
                    text: AppStrings.noAlarms,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _AlarmTile(suggestion: items[index]),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: preview.maybeWhen(
                  data: (items) => items.isEmpty
                      ? null
                      : () => _create(context, ref, items),
                  orElse: () => null,
                ),
                icon: const Icon(Icons.alarm_add),
                label: const Text(AppStrings.createAlarms),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _cancel(context, ref),
                      child: const Text(AppStrings.cancelAlarms),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _test(context, ref),
                      child: const Text(AppStrings.testNotification),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    List<AlarmSuggestion> items,
  ) async {
    final result = await ref.read(alarmSchedulerProvider).createAlarms(items);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    await ref.read(alarmSchedulerProvider).cancelAlarms();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已取消本机已预约的上课提醒')),
    );
  }

  Future<void> _test(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(alarmSchedulerProvider)
        .showTestNotification();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }
}

class _AlarmTile extends StatelessWidget {
  const _AlarmTile({required this.suggestion});

  final AlarmSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('M月d日 EEEE HH:mm', 'zh_CN').format(suggestion.fireAt);
    final isWake = suggestion.kind == AlarmKind.wakeUp;
    return Card(
      child: ListTile(
        leading: Icon(
          isWake ? Icons.wb_sunny_outlined : Icons.notifications_active_outlined,
          color: AppColors.navy,
        ),
        title: Text(suggestion.title),
        subtitle: Text('$time\n${suggestion.body}'),
        isThreeLine: true,
        trailing: Text(
          isWake ? AppStrings.wakeUpAlarm : AppStrings.classReminder,
          style: const TextStyle(fontSize: 12, color: AppColors.navy),
        ),
      ),
    );
  }
}
