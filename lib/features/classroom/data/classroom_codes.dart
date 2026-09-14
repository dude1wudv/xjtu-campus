import '../domain/classroom_slot.dart';

/// One option from jwxt/ehall `/jwapp/code/*.do` (`id` / `name` / optional campus).
class ClassroomCode {
  const ClassroomCode({
    required this.id,
    required this.name,
    this.campusCode,
  });

  final String id;
  final String name;

  /// Buildings expose `otherFields.XXXQDM` (campus code). Campuses leave this null.
  final String? campusCode;
}

/// Parsed campus + building maps used to query cxkxjs and populate UI dropdowns.
class ClassroomCodeMaps {
  const ClassroomCodeMaps({
    required this.campuses,
    required this.buildings,
  });

  final List<ClassroomCode> campuses;
  final List<ClassroomCode> buildings;

  bool get isEmpty => campuses.isEmpty || buildings.isEmpty;

  static const preferredCampusOrder = [
    '兴庆校区',
    '雁塔校区',
    '创新港校区',
    '曲江校区',
    '苏州校区',
    '海南创新中心',
  ];

  List<String> get campusNames {
    final names = [
      for (final campus in campuses)
        if (campus.name.trim().isNotEmpty) campus.name,
    ];
    names.sort((a, b) {
      final ia = preferredCampusOrder.indexOf(a);
      final ib = preferredCampusOrder.indexOf(b);
      final sa = ia < 0 ? 99 : ia;
      final sb = ib < 0 ? 99 : ib;
      if (sa != sb) return sa.compareTo(sb);
      return a.compareTo(b);
    });
    return names;
  }

  String? campusIdFor(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final needle = name.trim();
    for (final campus in campuses) {
      if (campus.name == needle) return campus.id;
    }
    final stripped = needle.replaceAll('校区', '');
    for (final campus in campuses) {
      final campusStripped = campus.name.replaceAll('校区', '');
      if (campus.name.contains(needle) ||
          needle.contains(campus.name) ||
          (stripped.isNotEmpty && campusStripped.contains(stripped))) {
        return campus.id;
      }
    }
    return null;
  }

  ClassroomCode? buildingFor(String name, {String? campusName}) {
    if (name.trim().isEmpty) return null;
    final campusId = campusIdFor(campusName);
    final exact = buildings.where((b) => b.name == name).toList();
    if (exact.isEmpty) {
      final fuzzy = buildings.where((b) => b.name.contains(name)).toList();
      if (fuzzy.isEmpty) return null;
      if (campusId != null) {
        for (final building in fuzzy) {
          if (building.campusCode == campusId) return building;
        }
      }
      return fuzzy.first;
    }
    if (campusId != null) {
      for (final building in exact) {
        if (building.campusCode == campusId) return building;
      }
    }
    return exact.first;
  }

  List<ClassroomCode> buildingsForCampus(String? campusName) {
    if (buildings.isEmpty) return const [];
    final campusId = campusIdFor(campusName);
    if (campusId == null) return buildings;
    final filtered =
        buildings.where((building) => building.campusCode == campusId).toList();
    return filtered.isNotEmpty ? filtered : buildings;
  }

  List<String> buildingNamesFor(String? campusName) => [
        for (final building in buildingsForCampus(campusName))
          if (building.name.trim().isNotEmpty) building.name,
      ];

  /// Counts of buildings grouped by campus display name.
  Map<String, int> buildingCountsByCampus() {
    final idToName = <String, String>{
      for (final campus in campuses) campus.id: campus.name,
    };
    final counts = <String, int>{};
    for (final building in buildings) {
      final label = idToName[building.campusCode ?? ''] ??
          (building.campusCode == null || building.campusCode!.isEmpty
              ? '未知校区'
              : building.campusCode!);
      counts[label] = (counts[label] ?? 0) + 1;
    }
    return counts;
  }

  static ClassroomCodeMaps parse({
    required Object? campusJson,
    required Object? buildingJson,
  }) {
    return ClassroomCodeMaps(
      campuses: parseCodeRows(campusJson),
      buildings: parseCodeRows(buildingJson),
    );
  }

  static List<ClassroomCode> parseCodeRows(Object? json) {
    final rows = _codeRows(json);
    final parsed = <ClassroomCode>[];
    final seen = <String>{};
    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final id = row['id']?.toString() ?? '';
      final name = row['name']?.toString() ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      final key = '$id|$name';
      if (!seen.add(key)) continue;
      parsed.add(
        ClassroomCode(
          id: id,
          name: name,
          campusCode: _campusCodeOf(row),
        ),
      );
    }
    return parsed;
  }

  static List<dynamic> _codeRows(Object? json) {
    if (json is Map) {
      final rows = json['datas']?['code']?['rows'];
      if (rows is List) return rows;
    }
    return const [];
  }

  static String? _campusCodeOf(Map<String, dynamic> row) {
    final other = row['otherFields'];
    if (other is Map) {
      final value = other['XXXQDM'] ?? other['xxxqdm'];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    final direct = row['XXXQDM'];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct.toString();
    }
    return null;
  }
}

class ClassroomParseResult {
  const ClassroomParseResult({
    required this.rooms,
    this.totalSize,
    this.hasPeriodFields = false,
  });

  final List<ClassroomSlot> rooms;
  final int? totalSize;
  final bool hasPeriodFields;
}

/// Shared cxkxjs row parsing / fan-out / occupancy policy (Dio + WebView).
abstract final class ClassroomQueryLogic {
  static const int pageSize = 500;
  static const int concurrency = 5;
  static const int firstPeriod = 1;
  static const int lastPeriod = 11;
  static const int maxPeriod = 13;

  static bool shouldFanOut({
    required List<ClassroomSlot> rooms,
    int? totalSize,
    int pageSize = ClassroomQueryLogic.pageSize,
  }) {
    if (rooms.isEmpty) return true;
    final buildings = rooms
        .map((room) => room.building.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    if (buildings.length < 2) return true;
    if (totalSize != null && totalSize > rooms.length) return true;
    if (rooms.length >= pageSize) return true;
    return false;
  }

  static int? totalSizeOf(Object? json) {
    if (json is! Map) return null;
    final table = json['datas']?['cxkxjs'];
    if (table is! Map) return null;
    final value = table['totalSize'] ?? table['total'] ?? table['totalCount'];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static List<dynamic> cxkxjsRows(Object? json) {
    if (json is Map) {
      final rows = json['datas']?['cxkxjs']?['rows'];
      if (rows is List) return rows;
    }
    return const [];
  }

  /// Reject exam/notice/non-classroom venue rows; keep numbered teaching rooms.
  static final _roomDigits = RegExp(r'\d{2,}');
  static const _rejectNameNeedles = [
    '考试',
    '通知',
    '测试专用',
    '非教室',
    '仓库',
    '厕所',
    '卫生间',
    '走廊',
    '电梯',
  ];

  /// Prefer JASMC like `主楼A-102` / `A-102`; fall back to JASH / display.
  static String roomNameFromRow(Map<dynamic, dynamic> row) {
    for (final key in [
      'JASMC',
      'jasmc',
      'JASH',
      'jash',
      'JASDM_DISPLAY',
      'jasdm_display',
    ]) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String roomTypeLabel(Map<dynamic, dynamic> row) {
    return (row['JASLXDM_DISPLAY'] ??
            row['jaslxdm_display'] ??
            row['JASLXMC'] ??
            row['jaslxmc'] ??
            '')
        .toString()
        .trim();
  }

  static String roomTypeCode(Map<dynamic, dynamic> row) {
    return (row['JASLXDM'] ?? row['jaslxdm'] ?? '').toString().trim();
  }

  /// True for normal teaching rooms with a digit room number.
  static bool isNormalTeachingRoom(Map<dynamic, dynamic> row) {
    final name = roomNameFromRow(row);
    if (name.isEmpty) return false;
    for (final needle in _rejectNameNeedles) {
      if (name.contains(needle)) return false;
    }
    final typeLabel = roomTypeLabel(row);
    for (final needle in _rejectNameNeedles) {
      if (typeLabel.contains(needle)) return false;
    }
    if (typeLabel.contains('办公室') || typeLabel.contains('值班室')) {
      return false;
    }
    if (!_roomDigits.hasMatch(name)) return false;
    return true;
  }

  static ClassroomParseResult parseResult(
    Object? json, {
    required ClassroomQuery query,
    String? fallbackBuilding,
    required int start,
    required int end,
  }) {
    final rows = cxkxjsRows(json);
    final rooms = <ClassroomSlot>[];
    final seen = <String>{};
    var hasPeriodFields = false;
    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      if (!isNormalTeachingRoom(row)) continue;
      final name = roomNameFromRow(row);
      final building = (row['JXLDM_DISPLAY'] ?? row['jxlmc'])?.toString() ??
          fallbackBuilding ??
          '';
      final campus =
          (row['XXXQDM_DISPLAY'] ?? row['xxxqmc'])?.toString() ??
              query.campus ??
              '';
      final id = '$campus|$building|$name';
      if (!seen.add(id)) continue;
      if (rowHasPeriodFields(row)) hasPeriodFields = true;
      // Single-period query: appearance means free only for that period.
      // Range query: prefer KXJC / column fields; else treat as free in range.
      final List<int> free;
      if (start == end) {
        free = [start];
      } else {
        free = freePeriodsFromRow(row) ??
            [for (var period = start; period <= end; period++) period];
      }
      rooms.add(
        ClassroomSlot(
          id: id,
          campus: campus,
          building: building,
          room: name,
          capacity: int.tryParse(
                (row['SKZWS'] ?? row['skzws'] ?? row['ZWS'])?.toString() ?? '',
              ) ??
              0,
          freePeriods: free,
        ),
      );
    }
    return ClassroomParseResult(
      rooms: rooms,
      totalSize: totalSizeOf(json),
      hasPeriodFields: hasPeriodFields,
    );
  }

  static List<ClassroomSlot> parseRooms(
    Object? json, {
    required ClassroomQuery query,
    String? fallbackBuilding,
    required int start,
    required int end,
  }) =>
      parseResult(
        json,
        query: query,
        fallbackBuilding: fallbackBuilding,
        start: start,
        end: end,
      ).rooms;

  static bool rowHasPeriodFields(Map<dynamic, dynamic> row) {
    final keys = {
      for (final key in row.keys) key.toString().toUpperCase(),
    };
    for (var period = firstPeriod; period <= maxPeriod; period++) {
      for (final prefix in ['JC', 'JCS', 'KX', 'ZY', 'J', 'P', 'JC_']) {
        if (keys.contains('$prefix$period')) return true;
      }
      // ignore: unnecessary_brace_in_string_interps
      if (keys.contains('第${period}节')) return true;
    }
    // KXJC/KXJCS alone means "free periods list for a range query" — that does
    // NOT mean we can skip per-period fan-out (range query only returns rooms
    // free for the entire KSJC..JSJC window).
    const columnMasks = [
      'KB',
      'ZYQK',
      'KXQK',
      'JCKXQK',
      'ZYBZ',
      'KXBZ',
    ];
    for (final name in columnMasks) {
      if (keys.contains(name)) return true;
    }
    return false;
  }

  /// Returns free period numbers when the row encodes occupancy; otherwise null.
  static List<int>? freePeriodsFromRow(Map<dynamic, dynamic> row) {
    final byKey = <String, dynamic>{
      for (final entry in row.entries) entry.key.toString().toUpperCase(): entry.value,
    };

    final columnFree = <int, bool>{};
    var sawColumn = false;
    for (var period = firstPeriod; period <= maxPeriod; period++) {
      final occupyValue = byKey['ZY$period'];
      final freeValue = byKey['KX$period'];
      final jcValue = byKey['JC$period'] ??
          byKey['JCS$period'] ??
          byKey['J$period'] ??
          byKey['P$period'] ??
          byKey['JC_$period'] ??
          // ignore: unnecessary_brace_in_string_interps
          byKey['第${period}节'];
      if (occupyValue != null) {
        sawColumn = true;
        columnFree[period] = !_isOccupiedValue(occupyValue, occupySemantics: true);
      } else if (freeValue != null) {
        sawColumn = true;
        columnFree[period] = _isFreeValue(freeValue, freeSemantics: true);
      } else if (jcValue != null) {
        sawColumn = true;
        columnFree[period] = !_isOccupiedValue(jcValue, occupySemantics: false);
      }
    }
    if (sawColumn) {
      final last = columnFree.keys.reduce((a, b) => a > b ? a : b);
      final until = last > lastPeriod ? last : lastPeriod;
      return [
        for (var period = firstPeriod; period <= until; period++)
          if (columnFree[period] ?? true) period,
      ];
    }

    final listValue = byKey['KXJC'] ??
        byKey['KXJCS'] ??
        byKey['KXJCLB'] ??
        byKey['FREEJC'] ??
        byKey['KXJCMC'];
    final fromList = _parsePeriodList(listValue);
    if (fromList != null) return fromList;

    final maskValue = byKey['KB'] ??
        byKey['ZYQK'] ??
        byKey['KXQK'] ??
        byKey['JCKXQK'] ??
        byKey['ZYBZ'] ??
        byKey['KXBZ'];
    final fromMask = _parseBitmask(maskValue);
    if (fromMask != null) return fromMask;

    return null;
  }

  static bool _isFreeValue(Object? raw, {required bool freeSemantics}) {
    if (raw == null) return !freeSemantics;
    if (raw is bool) return freeSemantics ? raw : !raw;
    final text = raw.toString().trim().toLowerCase();
    if (text.isEmpty ||
        text == '-' ||
        text == 'null' ||
        text == '无') {
      return !freeSemantics;
    }
    const freeTokens = {
      '0',
      'n',
      'no',
      'false',
      '空',
      '空闲',
      '闲',
      'free',
      '否',
      'kx',
    };
    const occupyTokens = {
      '1',
      'y',
      'yes',
      'true',
      '占用',
      '有课',
      '占',
      'busy',
      'occ',
      'zy',
    };
    if (freeTokens.contains(text)) return true;
    if (occupyTokens.contains(text)) return false;
    return !freeSemantics;
  }

  static bool _isOccupiedValue(Object? raw, {required bool occupySemantics}) {
    if (raw == null) return false;
    if (raw is bool) return occupySemantics ? raw : !raw;
    final text = raw.toString().trim().toLowerCase();
    if (text.isEmpty ||
        text == '-' ||
        text == 'null' ||
        text == '无' ||
        text == '0' ||
        text == 'n' ||
        text == 'no' ||
        text == 'false' ||
        text == '空' ||
        text == '空闲' ||
        text == '闲' ||
        text == 'free' ||
        text == '否' ||
        text == 'kx') {
      return false;
    }
    return true;
  }

  static List<int>? _parsePeriodList(Object? raw) {
    if (raw == null) return null;
    if (raw is List) {
      final periods = <int>{};
      for (final item in raw) {
        final value = int.tryParse(item.toString());
        if (value != null && value >= firstPeriod && value <= maxPeriod) {
          periods.add(value);
        }
      }
      if (periods.isEmpty) return null;
      return (periods.toList()..sort());
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    final periods = <int>{};
    for (final match in RegExp(r'(\d+)\s*[-~—到至]\s*(\d+)').allMatches(text)) {
      final start = int.tryParse(match.group(1)!);
      final end = int.tryParse(match.group(2)!);
      if (start == null || end == null) continue;
      final lo = start < end ? start : end;
      final hi = start < end ? end : start;
      for (var period = lo; period <= hi; period++) {
        if (period >= firstPeriod && period <= maxPeriod) periods.add(period);
      }
    }
    for (final match in RegExp(r'\d+').allMatches(text)) {
      final value = int.tryParse(match.group(0)!);
      if (value != null && value >= firstPeriod && value <= maxPeriod) {
        periods.add(value);
      }
    }
    if (periods.isEmpty) return null;
    return (periods.toList()..sort());
  }

  static List<int>? _parseBitmask(Object? raw) {
    if (raw == null) return null;
    final text = raw.toString().trim().replaceAll(RegExp(r'\s+'), '');
    if (text.length < lastPeriod) return null;
    if (!RegExp(r'^[01yn空占闲占用课]+$', caseSensitive: false).hasMatch(text) &&
        !RegExp(r'^[01]+$').hasMatch(text)) {
      if (!RegExp(r'^[01]+$').hasMatch(text)) return null;
    }
    if (!RegExp(r'^[01]+$').hasMatch(text)) return null;
    final last = text.length > lastPeriod ? text.length : lastPeriod;
    final bounded = last > maxPeriod ? maxPeriod : last;
    if (text.length < bounded) return null;
    return [
      for (var i = 0; i < bounded; i++)
        if (text[i] == '0') i + 1,
    ];
  }

  static List<ClassroomSlot> mergeRooms(Iterable<List<ClassroomSlot>> batches) {
    return mergeOccupancy(const {}, seeds: batches.expand((b) => b));
  }

  /// Union rooms from per-period queries.
  ///
  /// When [appearanceOnly] is true (cxkxjs KSJC=JSJC=p), a room is free only in
  /// periods where it appeared in that period's result; missing ⇒ occupied.
  static List<ClassroomSlot> mergeOccupancy(
    Map<int, List<ClassroomSlot>> byPeriod, {
    Iterable<ClassroomSlot> seeds = const [],
    bool appearanceOnly = false,
  }) {
    final rooms = <String, ClassroomSlot>{};
    final free = <String, Set<int>>{};

    void consider(ClassroomSlot room, Iterable<int> periods) {
      rooms.putIfAbsent(room.id, () => room);
      final slot = rooms[room.id]!;
      if (slot.capacity == 0 && room.capacity > 0) {
        rooms[room.id] = room;
      }
      free.putIfAbsent(room.id, () => <int>{});
      free[room.id]!.addAll(periods);
    }

    for (final room in seeds) {
      consider(room, room.freePeriods);
    }
    for (final entry in byPeriod.entries) {
      for (final room in entry.value) {
        if (appearanceOnly) {
          consider(room, [entry.key]);
        } else {
          final extra = room.freePeriods.isNotEmpty
              ? room.freePeriods
              : <int>[entry.key];
          consider(
            room,
            extra.contains(entry.key) ? extra : [...extra, entry.key],
          );
        }
      }
    }

    final merged = <ClassroomSlot>[];
    for (final id in rooms.keys) {
      final room = rooms[id]!;
      final periods = free[id]!.toList()..sort();
      merged.add(
        ClassroomSlot(
          id: room.id,
          campus: room.campus,
          building: room.building,
          room: room.room,
          capacity: room.capacity,
          freePeriods: periods,
          hasProjector: room.hasProjector,
        ),
      );
    }
    merged.sort((a, b) {
      final building = a.building.compareTo(b.building);
      if (building != 0) return building;
      return a.room.compareTo(b.room);
    });
    return merged;
  }

  static List<ClassroomSlot> filterByPeriod(
    List<ClassroomSlot> rooms,
    int? period,
  ) {
    if (period == null) return rooms;
    return rooms.where((room) => room.freePeriods.contains(period)).toList();
  }

  static String formatPeriodRanges(Iterable<int> periods) {
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

  static String liveBanner({
    required String? campus,
    required int buildingCount,
    required int roomCount,
  }) {
    if (roomCount == 0) {
      return '实时空闲教室：当前筛选下暂无空闲';
    }
    final campusShort = (campus ?? '')
        .replaceAll('校区', '')
        .replaceAll('创新中心', '')
        .trim();
    if (buildingCount > 0 && campusShort.isNotEmpty) {
      return '实时空闲教室 · $campusShort $buildingCount 栋楼 · $roomCount 间';
    }
    if (buildingCount > 0) {
      return '实时空闲教室 · $buildingCount 栋楼 · $roomCount 间';
    }
    return '实时空闲教室（优先 jwxt；校外可开 WebVPN）';
  }
}
