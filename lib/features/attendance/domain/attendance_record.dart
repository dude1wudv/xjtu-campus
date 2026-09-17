import '../../schedule/domain/course.dart';

enum AttendanceStatus {
  normal('正常出勤'), late('迟到'), absent('缺勤'),
  earlyLeave('早退'), leave('请假'), unknown('待确认');
  const AttendanceStatus(this.label);
  final String label;

  static AttendanceStatus fromCode(Object? value) => switch (value.toString()) {
    '1' => normal, '2' => late, '3' => absent, '4' => earlyLeave,
    '5' => leave, _ => unknown,
  };
}

class AttendanceRecord {
  const AttendanceRecord({required this.id, required this.courseName,
    required this.date, required this.startPeriod, required this.endPeriod,
    required this.location, required this.teacher, required this.status});

  final String id, courseName, location, teacher;
  final DateTime date;
  final int startPeriod, endPeriod;
  final AttendanceStatus status;

  bool matches(Course course, DateTime day) {
    if (date.year != day.year || date.month != day.month || date.day != day.day ||
        startPeriod != course.startPeriod || endPeriod != course.endPeriod) return false;
    String normalize(String value) => value.replaceAll(RegExp(r'[\s\-—·（）()]'), '').toLowerCase();
    // Never infer absence from missing data or a name-only match. Some API
    // versions omit the subject name; only use an exact room+teacher fallback.
    if (courseName.isNotEmpty) return normalize(courseName) == normalize(course.name);
    return teacher.isNotEmpty && normalize(teacher) == normalize(course.teacher) &&
        location.isNotEmpty && normalize(location) == normalize('${course.building}-${course.room}');
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'courseName': courseName, 'date': date.toIso8601String(),
    'startPeriod': startPeriod, 'endPeriod': endPeriod, 'location': location,
    'teacher': teacher, 'status': status.index,
  };

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) => AttendanceRecord(
    id: json['id'] as String, courseName: json['courseName'] as String,
    date: DateTime.parse(json['date'] as String),
    startPeriod: json['startPeriod'] as int, endPeriod: json['endPeriod'] as int,
    location: json['location'] as String, teacher: json['teacher'] as String,
    status: AttendanceStatus.values[json['status'] as int],
  );

  factory AttendanceRecord.fromResponse(Map<String, dynamic> row) {
    Map bean(String name) => row[name] is Map ? row[name] as Map : const {};
    final account = bean('accountBean');
    final water = bean('classWaterBean');
    final subject = bean('subjectBean');
    final date = DateTime.tryParse('${account['checkdate']}');
    final start = int.tryParse('${account['startJc']}');
    final end = int.tryParse('${account['endJc']}');
    if (date == null || start == null || end == null || start < 1 || end < start) {
      throw const FormatException('考勤记录格式变化，请在官方系统查看');
    }
    final teacher = row['teachNameList'];
    return AttendanceRecord(
      id: '${water['bh'] ?? '${date.toIso8601String()}-$start-$end'}',
      courseName: '${subject['sName'] ?? row['subjectname'] ?? row['subjectSName'] ?? ''}',
      date: date, startPeriod: start, endPeriod: end,
      location: [bean('buildBean')['name'], bean('roomBean')['roomnum']]
          .where((part) => part != null && '$part'.isNotEmpty).join('-'),
      teacher: teacher is List ? teacher.join('、') : '${teacher ?? ''}',
      status: AttendanceStatus.fromCode(water['status']),
    );
  }
}

class AttendanceSnapshot {
  const AttendanceSnapshot({required this.records, required this.term,
    required this.updatedAt, this.fromCache = false, this.message});
  final List<AttendanceRecord> records;
  final String term;
  final DateTime updatedAt;
  final bool fromCache;
  final String? message;

  AttendanceRecord? forCourse(Course course, DateTime day) {
    final matches = records.where((record) => record.matches(course, day)).toList();
    return matches.length == 1 ? matches.single : null;
  }

  Map<String, dynamic> toJson() => {'term': term,
    'updatedAt': updatedAt.toIso8601String(),
    'records': records.map((record) => record.toJson()).toList()};
  factory AttendanceSnapshot.fromJson(Map<String, dynamic> json) => AttendanceSnapshot(
    term: json['term'] as String, updatedAt: DateTime.parse(json['updatedAt'] as String),
    records: (json['records'] as List).map((row) =>
      AttendanceRecord.fromJson(Map<String, dynamic>.from(row as Map))).toList(),
    fromCache: true, message: '显示上次同步的考勤，最新状态以学校系统为准',
  );
}
