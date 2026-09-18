import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/data/data_status.dart';
import '../../../core/data/data_status_provider.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../exams/presentation/exams_providers.dart';
import '../../homework/domain/homework.dart';
import '../../homework/presentation/homework_providers.dart';
import '../../schedule/domain/timetable_logic.dart';
import '../../schedule/presentation/schedule_providers.dart';
import '../domain/task_item.dart';

final taskScopeProvider = Provider<String>((ref) {
  final auth = ref.watch(authControllerProvider);
  return !auth.initialized
      ? 'restoring'
      : kIsWeb
      ? 'web-local'
      : auth.user.isGuest
      ? 'guest'
      : '${auth.user.isDemo ? 'demo' : 'account'}:${auth.user.studentId}';
});

class PersonalTasks extends AsyncNotifier<List<PersonalTask>> {
  Future<void> _writes = Future.value();
  int _generation = 0;
  @override
  Future<List<PersonalTask>> build() async {
    final scope = ref.watch(taskScopeProvider);
    _generation++;
    final raw = (await SharedPreferences.getInstance()).getString(
      'personal_tasks.v1.$scope',
    );
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => PersonalTask.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _change(
    List<PersonalTask> Function(List<PersonalTask>) transform,
  ) {
    final scope = ref.read(taskScopeProvider);
    final generation = _generation;
    final operation = _writes.then((_) async {
      if (!ref.mounted || generation != _generation || scope == 'restoring') {
        throw StateError('账号已切换，请重新打开待办');
      }
      final current = await future;
      if (!ref.mounted || generation != _generation) throw StateError('账号已切换');
      final next = transform(List.of(current));
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        'personal_tasks.v1.$scope',
        jsonEncode(next.map((t) => t.toJson()).toList()),
      )) {
        throw StateError('保存失败');
      }
      if (ref.mounted && generation == _generation) state = AsyncData(next);
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> save(PersonalTask task) => _change((items) {
    final index = items.indexWhere((t) => t.id == task.id);
    if (index < 0) {
      items.add(task);
    } else {
      items[index] = task;
    }
    return items;
  });
  Future<void> toggle(String id) => _change(
    (items) => items.map((t) => t.id == id ? t.toggle() : t).toList(),
  );
  Future<void> remove(String id) =>
      _change((items) => items.where((t) => t.id != id).toList());
}

final personalTasksProvider =
    AsyncNotifierProvider<PersonalTasks, List<PersonalTask>>(
      PersonalTasks.new,
      retry: (count, error) => null,
    );
String newTaskId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

final taskClockProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now());
});
DateTime campusInstant(DateTime wall) => DateTime.utc(
  wall.year,
  wall.month,
  wall.day,
  wall.hour,
  wall.minute,
).subtract(const Duration(hours: 8));
DateTime campusDay(DateTime now) {
  final wall = campusTime(now);
  return DateTime(wall.year, wall.month, wall.day);
}

final agendaProvider = Provider<List<AgendaItem>>((ref) {
  final now = ref.watch(taskClockProvider).asData?.value ?? DateTime.now();
  final day = campusDay(now);
  final auth = ref.watch(authControllerProvider);
  final statuses = ref.watch(dataStatusesProvider);
  final result = <String, AgendaItem>{};
  void add(AgendaItem item) => result[item.id] = item;
  final schedule = ref.watch(scheduleSnapshotProvider).asData?.value;
  if (auth.initialized &&
      schedule != null &&
      (schedule.failure == null || schedule.fromCache)) {
    for (var offset = 0; offset < 7; offset++) {
      final date = DateTime(day.year, day.month, day.day + offset);
      for (final c in coursesForDay(schedule, date, day)) {
        final start = campusInstant(c.startAt(date));
        final end = campusInstant(c.endAt(date));
        add(
          AgendaItem(
            id: 'course:${c.id}:${date.toIso8601String()}',
            title: c.name,
            detail: '${c.periodLabelFor(date)} · ${c.location}',
            kind: TaskKind.course,
            source: statuses['schedule']?.sourceLabel ?? '课表',
            at: start,
            end: end,
            route: courseRoute(c, date),
          ),
        );
      }
    }
  }
  if (auth.initialized && !kIsWeb && auth.isLoggedIn && !auth.user.isDemo) {
    final homework = ref.watch(homeworkProvider).asData?.value;
    for (final h in homework?.items ?? <Homework>[]) {
      add(
        AgendaItem(
          id: 'homework:${h.courseId}:${h.id}',
          title: h.title,
          detail: '${h.courseName} · ${h.status.label}',
          kind: TaskKind.homework,
          source: statuses['homework']?.sourceLabel ?? '作业',
          at: h.dueAt,
          completed: h.status == HomeworkStatus.submitted,
          route: '/homework/${h.id}',
          extra: h,
        ),
      );
    }
    final exams = ref.watch(examsSnapshotProvider).asData?.value;
    if (exams != null && (exams.live || exams.fromCache)) {
      for (final e in exams.exams) {
        final date = RegExp(r'(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})')
            .firstMatch(e.date);
        final time = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(e.timeLabel);
        DateTime? instant;
        if (date != null) {
          final y = int.parse(date[1]!),
              m = int.parse(date[2]!),
              d = int.parse(date[3]!);
          final h = time == null ? 0 : int.parse(time[1]!);
          final min = time == null ? 0 : int.parse(time[2]!);
          final wall = DateTime.utc(y, m, d, h, min);
          if (wall.year == y &&
              wall.month == m &&
              wall.day == d &&
              h < 24 &&
              min < 60) {
            instant = wall.subtract(const Duration(hours: 8));
          }
        }
        add(
          AgendaItem(
            id: 'exam:${e.termCode}:${e.courseCode}:${e.courseName}:${e.date}:${e.timeLabel}:${e.location}',
            title: e.courseName,
            detail: '${e.dateTimeLabel} · ${e.location}',
            kind: TaskKind.exam,
            source: statuses['exams']?.sourceLabel ?? '考试',
            at: instant,
            route: '/exams',
          ),
        );
      }
    }
  }
  for (final t
      in ref.watch(personalTasksProvider).asData?.value ?? <PersonalTask>[]) {
    add(
      AgendaItem(
        id: 'personal:${t.id}',
        title: t.title,
        detail: t.notes,
        kind: TaskKind.personal,
        source: '本机保存',
        at: t.dueAt,
        completed: t.completed,
        personal: t,
      ),
    );
  }
  final items = result.values.toList();
  items.sort((a, b) {
    if (a.completed != b.completed) return a.completed ? 1 : -1;
    if (a.overdue(now) != b.overdue(now)) return a.overdue(now) ? -1 : 1;
    if (a.at == null) return b.at == null ? a.id.compareTo(b.id) : 1;
    if (b.at == null) return -1;
    return a.at!.compareTo(b.at!);
  });
  return items;
});

enum TaskFilter { today, week, overdue, completed }

List<AgendaItem> filterTasks(
  List<AgendaItem> items,
  TaskFilter filter,
  DateTime now,
) {
  final start = campusInstant(campusDay(now));
  final end = start.add(Duration(days: filter == TaskFilter.week ? 7 : 1));
  return items.where((t) {
    if (filter == TaskFilter.completed) return t.completed;
    if (t.completed) return false;
    if (filter == TaskFilter.overdue) return t.overdue(now);
    if (t.overdue(now) || t.at == null) return true;
    return !t.at!.isBefore(start) && t.at!.isBefore(end);
  }).toList();
}

Future<void> refreshTaskSources(WidgetRef ref) async {
  final auth = ref.read(authControllerProvider);
  Future<void> safe(Future<Object?> f) async {
    try {
      await f;
    } catch (_) {}
  }

  final pending = <Future<void>>[
    safe(ref.read(scheduleSnapshotProvider.notifier).refresh()),
  ];
  if (!kIsWeb && auth.isLoggedIn && !auth.user.isDemo) {
    pending.add(safe(ref.read(examsSnapshotProvider.notifier).refresh()));
    ref.invalidate(homeworkProvider);
    pending.add(
      safe(
        ref
            .read(homeworkProvider.future)
            .then(
              (_) async => await ref.read(homeworkProvider.notifier).pending,
            ),
      ),
    );
  }
  await Future.wait(pending);
}
