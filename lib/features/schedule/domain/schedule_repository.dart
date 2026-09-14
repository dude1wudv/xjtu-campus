import 'course.dart';

class ScheduleSnapshot {
  const ScheduleSnapshot({
    required this.courses,
    required this.week,
    required this.live,
    required this.banner,
    this.termStart,
    this.fromCache = false,
    this.cachedAt,
    this.fetchedAt,
  });

  final List<Course> courses;
  final int week;
  final bool live;
  final String banner;
  final DateTime? termStart;

  /// True when this value was restored from local cache (may be stale).
  final bool fromCache;

  /// When the cached payload was originally saved (UTC or local wall clock).
  final DateTime? cachedAt;

  /// When this live fetch completed (for 「刚刚更新」).
  final DateTime? fetchedAt;

  ScheduleSnapshot copyWith({
    List<Course>? courses,
    int? week,
    bool? live,
    String? banner,
    DateTime? termStart,
    bool? fromCache,
    DateTime? cachedAt,
    DateTime? fetchedAt,
    bool clearTermStart = false,
    bool clearCachedAt = false,
    bool clearFetchedAt = false,
  }) {
    return ScheduleSnapshot(
      courses: courses ?? this.courses,
      week: week ?? this.week,
      live: live ?? this.live,
      banner: banner ?? this.banner,
      termStart: clearTermStart ? null : (termStart ?? this.termStart),
      fromCache: fromCache ?? this.fromCache,
      cachedAt: clearCachedAt ? null : (cachedAt ?? this.cachedAt),
      fetchedAt: clearFetchedAt ? null : (fetchedAt ?? this.fetchedAt),
    );
  }

  ScheduleSnapshot asCached(DateTime savedAt, {required String banner}) =>
      copyWith(
        fromCache: true,
        cachedAt: savedAt,
        banner: banner,
        clearFetchedAt: true,
      );

  ScheduleSnapshot asFresh({required String banner}) => copyWith(
        fromCache: false,
        fetchedAt: DateTime.now(),
        banner: banner,
        clearCachedAt: true,
      );

  Map<String, dynamic> toJson() => {
        'courses': courses.map((c) => c.toJson()).toList(),
        'week': week,
        'live': live,
        'banner': banner,
        if (termStart != null) 'termStart': termStart!.toIso8601String(),
      };

  factory ScheduleSnapshot.fromJson(Map<String, dynamic> json) {
    final coursesRaw = json['courses'];
    final courses = <Course>[];
    if (coursesRaw is List) {
      for (final item in coursesRaw) {
        if (item is Map) {
          courses.add(Course.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return ScheduleSnapshot(
      courses: courses,
      week: (json['week'] as num?)?.toInt() ?? 1,
      live: json['live'] as bool? ?? true,
      banner: json['banner'] as String? ?? '',
      termStart: json['termStart'] is String
          ? DateTime.tryParse(json['termStart'] as String)
          : null,
    );
  }
}

/// 课表数据源。登录后走 ehall / jwxt；失败或未登录回退演示数据。
abstract class ScheduleRepository {
  Future<int> currentWeek({DateTime? now});

  Future<List<Course>> fetchCourses();

  Future<ScheduleSnapshot> load({DateTime? now});
}
