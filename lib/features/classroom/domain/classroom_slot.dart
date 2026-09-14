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

  static const int dayLastPeriod = 11;

  List<int> get occupiedPeriods => [
        for (var period = 1; period <= dayLastPeriod; period++)
          if (!freePeriods.contains(period)) period,
      ];

  bool get isFreeAllDay =>
      freePeriods.length >= dayLastPeriod && occupiedPeriods.isEmpty;

  /// 「空闲: 1-2,5-6,9-11」or 「全天占用」.
  String get periodText {
    if (freePeriods.isEmpty) return '全天占用';
    final ranges = _formatRanges(freePeriods);
    if (occupiedPeriods.isEmpty) return '空闲: 全天 1-$dayLastPeriod';
    return '空闲: $ranges';
  }

  static String _formatRanges(Iterable<int> periods) {
    final list = periods.toSet().toList()..sort();
    if (list.isEmpty) return '';
    final parts = <String>[];
    var start = list.first;
    var prev = list.first;
    for (var i = 1; i < list.length; i++) {
      if (list[i] == prev + 1) {
        prev = list[i];
        continue;
      }
      parts.add(start == prev ? '$start' : '$start-$prev');
      start = prev = list[i];
    }
    parts.add(start == prev ? '$start' : '$start-$prev');
    return parts.join(',');
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

class ClassroomPageData {
  const ClassroomPageData({
    required this.rooms,
    required this.live,
    required this.banner,
    this.campuses = const [],
    this.buildingsForCampus = const [],
    this.buildingCount = 0,
  });

  final List<ClassroomSlot> rooms;
  final bool live;
  final String banner;

  /// Live jwxt campus names; UI falls back to static list when empty.
  final List<String> campuses;

  /// Buildings for the selected campus (or all when campus is null).
  final List<String> buildingsForCampus;

  /// Number of buildings covered by the current campus filter.
  final int buildingCount;
}
