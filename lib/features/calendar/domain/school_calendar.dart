import 'package:equatable/equatable.dart';

class CalendarEvent extends Equatable {
  const CalendarEvent({
    required this.name,
    required this.startDate,
    required this.endDate,
    this.remark = '',
  });

  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final String remark;

  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'remark': remark,
      };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      name: json['name'] as String? ?? '',
      startDate: DateTime.tryParse(json['startDate'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endDate: DateTime.tryParse(json['endDate'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      remark: json['remark'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [name, startDate, endDate, remark];
}

class SchoolTermInfo extends Equatable {
  const SchoolTermInfo({
    required this.id,
    required this.label,
    required this.startDate,
    required this.endDate,
    this.yearLabel,
  });

  final String id;
  final String label;
  final DateTime startDate;
  final DateTime endDate;
  final String? yearLabel;

  bool contains(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  /// Teaching week: Mon of week containing term start = week 1.
  int teachingWeekOf(DateTime day) {
    final mondayOfStart = startDate.subtract(
      Duration(days: startDate.weekday - DateTime.monday),
    );
    final mondayOfDay = day.subtract(
      Duration(days: day.weekday - DateTime.monday),
    );
    final days = mondayOfDay.difference(mondayOfStart).inDays;
    final week = (days ~/ 7) + 1;
    if (week < 1) return 1;
    return week;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        if (yearLabel != null) 'yearLabel': yearLabel,
      };

  factory SchoolTermInfo.fromJson(Map<String, dynamic> json) {
    return SchoolTermInfo(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      startDate: DateTime.tryParse(json['startDate'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endDate: DateTime.tryParse(json['endDate'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      yearLabel: json['yearLabel'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, label, startDate, endDate];
}

class CalendarSnapshot {
  const CalendarSnapshot({
    required this.terms,
    required this.currentTerm,
    required this.events,
    required this.teachingWeek,
    required this.live,
    required this.banner,
    this.syncedWithScheduleWeek,
    this.fromCache = false,
    this.cachedAt,
    this.fetchedAt,
  });

  final List<SchoolTermInfo> terms;
  final SchoolTermInfo? currentTerm;
  final List<CalendarEvent> events;
  final int teachingWeek;
  final bool live;
  final String banner;

  /// When non-null, home/schedule ClassPeriod week was preferred.
  final int? syncedWithScheduleWeek;
  final bool fromCache;
  final DateTime? cachedAt;
  final DateTime? fetchedAt;

  CalendarSnapshot copyWith({
    List<SchoolTermInfo>? terms,
    SchoolTermInfo? currentTerm,
    List<CalendarEvent>? events,
    int? teachingWeek,
    bool? live,
    String? banner,
    int? syncedWithScheduleWeek,
    bool? fromCache,
    DateTime? cachedAt,
    DateTime? fetchedAt,
    bool clearCurrentTerm = false,
    bool clearSynced = false,
    bool clearCachedAt = false,
    bool clearFetchedAt = false,
  }) {
    return CalendarSnapshot(
      terms: terms ?? this.terms,
      currentTerm:
          clearCurrentTerm ? null : (currentTerm ?? this.currentTerm),
      events: events ?? this.events,
      teachingWeek: teachingWeek ?? this.teachingWeek,
      live: live ?? this.live,
      banner: banner ?? this.banner,
      syncedWithScheduleWeek: clearSynced
          ? null
          : (syncedWithScheduleWeek ?? this.syncedWithScheduleWeek),
      fromCache: fromCache ?? this.fromCache,
      cachedAt: clearCachedAt ? null : (cachedAt ?? this.cachedAt),
      fetchedAt: clearFetchedAt ? null : (fetchedAt ?? this.fetchedAt),
    );
  }

  CalendarSnapshot asCached(DateTime savedAt, {required String banner}) =>
      copyWith(
        fromCache: true,
        cachedAt: savedAt,
        banner: banner,
        clearFetchedAt: true,
      );

  CalendarSnapshot asFresh({String? banner}) => copyWith(
        fromCache: false,
        fetchedAt: DateTime.now(),
        banner: banner ?? this.banner,
        clearCachedAt: true,
      );

  Map<String, dynamic> toJson() => {
        'terms': terms.map((t) => t.toJson()).toList(),
        if (currentTerm != null) 'currentTerm': currentTerm!.toJson(),
        'events': events.map((e) => e.toJson()).toList(),
        'teachingWeek': teachingWeek,
        'live': live,
        'banner': banner,
        if (syncedWithScheduleWeek != null)
          'syncedWithScheduleWeek': syncedWithScheduleWeek,
      };

  factory CalendarSnapshot.fromJson(Map<String, dynamic> json) {
    final terms = <SchoolTermInfo>[];
    final termsRaw = json['terms'];
    if (termsRaw is List) {
      for (final item in termsRaw) {
        if (item is Map) {
          terms.add(SchoolTermInfo.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    SchoolTermInfo? currentTerm;
    final ct = json['currentTerm'];
    if (ct is Map) {
      currentTerm = SchoolTermInfo.fromJson(Map<String, dynamic>.from(ct));
    }
    final events = <CalendarEvent>[];
    final eventsRaw = json['events'];
    if (eventsRaw is List) {
      for (final item in eventsRaw) {
        if (item is Map) {
          events.add(CalendarEvent.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return CalendarSnapshot(
      terms: terms,
      currentTerm: currentTerm,
      events: events,
      teachingWeek: (json['teachingWeek'] as num?)?.toInt() ?? 1,
      live: json['live'] as bool? ?? true,
      banner: json['banner'] as String? ?? '',
      syncedWithScheduleWeek:
          (json['syncedWithScheduleWeek'] as num?)?.toInt(),
    );
  }
}
