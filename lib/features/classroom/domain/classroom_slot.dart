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

  Map<String, dynamic> toJson() => {
    'id': id,
    'campus': campus,
    'building': building,
    'room': room,
    'capacity': capacity,
    'freePeriods': freePeriods,
    'hasProjector': hasProjector,
  };

  factory ClassroomSlot.fromJson(Map<String, dynamic> json) {
    final periodsRaw = json['freePeriods'];
    final freePeriods = <int>[];
    if (periodsRaw is List) {
      for (final p in periodsRaw) {
        if (p is num) freePeriods.add(p.toInt());
      }
    }
    return ClassroomSlot(
      id: json['id'] as String? ?? '',
      campus: json['campus'] as String? ?? '',
      building: json['building'] as String? ?? '',
      room: json['room'] as String? ?? '',
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      freePeriods: freePeriods,
      hasProjector: json['hasProjector'] as bool? ?? true,
    );
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
    this.fromCache = false,
    this.cachedAt,
    this.fetchedAt,
    this.queryCampus,
    this.queryBuilding,
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
  final bool fromCache;
  final DateTime? cachedAt;
  final DateTime? fetchedAt;
  final String? queryCampus;
  final String? queryBuilding;

  ClassroomPageData copyWith({
    List<ClassroomSlot>? rooms,
    bool? live,
    String? banner,
    List<String>? campuses,
    List<String>? buildingsForCampus,
    int? buildingCount,
    bool? fromCache,
    DateTime? cachedAt,
    DateTime? fetchedAt,
    String? queryCampus,
    String? queryBuilding,
    bool clearCachedAt = false,
    bool clearFetchedAt = false,
  }) {
    return ClassroomPageData(
      rooms: rooms ?? this.rooms,
      live: live ?? this.live,
      banner: banner ?? this.banner,
      campuses: campuses ?? this.campuses,
      buildingsForCampus: buildingsForCampus ?? this.buildingsForCampus,
      buildingCount: buildingCount ?? this.buildingCount,
      fromCache: fromCache ?? this.fromCache,
      cachedAt: clearCachedAt ? null : (cachedAt ?? this.cachedAt),
      fetchedAt: clearFetchedAt ? null : (fetchedAt ?? this.fetchedAt),
      queryCampus: queryCampus ?? this.queryCampus,
      queryBuilding: queryBuilding ?? this.queryBuilding,
    );
  }

  ClassroomPageData asCached(DateTime savedAt, {required String banner}) =>
      copyWith(
        fromCache: true,
        cachedAt: savedAt,
        banner: banner,
        clearFetchedAt: true,
      );

  ClassroomPageData asFresh({String? banner}) => copyWith(
        fromCache: false,
        fetchedAt: DateTime.now(),
        banner: banner ?? this.banner,
        clearCachedAt: true,
      );

  Map<String, dynamic> toJson() => {
        'rooms': rooms.map((r) => r.toJson()).toList(),
        'live': live,
        'banner': banner,
        'campuses': campuses,
        'buildingsForCampus': buildingsForCampus,
        'buildingCount': buildingCount,
        if (queryCampus != null) 'queryCampus': queryCampus,
        if (queryBuilding != null) 'queryBuilding': queryBuilding,
      };

  factory ClassroomPageData.fromJson(Map<String, dynamic> json) {
    final rooms = <ClassroomSlot>[];
    final roomsRaw = json['rooms'];
    if (roomsRaw is List) {
      for (final item in roomsRaw) {
        if (item is Map) {
          rooms.add(ClassroomSlot.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    List<String> strList(Object? raw) {
      if (raw is! List) return const [];
      return [for (final e in raw) if (e is String) e];
    }

    return ClassroomPageData(
      rooms: rooms,
      live: json['live'] as bool? ?? true,
      banner: json['banner'] as String? ?? '',
      campuses: strList(json['campuses']),
      buildingsForCampus: strList(json['buildingsForCampus']),
      buildingCount: (json['buildingCount'] as num?)?.toInt() ?? 0,
      queryCampus: json['queryCampus'] as String?,
      queryBuilding: json['queryBuilding'] as String?,
    );
  }
}
