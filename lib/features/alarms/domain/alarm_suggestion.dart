import 'package:equatable/equatable.dart';

import '../../schedule/domain/course.dart';

enum AlarmKind { wakeUp, classReminder }

class AlarmSuggestion extends Equatable {
  const AlarmSuggestion({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.fireAt,
    required this.course,
    required this.minutesBefore,
  });

  final String id;
  final AlarmKind kind;
  final String title;
  final String body;
  final DateTime fireAt;
  final Course course;
  final int minutesBefore;

  @override
  List<Object?> get props => [
    id,
    kind,
    title,
    body,
    fireAt,
    course,
    minutesBefore,
  ];
}

class AlarmScheduleResult extends Equatable {
  const AlarmScheduleResult({
    required this.simulated,
    required this.count,
    required this.message,
  });

  final bool simulated;
  final int count;
  final String message;

  @override
  List<Object?> get props => [simulated, count, message];
}
