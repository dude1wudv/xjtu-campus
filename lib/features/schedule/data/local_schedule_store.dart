import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/course.dart';
import '../domain/schedule_repository.dart';

/// Portable timetable only: never export school credentials or session data.
class LocalScheduleStore {
  static const key = 'schedule.local.v1';

  static String encode(ScheduleSnapshot snapshot) =>
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'termStart': snapshot.termStart?.toIso8601String(),
        'week': snapshot.week,
        'exportedAt': DateTime.now().toIso8601String(),
        'sourceMonday': snapshot.sourceMonday?.toIso8601String(),
        'currentWeekOnly': snapshot.currentWeekOnly,
        'courses': snapshot.courses.map((c) => c.toJson()).toList(),
      });

  static ScheduleSnapshot decode(String raw, {DateTime? now}) {
    if (raw.length > 2000000) throw const FormatException('课表文件过大');
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic> ||
        json['version'] != 1 ||
        json['courses'] is! List) {
      throw const FormatException('请使用校园助手导出的课表 JSON');
    }
    final rows = json['courses'] as List;
    if (rows.length > 1000) throw const FormatException('课程数量超过限制');
    final courses = rows.map((row) {
      if (row is! Map<String, dynamic>) throw const FormatException('课程格式不正确');
      final c = Course.fromJson(row);
      if (c.id.isEmpty ||
          c.name.trim().isEmpty ||
          c.weekday < 1 ||
          c.weekday > 7 ||
          c.startPeriod < 1 ||
          c.endPeriod > 11 ||
          c.startPeriod > c.endPeriod ||
          c.weeks.any((w) => w < 1 || w > 60)) {
        throw const FormatException('请检查课程名称、星期、节次和教学周');
      }
      return c;
    }).toList();
    final today = now ?? DateTime.now();
    final start = DateTime.tryParse(json['termStart']?.toString() ?? '');
    final exported = DateTime.tryParse(json['exportedAt']?.toString() ?? '');
    final week = json['week'];
    if (week is! int || week < 1 || week > 60)
      throw const FormatException('教学周必须为 1–60');
    final anchor = start ?? exported;
    final monday = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: today.weekday - 1));
    final anchorMonday = anchor == null
        ? monday
        : DateTime(
            anchor.year,
            anchor.month,
            anchor.day,
          ).subtract(Duration(days: anchor.weekday - 1));
    final currentWeek =
        (start != null ? 1 : week) +
        monday.difference(anchorMonday).inDays ~/ 7;
    return ScheduleSnapshot(
      courses: courses,
      week: currentWeek,
      live: false,
      imported: true,
      termStart: start,
      banner: '本地课表 · 不会自动同步学校变更',
      currentWeekOnly: json['currentWeekOnly'] == true,
      sourceMonday:
          DateTime.tryParse(json['sourceMonday']?.toString() ?? '') ?? exported,
      cachedAt: exported,
    );
  }

  static Future<ScheduleSnapshot?> read() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    return raw == null ? null : decode(raw);
  }

  static Future<void> save(String raw) async {
    decode(raw);
    await (await SharedPreferences.getInstance()).setString(key, raw);
  }

  static Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(key);
  }
}
