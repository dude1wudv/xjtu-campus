import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/storage/credential_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../schedule/domain/course.dart';
import '../../schedule/presentation/schedule_providers.dart';
import '../domain/alarm_suggestion.dart';

class AlarmPrefs {
  const AlarmPrefs({
    required this.enableWake,
    required this.enableClass,
    required this.wakeMinutes,
    required this.reminderMinutes,
  });

  final bool enableWake;
  final bool enableClass;
  final int wakeMinutes;
  final Set<int> reminderMinutes;

  static AlarmPrefs defaults() => AlarmPrefs(
    enableWake: true,
    enableClass: true,
    wakeMinutes: AppConstants.defaultWakeOffset.inMinutes,
    reminderMinutes: {
      for (final d in AppConstants.defaultClassReminders) d.inMinutes,
    },
  );

  AlarmPrefs copyWith({
    bool? enableWake,
    bool? enableClass,
    int? wakeMinutes,
    Set<int>? reminderMinutes,
  }) {
    return AlarmPrefs(
      enableWake: enableWake ?? this.enableWake,
      enableClass: enableClass ?? this.enableClass,
      wakeMinutes: wakeMinutes ?? this.wakeMinutes,
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    );
  }

  List<Duration> get reminderOffsets => [
    for (final m in AppConstants.availableReminderMinutes)
      if (reminderMinutes.contains(m)) Duration(minutes: m),
  ];
}

class AlarmPrefsController extends Notifier<AlarmPrefs> {
  CredentialStore get _store => ref.read(credentialStoreProvider);

  @override
  AlarmPrefs build() {
    Future.microtask(_restore);
    return AlarmPrefs.defaults();
  }

  Future<void> _restore() async {
    try {
      final enableWake =
          await _store.read(AppConstants.alarmEnableWakeKey) ?? '1';
      final enableClass =
          await _store.read(AppConstants.alarmEnableClassKey) ?? '1';
      final wakeRaw = await _store.read(AppConstants.alarmWakeMinutesKey);
      final remRaw = await _store.read(AppConstants.alarmReminderMinutesKey);
      final wake =
          int.tryParse(wakeRaw ?? '') ??
          AppConstants.defaultWakeOffset.inMinutes;
      final reminders = <int>{};
      if (remRaw != null && remRaw.trim().isNotEmpty) {
        for (final part in remRaw.split(',')) {
          final m = int.tryParse(part.trim());
          if (m != null) reminders.add(m);
        }
      } else {
        reminders.addAll({
          for (final d in AppConstants.defaultClassReminders) d.inMinutes,
        });
      }
      if (!ref.mounted) return;
      state = AlarmPrefs(
        enableWake: enableWake != '0',
        enableClass: enableClass != '0',
        wakeMinutes: wake.clamp(45, 150),
        reminderMinutes: reminders.isEmpty
            ? {for (final d in AppConstants.defaultClassReminders) d.inMinutes}
            : reminders,
      );
    } on Object {
      // Keep defaults.
    }
  }

  Future<void> _persist(AlarmPrefs prefs) async {
    try {
      await _store.write(
        key: AppConstants.alarmEnableWakeKey,
        value: prefs.enableWake ? '1' : '0',
      );
      await _store.write(
        key: AppConstants.alarmEnableClassKey,
        value: prefs.enableClass ? '1' : '0',
      );
      await _store.write(
        key: AppConstants.alarmWakeMinutesKey,
        value: '${prefs.wakeMinutes}',
      );
      final sorted = prefs.reminderMinutes.toList()
        ..sort((a, b) => b.compareTo(a));
      await _store.write(
        key: AppConstants.alarmReminderMinutesKey,
        value: sorted.join(','),
      );
    } on Object {
      // Persistence is best-effort.
    }
  }

  void setEnableWake(bool value) {
    state = state.copyWith(enableWake: value);
    _persist(state);
  }

  void setEnableClass(bool value) {
    state = state.copyWith(enableClass: value);
    _persist(state);
  }

  void setWakeMinutes(int minutes) {
    state = state.copyWith(wakeMinutes: minutes.clamp(45, 150));
    _persist(state);
  }

  void toggleReminderMinute(int minutes) {
    final next = {...state.reminderMinutes};
    if (next.contains(minutes)) {
      next.remove(minutes);
    } else {
      next.add(minutes);
    }
    state = state.copyWith(reminderMinutes: next);
    _persist(state);
  }
}

final alarmPrefsProvider = NotifierProvider<AlarmPrefsController, AlarmPrefs>(
  AlarmPrefsController.new,
);

/// Back-compat for older wake-only slider references.
final wakeOffsetProvider = Provider<int>(
  (ref) => ref.watch(alarmPrefsProvider).wakeMinutes,
);

final alarmPreviewProvider = Provider<AsyncValue<List<AlarmSuggestion>>>((ref) {
  final snapshot = ref.watch(scheduleSnapshotProvider);
  final prefs = ref.watch(alarmPrefsProvider);
  final planner = ref.watch(alarmPlannerProvider);
  return snapshot.whenData(
    (data) => planner.plan(
      courses: data.courses,
      now: DateTime.now(),
      wakeOffset: Duration(minutes: prefs.wakeMinutes),
      reminderOffsets: prefs.reminderOffsets,
      weekNumber: data.week,
      enableWake: prefs.enableWake,
      enableClass: prefs.enableClass,
    ),
  );
});

class AlarmsPage extends ConsumerStatefulWidget {
  const AlarmsPage({super.key});

  @override
  ConsumerState<AlarmsPage> createState() => _AlarmsPageState();
}

class _AlarmsPageState extends ConsumerState<AlarmsPage> {
  final Set<String> _selected = {};
  var _selectionBootstrapped = false;

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(alarmPrefsProvider);
    final preview = ref.watch(alarmPreviewProvider);
    final snapshot = ref.watch(scheduleSnapshotProvider);
    final now = DateTime.now();
    final season = ClassPeriod.seasonLabel(now);

    ref.listen<AsyncValue<List<AlarmSuggestion>>>(alarmPreviewProvider, (
      previous,
      next,
    ) {
      next.whenData((items) {
        final ids = items.map((e) => e.id).toSet();
        final prevIds = previous?.asData?.value.map((e) => e.id).toSet();
        final shouldReset =
            !_selectionBootstrapped ||
            prevIds == null ||
            prevIds.length != ids.length ||
            !prevIds.containsAll(ids) ||
            !ids.containsAll(prevIds);
        if (!shouldReset) return;
        _selectionBootstrapped = true;
        setState(() {
          _selected
            ..clear()
            ..addAll(ids);
        });
      });
    });

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.alarmsTitle)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                snapshot.when(
                  data: (data) =>
                      DataSourceBanner(live: data.live, message: data.banner),
                  loading: () => const MockDataBanner(),
                  error: (_, _) => const MockDataBanner(),
                ),
                const SizedBox(height: 8),
                Card(
                  color: AppColors.navy.withValues(alpha: 0.08),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.wb_twilight,
                      color: AppColors.navy,
                    ),
                    title: Text(
                      season,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                    ),
                    subtitle: const Text('根据学校通知自动切换下午作息'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.alarmStubHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(AppStrings.enableWakeAlarm),
                  value: prefs.enableWake,
                  onChanged: (v) =>
                      ref.read(alarmPrefsProvider.notifier).setEnableWake(v),
                ),
                if (prefs.enableWake) ...[
                  Text(
                    '${AppStrings.wakeOffsetLabel}：${prefs.wakeMinutes} ${AppStrings.minutesUnit}',
                  ),
                  Slider(
                    min: 45,
                    max: 150,
                    divisions: 7,
                    value: prefs.wakeMinutes.toDouble(),
                    label: '${prefs.wakeMinutes}',
                    onChanged: (value) => ref
                        .read(alarmPrefsProvider.notifier)
                        .setWakeMinutes(value.round()),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(AppStrings.enableClassReminder),
                  value: prefs.enableClass,
                  onChanged: (v) =>
                      ref.read(alarmPrefsProvider.notifier).setEnableClass(v),
                ),
                if (prefs.enableClass) ...[
                  const Text(AppStrings.reminderOffsetsLabel),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final minutes
                          in AppConstants.availableReminderMinutes)
                        FilterChip(
                          selected: prefs.reminderMinutes.contains(minutes),
                          label: Text(
                            '$minutes ${AppStrings.minutesUnit}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: prefs.reminderMinutes.contains(minutes)
                                  ? Colors.white
                                  : AppColors.navy,
                            ),
                          ),
                          selectedColor: AppColors.navy,
                          checkmarkColor: Colors.white,
                          backgroundColor: Colors.white,
                          side: const BorderSide(
                            color: AppColors.navy,
                            width: 1.5,
                          ),
                          onSelected: (_) => ref
                              .read(alarmPrefsProvider.notifier)
                              .toggleReminderMinute(minutes),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      AppStrings.suggestedAlarms,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: preview.maybeWhen(
                        data: (items) => () {
                          setState(() {
                            _selected
                              ..clear()
                              ..addAll(items.map((e) => e.id));
                          });
                        },
                        orElse: () => null,
                      ),
                      child: const Text(AppStrings.selectAllAlarms),
                    ),
                    TextButton(
                      onPressed: () => setState(_selected.clear),
                      child: const Text(AppStrings.deselectAllAlarms),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AsyncBody(
                  value: preview,
                  onRetry: () => ref.invalidate(scheduleSnapshotProvider),
                  builder: (items) {
                    if (items.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: EmptyHint(
                          icon: Icons.alarm_off,
                          text: AppStrings.noAlarms,
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          _AlarmTile(
                            suggestion: items[i],
                            checked: _selected.contains(items[i].id),
                            onChanged: (checked) {
                              setState(() {
                                if (checked) {
                                  _selected.add(items[i].id);
                                } else {
                                  _selected.remove(items[i].id);
                                }
                              });
                            },
                          ),
                        ],
                        const SizedBox(height: 88),
                      ],
                    );
                  },
                ),
              ],
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
                  data: (items) {
                    final chosen = items
                        .where((e) => _selected.contains(e.id))
                        .toList();
                    if (chosen.isEmpty) {
                      return () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(AppStrings.noSelectedAlarms),
                          ),
                        );
                      };
                    }
                    return () => _create(context, ref, chosen);
                  },
                  orElse: () => null,
                ),
                icon: const Icon(Icons.alarm_add),
                label: const Text(AppStrings.createSelectedAlarms),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    await ref.read(alarmSchedulerProvider).cancelAlarms();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已取消本机已预约的上课提醒')));
  }

  Future<void> _test(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(alarmSchedulerProvider)
        .showTestNotification();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }
}

class _AlarmTile extends StatelessWidget {
  const _AlarmTile({
    required this.suggestion,
    required this.checked,
    required this.onChanged,
  });

  final AlarmSuggestion suggestion;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat(
      'M月d日 EEEE HH:mm',
      'zh_CN',
    ).format(suggestion.fireAt);
    final isWake = suggestion.kind == AlarmKind.wakeUp;
    return Card(
      child: CheckboxListTile(
        value: checked,
        onChanged: (v) => onChanged(v ?? false),
        secondary: Icon(
          isWake
              ? Icons.wb_sunny_outlined
              : Icons.notifications_active_outlined,
          color: AppColors.navy,
        ),
        title: Text(suggestion.title),
        subtitle: Text('$time\n${suggestion.body}'),
        isThreeLine: true,
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }
}
