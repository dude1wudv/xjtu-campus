/// Dates without an offset from LMS are campus (UTC+8) wall-clock times.
DateTime? homeworkDate(Object? value) {
  if (value == null || '$value'.isEmpty) return null;
  var text = '$value'.trim().replaceFirst(' ', 'T');
  if (!RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(text)) {
    if (!text.contains('T')) text += 'T00:00:00';
    text += '+08:00';
  }
  return DateTime.tryParse(text)?.toUtc();
}

DateTime campusTime(DateTime date) => date.toUtc().add(const Duration(hours: 8));

enum HomeworkStatus {
  unknown('提交待确认'), pending('未提交'), submitted('已提交');
  const HomeworkStatus(this.label);
  final String label;
}

class Homework {
  const Homework({required this.id, required this.courseId,
    required this.courseName, required this.title, this.dueAt,
    this.status = HomeworkStatus.unknown, this.group = false});
  final int id, courseId;
  final String courseName, title;
  final DateTime? dueAt;
  final HomeworkStatus status;
  final bool group;

  bool get overdue => dueAt != null && dueAt!.isBefore(DateTime.now());
  Homework withStatus(HomeworkStatus value) => Homework(id: id, courseId: courseId,
    courseName: courseName, title: title, dueAt: dueAt, status: value, group: group);

  factory Homework.fromJson(Map<String, dynamic> json) => Homework(
    id: json['id'] as int, courseId: json['courseId'] as int,
    courseName: json['courseName'] as String, title: json['title'] as String,
    dueAt: homeworkDate(json['dueAt']), group: json['group'] == true,
    status: HomeworkStatus.values.firstWhere((s) => s.name == json['status'],
        orElse: () => HomeworkStatus.unknown),
  );
  Map<String, dynamic> toJson() => {'id': id, 'courseId': courseId,
    'courseName': courseName, 'title': title, 'dueAt': dueAt?.toIso8601String(),
    'group': group, 'status': status.name};
}

class HomeworkSnapshot {
  const HomeworkSnapshot(this.items, this.updatedAt, {this.fromCache = false,
    this.failedCourses = 0, this.terms = const [], this.termLabel = '本学期'});
  final List<Homework> items;
  final DateTime updatedAt;
  final bool fromCache;
  final int failedCourses;
  final List<HomeworkTerm> terms;
  final String termLabel;
  factory HomeworkSnapshot.fromJson(Map<String, dynamic> json) => HomeworkSnapshot(
    (json['items'] as List).map((v) => Homework.fromJson(Map<String, dynamic>.from(v as Map))).toList(),
    DateTime.parse(json['updatedAt'] as String), fromCache: true,
    failedCourses: (json['failedCourses'] as int?) ?? 0,
    terms: (json['terms'] as List? ?? []).map((v) => HomeworkTerm.fromJson(v as Map)).toList(),
    termLabel: json['termLabel'] as String? ?? '本学期',
  );
  Map<String, dynamic> toJson() => {'items': items.map((i) => i.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(), 'failedCourses': failedCourses, 'terms': terms.map((t) => t.toJson()).toList(), 'termLabel': termLabel};
}

class HomeworkDetail {
  const HomeworkDetail(this.description, this.status, this.attachments);
  final String description;
  final HomeworkStatus status;
  final List<String> attachments;
}

class HomeworkAuthRequired implements Exception {
  const HomeworkAuthRequired();
  @override
  String toString() => '请登录思源学堂后重新同步';
}

/// Stable LMS year/semester identifiers; names are only used for display.
class HomeworkTerm {
  const HomeworkTerm(this.id, this.label, this.code);
  final String id, label;
  final String? code;
  factory HomeworkTerm.fromCourse(Map course) {
    final year = course['academic_year'];
    final semester = course['semester'];
    if (year is! Map || semester is! Map) {
      return const HomeworkTerm('unknown', '学期未标注', null);
    }
    final yearName = '${year['name'] ?? year['code'] ?? ''}';
    final name = '${semester['name'] ?? semester['real_name'] ?? ''}';
    final years = RegExp(r'(20\d{2})\D+(20\d{2})').firstMatch(yearName);
    final number = name.contains('秋') || name.contains('第一') ? '1'
        : name.contains('春') || name.contains('第二') ? '2'
        : name.contains('夏') || name.contains('第三') ? '3' : null;
    return HomeworkTerm('${year['id'] ?? yearName}:${semester['id'] ?? name}',
      '$yearName $name'.trim(), years != null && number != null
        ? '${years[1]}-${years[2]}-$number' : null);
  }
  factory HomeworkTerm.fromJson(Map json) => HomeworkTerm(
    json['id'] as String, json['label'] as String, json['code'] as String?);
  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'code': code};
}
