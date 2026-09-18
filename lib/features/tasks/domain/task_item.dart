import '../../homework/domain/homework.dart';

/// Personal tasks are device-local and never represent an LMS submission.
class PersonalTask {
  const PersonalTask({
    required this.id,
    required this.title,
    this.notes = '',
    this.dueAt,
    this.completed = false,
  });
  final String id, title, notes;
  final DateTime? dueAt;
  final bool completed;
  PersonalTask toggle() => PersonalTask(
    id: id,
    title: title,
    notes: notes,
    dueAt: dueAt,
    completed: !completed,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'notes': notes,
    'dueAt': dueAt?.toUtc().toIso8601String(),
    'completed': completed,
  };
  factory PersonalTask.fromJson(Map<String, dynamic> json) => PersonalTask(
    id: json['id'] as String,
    title: json['title'] as String,
    notes: json['notes'] as String? ?? '',
    dueAt: homeworkDate(json['dueAt']),
    completed: json['completed'] == true,
  );
}

enum TaskKind { course, homework, exam, personal }

class AgendaItem {
  const AgendaItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.kind,
    required this.source,
    this.at,
    this.end,
    this.completed = false,
    this.route,
    this.extra,
    this.personal,
  });
  final String id, title, detail, source;
  final TaskKind kind;
  final DateTime? at, end;
  final bool completed;
  final String? route;
  final Object? extra;
  final PersonalTask? personal;
  bool overdue(DateTime now) =>
      !completed &&
      (kind == TaskKind.personal || kind == TaskKind.homework) &&
      at != null &&
      at!.isBefore(now);
  String get kindLabel => switch (kind) {
    TaskKind.course => '课程',
    TaskKind.homework => '作业',
    TaskKind.exam => '考试',
    TaskKind.personal => '个人待办',
  };
}
