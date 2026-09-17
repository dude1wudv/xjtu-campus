import '../../schedule/domain/course.dart';

enum AttendanceStatus {
  normal('正常出勤'), late('迟到'), absent('缺勤'),
  earlyLeave('早退'), leave('请假'), unknown('待确认'),
  pending('待考勤'), notRequired('不考勤');
  const AttendanceStatus(this.label);
  final String label;

  static AttendanceStatus fromCode(Object? value) => switch (value.toString()) {
    '1' => normal, '2' => late, '3' => absent, '4' => earlyLeave,
    '5' => leave, _ => unknown,
  };

  /// Status values used by the undergraduate `/sa` application. Pending and
  /// not-required are kept distinct from normal; unrecognized values remain
  /// unknown and never prove normal attendance.
  static AttendanceStatus fromUndergraduateValue(Object? value) {
    final raw = value is String ? value.trim() : '${value ?? ''}'.trim();
    return switch (raw.toUpperCase()) {
      'NORMAL' => normal,
      'LATE' => late,
      'ABSENT' => absent,
      'LEAVE' => leave,
      'PENDING' => pending,
      'NOT_REQUIRED' => notRequired,
      _ => unknown,
    };
  }
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
    if (startPeriod < 1 || endPeriod < startPeriod) return false;
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

  /// Parse a row returned by the undergraduate `/sa` attendance service.
  ///
  /// This is intentionally separate from [fromResponse]: the graduate API
  /// uses nested `*Bean` objects, while the undergraduate rows are flat.
  factory AttendanceRecord.fromUndergraduateResponse(Map<String, dynamic> row) {
    final id = _text(row['resultId']).isNotEmpty
        ? _text(row['resultId'])
        : _text(row['id']);
    if (id.isEmpty) throw const FormatException('本科生考勤记录缺少记录标识');

    final rawDate = _text(row['attendanceDate']);
    final date = _parseDate(rawDate);
    if (rawDate.isEmpty || date == null) {
      throw const FormatException('本科生考勤记录日期无法解析');
    }

    var start = _integer(row['startSection']);
    var end = _integer(row['endSection']);
    if (start == null || end == null) {
      final range = _periodRange(row['periodNo']);
      if (range != null && (start == null || start == range.$1) &&
          (end == null || end == range.$2)) {
        start = range.$1;
        end = range.$2;
      }
    }
    if (start == null || end == null || start < 1 || end < start) {
      // Keep the official row visible, but make it impossible to associate
      // an unknown lesson with a timetable course.
      start = 0;
      end = 0;
    }

    final courseName = _text(row['courseName']).isNotEmpty
        ? _text(row['courseName'])
        : _text(row['courseCode']);
    return AttendanceRecord(
      id: id,
      courseName: courseName,
      date: date,
      startPeriod: start,
      endPeriod: end,
      location: _text(row['classroomName']),
      teacher: _textList(row['teacherName']),
      status: AttendanceStatus.fromUndergraduateValue(row['attendanceStatus']),
    );
  }

  static String _text(Object? value) => value is String
      ? value.trim()
      : value == null ? '' : '$value'.trim();

  static String _textList(Object? value) {
    if (value is List) return value.map(_text).where((v) => v.isNotEmpty).join('、');
    return _text(value);
  }

  static int? _integer(Object? value) {
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    return int.tryParse(_text(value));
  }

  static (int, int)? _periodRange(Object? value) {
    final raw = _text(value);
    if (raw.isEmpty) return null;
    final match = RegExp(r'^第?\s*(\d{1,2})(?:\s*[-~—至到]\s*(\d{1,2}))?\s*节?$')
        .firstMatch(raw);
    if (match != null) {
      final start = int.parse(match.group(1)!);
      final end = int.tryParse(match.group(2) ?? '') ?? start;
      return (start, end);
    }
    return null;
  }

  static DateTime? _parseDate(String raw) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|[T ])').firstMatch(raw);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime.tryParse(raw);
    if (date == null || date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return DateTime(year, month, day);
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
