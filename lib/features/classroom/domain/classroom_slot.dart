import 'package:equatable/equatable.dart';

class ClassroomSlot extends Equatable {
  const ClassroomSlot({
    required this.id,
    required this.campus,
    required this.building,
    required this.room,
    required this.capacity,
    required this.freePeriods,
    this.hasProjector = true,
  });

  final String id;
  final String campus;
  final String building;
  final String room;
  final int capacity;
  final List<int> freePeriods;
  final bool hasProjector;

  String get periodText {
    if (freePeriods.isEmpty) return '暂无空闲';
    return '第${freePeriods.first}-${freePeriods.last}节空闲';
  }

  @override
  List<Object?> get props => [
    id,
    campus,
    building,
    room,
    capacity,
    freePeriods,
    hasProjector,
  ];
}

class ClassroomQuery {
  const ClassroomQuery({this.campus, this.building, this.period});

  final String? campus;
  final String? building;
  final int? period;
}
