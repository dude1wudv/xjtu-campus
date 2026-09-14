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
  });

  final List<GradeRecord> records;
  final bool live;
  final String banner;
  final Map<String, List<GradeRecord>> groupedByTerm;
}
