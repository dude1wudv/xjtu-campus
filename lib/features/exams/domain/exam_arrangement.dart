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
  });

  final List<ExamArrangement> exams;
  final bool live;
  final String banner;
  final String? termCode;
}
