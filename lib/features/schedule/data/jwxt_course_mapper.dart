import '../domain/course.dart';

abstract final class JwxtCourseMapper {
  static List<Course> fromRows(List<dynamic> rows) {
    final courses = <Course>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final name = row['KCM']?.toString() ?? '';
      if (name.isEmpty) continue;
      final weekday = _int(row['SKXQ']) ?? 1;
      final startPeriod = _int(row['KSJC']) ?? 1;
      final endPeriod = _int(row['JSJC']) ?? startPeriod;
      final weeks = _weeks(row['SKZC']?.toString() ?? '');
      final room = row['JASMC']?.toString() ?? '';
      final campus = row['XXXQMC']?.toString() ??
          row['XXXQDM_DISPLAY']?.toString() ??
          '';
      courses.add(
        Course(
          id: row['WID']?.toString() ??
              '$name-$weekday-$startPeriod-${row['XNXQDM']}',
          name: name,
          teacher: row['SKJS']?.toString() ?? '',
          campus: campus,
          building: _buildingOf(room),
          room: room,
          weekday: weekday.clamp(1, 7),
          startPeriod: startPeriod,
          endPeriod: endPeriod,
          weeks: weeks,
          weeksLabel: weeks.isEmpty ? '' : '${weeks.first}-${weeks.last}周',
        ),
      );
    }
    return courses;
  }

  static List<int> _weeks(String mask) {
    final weeks = <int>[];
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == '1') weeks.add(i + 1);
    }
    return weeks;
  }

  static int? _int(Object? value) {
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  static String _buildingOf(String room) {
    if (room.contains('-')) return room.split('-').first;
    return room;
  }
}
