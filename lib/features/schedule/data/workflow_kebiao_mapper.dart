import '../../../core/logging/app_logger.dart';
import '../domain/course.dart';

/// Maps YWTB workflow `getUndergraduateKebiao` JSON into [Course]s.
///
/// Documented sample (`docs/workflow-kebiao-sample.json`):
/// `{ "e": 0, "d": [ { KCM, KCBH, JSXM, BJJSMC, ZC, XQ, KSJC, JSJC,
/// XNXQDM, TERMNAME, ... } ], "m": "操作成功" }`
///
/// Still accepts List roots and alternate wrapper keys; unknown top-level
/// keys are logged for debugging.
abstract final class WorkflowKebiaoMapper {
  static List<Course> fromJson(Object? root) {
    if (root == null) return const [];

    final list = _extractList(root);
    if (list == null) {
      AppLogger.warn('workflow 课表 JSON 未能识别为列表');
      return const [];
    }

    final courses = <Course>[];
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is! Map) continue;
      final row = _normalizeKeys(Map<Object?, Object?>.from(item));
      final course = _mapRow(row, i);
      if (course != null) courses.add(course);
    }
    return courses;
  }

  /// Term code from first row (`XNXQDM` / `TERMNAME`), if present.
  static String? termOf(Object? root) {
    final list = _extractList(root);
    if (list == null || list.isEmpty) return null;
    final first = list.first;
    if (first is! Map) return null;
    final row = _normalizeKeys(Map<Object?, Object?>.from(first));
    return _firstString(row, const ['xnxqdm', 'termname', 'term', 'xnxq']);
  }

  static List<dynamic>? _extractList(Object? root) {
    if (root == null) return null;
    if (root is List) {
      AppLogger.info('workflow 课表根节点为 List');
      return root;
    }
    if (root is! Map) return null;

    final normalized = _normalizeKeys(Map<Object?, Object?>.from(root));
    _logUnknownTopLevel(normalized);

    // Sample shape: { e, d: [...], m }
    const listKeys = [
      'd',
      'data',
      'datas',
      'list',
      'rows',
      'result',
      'kebiao',
      'courses',
      'records',
      'items',
      'content',
      '课表',
      '数据',
    ];
    for (final key in listKeys) {
      final value = normalized[key];
      if (value is List) return value;
      if (value is Map) {
        final nested = _normalizeKeys(Map<Object?, Object?>.from(value));
        for (final nestedKey in listKeys) {
          final inner = nested[nestedKey];
          if (inner is List) return inner;
        }
      }
    }
    final collected = <dynamic>[];
    for (final value in normalized.values) {
      if (value is List) collected.addAll(value);
    }
    return collected.isEmpty ? null : collected;
  }

  static void _logUnknownTopLevel(Map<String, dynamic> normalized) {
    const known = {
      'e',
      'd',
      'm',
      'data',
      'datas',
      'list',
      'rows',
      'result',
      'kebiao',
      'courses',
      'records',
      'items',
      'content',
      'code',
      'msg',
      'message',
      'success',
      'status',
      'total',
      'count',
      'page',
      '课表',
      '数据',
    };
    final unknown = normalized.keys.where((k) => !known.contains(k)).toList();
    if (unknown.isNotEmpty) {
      AppLogger.info('workflow 课表未知顶层字段: ${unknown.join(', ')}');
    }
  }

  static Course? _mapRow(Map<String, dynamic> row, int index) {
    // Sample: KCM
    final name = _firstString(row, const [
      'kcm',
      'kcmc',
      'coursename',
      'course_name',
      'course',
      'name',
      'title',
      '课程名',
      '课程名称',
      '课程',
    ]);
    if (name == null || name.isEmpty) return null;

    // Sample: JSXM
    final teacher = _firstString(row, const [
          'jsxm',
          'skjs',
          'teacher',
          'teachername',
          'teacher_name',
          'js',
          '教师',
          '老师',
          '授课教师',
        ]) ??
        '';

    // Sample: BJJSMC
    final room = _firstString(row, const [
          'bjjsmc',
          'jasmc',
          'jsmc',
          'classroom',
          'room',
          'location',
          'place',
          'skdd',
          'cdmc',
          '教室',
          '地点',
          '上课地点',
        ]) ??
        '';

    final campus = _firstString(row, const [
          'xxxqmc',
          'xxxqdm_display',
          'campus',
          'xiaoqu',
          'xqmc',
          '校区',
        ]) ??
        '';

    // Sample: XQ as string "1".."7" (Mon..Sun)
    var weekday = _firstInt(row, const [
      'xq',
      'skxq',
      'weekday',
      'dayofweek',
      'xingqi',
      '星期',
      '周几',
    ]);
    weekday ??= _weekdayFromText(_firstString(row, const [
      'xq',
      'skxq',
      'weekday',
      '星期',
      'weekname',
      'xqmc',
    ]));
    weekday ??= 1;

    // Sample: KSJC / JSJC ints
    var startPeriod = _firstInt(row, const [
      'ksjc',
      'startsection',
      'startperiod',
      'startjc',
      'jc',
      'section',
      'beginsection',
      '开始节次',
      '节次',
    ]);
    var endPeriod = _firstInt(row, const [
      'jsjc',
      'endsection',
      'endperiod',
      'endjc',
      '结束节次',
    ]);

    if (startPeriod == null || endPeriod == null) {
      final fromJc = _periodsFromJcText(_firstString(row, const [
        'jc',
        'jcdm',
        'jcmc',
        'section',
        'sections',
        '节次',
        '上课节次',
      ]));
      startPeriod ??= fromJc?.$1;
      endPeriod ??= fromJc?.$2;
    }

    if (startPeriod == null || endPeriod == null) {
      final startTime = _firstString(row, const [
        'starttime',
        'kssj',
        'begintime',
        '开始时间',
      ]);
      final endTime = _firstString(row, const [
        'endtime',
        'jssj',
        '结束时间',
      ]);
      startPeriod ??= _periodFromClock(startTime);
      endPeriod ??= _periodFromClock(endTime) ?? startPeriod;
    }

    startPeriod ??= 1;
    endPeriod ??= startPeriod;
    if (endPeriod < startPeriod) endPeriod = startPeriod;

    // Sample: ZC weeks string e.g. "1" or "1-16" / mask
    final weeksRaw = _firstString(row, const [
          'zc',
          'skzc',
          'weeks',
          'zcs',
          'weeklist',
          'kkzc',
          '周次',
          '上课周次',
        ]) ??
        '';
    final weeks = _parseWeeks(weeksRaw, row);

    // Sample: KCBH / BJID
    final code = _firstString(row, const ['kcbh', 'bjid', 'wid', 'id', 'pkinfoid']);
    final term = _firstString(row, const ['xnxqdm', 'termname']) ?? '';
    final id = code != null && code.isNotEmpty
        ? '$code-$weekday-$startPeriod-$endPeriod-${weeksRaw.isEmpty ? index : weeksRaw}'
        : '$name-$weekday-$startPeriod-$index-$term';

    return Course(
      id: id,
      name: name,
      teacher: teacher,
      campus: campus,
      building: _buildingOf(room),
      room: room,
      weekday: weekday.clamp(1, 7),
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      weeks: weeks,
      weeksLabel: weeks.isEmpty
          ? weeksRaw
          : (weeksRaw.contains('周')
              ? weeksRaw
              : (weeks.length == 1
                  ? '${weeks.first}周'
                  : '${weeks.first}-${weeks.last}周')),
    );
  }

  static Map<String, dynamic> _normalizeKeys(Map<Object?, Object?> raw) {
    final out = <String, dynamic>{};
    raw.forEach((key, value) {
      if (key == null) return;
      out[key.toString().trim().toLowerCase()] = value;
    });
    return out;
  }

  static String? _firstString(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key.toLowerCase()];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return null;
  }

  static int? _firstInt(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key.toLowerCase()];
      if (value == null) continue;
      if (value is int) return value;
      if (value is num) return value.toInt();
      final text = value.toString().trim();
      final asInt = int.tryParse(text);
      if (asInt != null) return asInt;
      final digit = RegExp(r'\d+').firstMatch(text);
      if (digit != null) return int.tryParse(digit.group(0)!);
    }
    return null;
  }

  static int? _weekdayFromText(String? text) {
    if (text == null || text.isEmpty) return null;
    final lower = text.toLowerCase();
    const map = {
      '周一': 1,
      '星期一': 1,
      'monday': 1,
      'mon': 1,
      '周二': 2,
      '星期二': 2,
      'tuesday': 2,
      'tue': 2,
      '周三': 3,
      '星期三': 3,
      'wednesday': 3,
      'wed': 3,
      '周四': 4,
      '星期四': 4,
      'thursday': 4,
      'thu': 4,
      '周五': 5,
      '星期五': 5,
      'friday': 5,
      'fri': 5,
      '周六': 6,
      '星期六': 6,
      'saturday': 6,
      'sat': 6,
      '周日': 7,
      '星期日': 7,
      '星期天': 7,
      'sunday': 7,
      'sun': 7,
    };
    for (final entry in map.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return int.tryParse(text);
  }

  static (int, int)? _periodsFromJcText(String? text) {
    if (text == null || text.isEmpty) return null;
    final nums = RegExp(r'\d+')
        .allMatches(text)
        .map((m) => int.tryParse(m.group(0)!))
        .whereType<int>()
        .toList();
    if (nums.isEmpty) return null;
    if (nums.length == 1) return (nums.first, nums.first);
    return (nums.first, nums.last);
  }

  static int? _periodFromClock(String? clock) {
    if (clock == null || clock.isEmpty) return null;
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(clock);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final total = hour * 60 + minute;
    ClassPeriod? best;
    var bestDelta = 1 << 30;
    // Match against both season catalogs (afternoon differs by 30 min).
    for (final period in [
      ...ClassPeriod.catalogWinter,
      ...ClassPeriod.catalogSummer,
    ]) {
      final delta = (period.start.inMinutes - total).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        best = period;
      }
    }
    return best?.index;
  }

  static List<int> _parseWeeks(String raw, Map<String, dynamic> row) {
    if (raw.isNotEmpty) {
      // Binary mask like jwxt SKZC — only when long enough.
      if (RegExp(r'^[01]+$').hasMatch(raw) && raw.length >= 4) {
        final weeks = <int>[];
        for (var i = 0; i < raw.length; i++) {
          if (raw[i] == '1') weeks.add(i + 1);
        }
        return weeks;
      }
      final fromRanges = _weeksFromRangeText(raw);
      if (fromRanges.isNotEmpty) return fromRanges;
    }

    final listValue = row['weeks'] ?? row['zclist'] ?? row['weeklist'];
    if (listValue is List) {
      return listValue
          .map((e) => int.tryParse(e.toString()))
          .whereType<int>()
          .toList();
    }
    return const [];
  }

  static List<int> _weeksFromRangeText(String text) {
    final weeks = <int>{};
    final cleaned = text.replaceAll('周', ',').replaceAll('，', ',');
    for (final part in cleaned.split(RegExp(r'[,;\s]+'))) {
      final token = part.trim();
      if (token.isEmpty) continue;
      final range = RegExp(r'^(\d+)\s*[-~—–]\s*(\d+)$').firstMatch(token);
      if (range != null) {
        final a = int.parse(range.group(1)!);
        final b = int.parse(range.group(2)!);
        final start = a < b ? a : b;
        final end = a < b ? b : a;
        for (var w = start; w <= end; w++) {
          weeks.add(w);
        }
        continue;
      }
      final single = int.tryParse(token);
      if (single != null) weeks.add(single);
    }
    final sorted = weeks.toList()..sort();
    return sorted;
  }

  static String _buildingOf(String room) {
    if (room.contains('-')) return room.split('-').first;
    return room;
  }
}
