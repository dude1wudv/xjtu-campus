import 'package:equatable/equatable.dart';

class ExamArrangement extends Equatable {
  const ExamArrangement({
    required this.termCode,
    required this.courseName,
    required this.date,
    required this.timeLabel,
    required this.location,
    this.campus,
    this.courseCode,
    this.seat,
  });

  final String termCode;
  final String courseName;
  final String date;
  final String timeLabel;
  final String location;
  final String? campus;
  final String? courseCode;
  final String? seat;

  String get dateTimeLabel {
    if (date.isEmpty && timeLabel.isEmpty) return '时间待定';
    if (timeLabel.isEmpty) return date;
    if (date.isEmpty) return timeLabel;
    return '$date $timeLabel';
  }

  Map<String, dynamic> toJson() => {
        'termCode': termCode,
        'courseName': courseName,
        'date': date,
        'timeLabel': timeLabel,
        'location': location,
        'campus': campus,
        'courseCode': courseCode,
        'seat': seat,
      };

  factory ExamArrangement.fromJson(Map<String, dynamic> json) {
    return ExamArrangement(
      termCode: json['termCode'] as String? ?? '',
      courseName: json['courseName'] as String? ?? '',
      date: json['date'] as String? ?? '',
      timeLabel: json['timeLabel'] as String? ?? '',
      location: json['location'] as String? ?? '',
      campus: json['campus'] as String?,
      courseCode: json['courseCode'] as String?,
      seat: json['seat'] as String?,
    );
  }

  @override
  List<Object?> get props =>
      [termCode, courseName, date, timeLabel, location, courseCode];
}

class ExamsSnapshot {
  const ExamsSnapshot({
    required this.exams,
    required this.live,
    required this.banner,
    this.termCode,
    this.fromCache = false,
    this.cachedAt,
    this.fetchedAt,
  });

  final List<ExamArrangement> exams;
  final bool live;
  final String banner;
  final String? termCode;
  final bool fromCache;
  final DateTime? cachedAt;
  final DateTime? fetchedAt;

  ExamsSnapshot copyWith({
    List<ExamArrangement>? exams,
    bool? live,
    String? banner,
    String? termCode,
    bool? fromCache,
    DateTime? cachedAt,
    DateTime? fetchedAt,
    bool clearTermCode = false,
    bool clearCachedAt = false,
    bool clearFetchedAt = false,
  }) {
    return ExamsSnapshot(
      exams: exams ?? this.exams,
      live: live ?? this.live,
      banner: banner ?? this.banner,
      termCode: clearTermCode ? null : (termCode ?? this.termCode),
      fromCache: fromCache ?? this.fromCache,
      cachedAt: clearCachedAt ? null : (cachedAt ?? this.cachedAt),
      fetchedAt: clearFetchedAt ? null : (fetchedAt ?? this.fetchedAt),
    );
  }

  ExamsSnapshot asCached(DateTime savedAt, {required String banner}) =>
      copyWith(
        fromCache: true,
        cachedAt: savedAt,
        banner: banner,
        clearFetchedAt: true,
      );

  ExamsSnapshot asFresh({String? banner}) => copyWith(
        fromCache: false,
        fetchedAt: DateTime.now(),
        banner: banner ?? this.banner,
        clearCachedAt: true,
      );

  Map<String, dynamic> toJson() => {
        'exams': exams.map((e) => e.toJson()).toList(),
        'live': live,
        'banner': banner,
        if (termCode != null) 'termCode': termCode,
      };

  factory ExamsSnapshot.fromJson(Map<String, dynamic> json) {
    final examsRaw = json['exams'];
    final exams = <ExamArrangement>[];
    if (examsRaw is List) {
      for (final item in examsRaw) {
        if (item is Map) {
          exams.add(ExamArrangement.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return ExamsSnapshot(
      exams: exams,
      live: json['live'] as bool? ?? true,
      banner: json['banner'] as String? ?? '',
      termCode: json['termCode'] as String?,
    );
  }
}
