import 'package:equatable/equatable.dart';

/// One course grade row from jwxt cjcx (student's own transcript).
class GradeRecord extends Equatable {
  const GradeRecord({
    required this.termCode,
    required this.courseName,
    required this.credit,
    required this.gpaPoints,
    required this.score,
    this.usualScore,
    this.midtermScore,
    this.finalScore,
    this.examType,
    this.courseNature,
    this.courseCode,
  });

  final String termCode;
  final String courseName;
  final double credit;
  final double? gpaPoints;
  final String score;
  final String? usualScore;
  final String? midtermScore;
  final String? finalScore;
  final String? examType;
  final String? courseNature;
  final String? courseCode;

  Map<String, dynamic> toJson() => {
        'termCode': termCode,
        'courseName': courseName,
        'credit': credit,
        'gpaPoints': gpaPoints,
        'score': score,
        'usualScore': usualScore,
        'midtermScore': midtermScore,
        'finalScore': finalScore,
        'examType': examType,
        'courseNature': courseNature,
        'courseCode': courseCode,
      };

  factory GradeRecord.fromJson(Map<String, dynamic> json) {
    return GradeRecord(
      termCode: json['termCode'] as String? ?? '',
      courseName: json['courseName'] as String? ?? '',
      credit: (json['credit'] as num?)?.toDouble() ?? 0,
      gpaPoints: (json['gpaPoints'] as num?)?.toDouble(),
      score: json['score'] as String? ?? '',
      usualScore: json['usualScore'] as String?,
      midtermScore: json['midtermScore'] as String?,
      finalScore: json['finalScore'] as String?,
      examType: json['examType'] as String?,
      courseNature: json['courseNature'] as String?,
      courseCode: json['courseCode'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        termCode,
        courseName,
        credit,
        gpaPoints,
        score,
        courseCode,
      ];
}

class GradesSnapshot {
  const GradesSnapshot({
    required this.records,
    required this.live,
    required this.banner,
    this.groupedByTerm = const {},
    this.fromCache = false,
    this.cachedAt,
    this.fetchedAt,
  });

  final List<GradeRecord> records;
  final bool live;
  final String banner;
  final Map<String, List<GradeRecord>> groupedByTerm;
  final bool fromCache;
  final DateTime? cachedAt;
  final DateTime? fetchedAt;

  GradesSnapshot copyWith({
    List<GradeRecord>? records,
    bool? live,
    String? banner,
    Map<String, List<GradeRecord>>? groupedByTerm,
    bool? fromCache,
    DateTime? cachedAt,
    DateTime? fetchedAt,
    bool clearCachedAt = false,
    bool clearFetchedAt = false,
  }) {
    return GradesSnapshot(
      records: records ?? this.records,
      live: live ?? this.live,
      banner: banner ?? this.banner,
      groupedByTerm: groupedByTerm ?? this.groupedByTerm,
      fromCache: fromCache ?? this.fromCache,
      cachedAt: clearCachedAt ? null : (cachedAt ?? this.cachedAt),
      fetchedAt: clearFetchedAt ? null : (fetchedAt ?? this.fetchedAt),
    );
  }

  GradesSnapshot asCached(DateTime savedAt, {required String banner}) =>
      copyWith(
        fromCache: true,
        cachedAt: savedAt,
        banner: banner,
        clearFetchedAt: true,
      );

  GradesSnapshot asFresh({String? banner}) => copyWith(
        fromCache: false,
        fetchedAt: DateTime.now(),
        banner: banner ?? this.banner,
        clearCachedAt: true,
      );

  Map<String, List<GradeRecord>> get effectiveGrouped {
    if (groupedByTerm.isNotEmpty) return groupedByTerm;
    final map = <String, List<GradeRecord>>{};
    for (final r in records) {
      map.putIfAbsent(r.termCode, () => []).add(r);
    }
    return map;
  }

  Map<String, dynamic> toJson() => {
        'records': records.map((r) => r.toJson()).toList(),
        'live': live,
        'banner': banner,
      };

  factory GradesSnapshot.fromJson(Map<String, dynamic> json) {
    final recordsRaw = json['records'];
    final records = <GradeRecord>[];
    if (recordsRaw is List) {
      for (final item in recordsRaw) {
        if (item is Map) {
          records.add(GradeRecord.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final grouped = <String, List<GradeRecord>>{};
    for (final r in records) {
      grouped.putIfAbsent(r.termCode, () => []).add(r);
    }
    return GradesSnapshot(
      records: records,
      live: json['live'] as bool? ?? true,
      banner: json['banner'] as String? ?? '',
      groupedByTerm: grouped,
    );
  }
}
