import 'package:equatable/equatable.dart';

/// 交大常见 45 分钟小节，含课间。
///
/// 夏秋季（5/1 起）下午从 14:30 开始；冬春季（10/1 起）下午从 14:00 开始。
/// 上午与晚间保持一致，仅下午 5–8 节整体平移 30 分钟。
class ClassPeriod extends Equatable {
  const ClassPeriod({
    required this.index,
    required this.start,
    required this.end,
  });

  final int index;
  final Duration start;
  final Duration end;

  String get label => '第$index节';

  String formatClock() => '${_clock(start)}–${_clock(end)}';

  static String _clock(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  static const _morning = [
    ClassPeriod(
      index: 1,
      start: Duration(hours: 8),
      end: Duration(hours: 8, minutes: 45),
    ),
    ClassPeriod(
      index: 2,
      start: Duration(hours: 8, minutes: 55),
      end: Duration(hours: 9, minutes: 40),
    ),
    ClassPeriod(
      index: 3,
      start: Duration(hours: 10, minutes: 10),
      end: Duration(hours: 10, minutes: 55),
    ),
    ClassPeriod(
      index: 4,
      start: Duration(hours: 11, minutes: 5),
      end: Duration(hours: 11, minutes: 50),
    ),
  ];

  static const _evening = [
    ClassPeriod(
      index: 9,
      start: Duration(hours: 19),
      end: Duration(hours: 19, minutes: 45),
    ),
    ClassPeriod(
      index: 10,
      start: Duration(hours: 19, minutes: 55),
      end: Duration(hours: 20, minutes: 40),
    ),
    ClassPeriod(
      index: 11,
      start: Duration(hours: 20, minutes: 50),
      end: Duration(hours: 21, minutes: 35),
    ),
  ];

  /// 冬春季作息：下午从 14:00 起（10/1 起）。
  static const catalogWinter = [
    ..._morning,
    ClassPeriod(
      index: 5,
      start: Duration(hours: 14),
      end: Duration(hours: 14, minutes: 45),
    ),
    ClassPeriod(
      index: 6,
      start: Duration(hours: 14, minutes: 55),
      end: Duration(hours: 15, minutes: 40),
    ),
    ClassPeriod(
      index: 7,
      start: Duration(hours: 16, minutes: 10),
      end: Duration(hours: 16, minutes: 55),
    ),
    ClassPeriod(
      index: 8,
      start: Duration(hours: 17, minutes: 5),
      end: Duration(hours: 17, minutes: 50),
    ),
    ..._evening,
  ];

  /// 夏秋季作息：下午从 14:30 起（5/1 起）。
  static const catalogSummer = [
    ..._morning,
    ClassPeriod(
      index: 5,
      start: Duration(hours: 14, minutes: 30),
      end: Duration(hours: 15, minutes: 15),
    ),
    ClassPeriod(
      index: 6,
      start: Duration(hours: 15, minutes: 25),
      end: Duration(hours: 16, minutes: 10),
    ),
    ClassPeriod(
      index: 7,
      start: Duration(hours: 16, minutes: 40),
      end: Duration(hours: 17, minutes: 25),
    ),
    ClassPeriod(
      index: 8,
      start: Duration(hours: 17, minutes: 35),
      end: Duration(hours: 18, minutes: 20),
    ),
    ..._evening,
  ];

  /// 兼容旧调用：默认取当前日期对应季节目录。
  static List<ClassPeriod> get catalog => catalogFor(DateTime.now());

  /// May–Sep → 夏秋季；Oct–Apr → 冬春季。
  static bool isSummerSeason(DateTime day) => day.month >= 5 && day.month <= 9;

  static List<ClassPeriod> catalogFor(DateTime now) =>
      isSummerSeason(now) ? catalogSummer : catalogWinter;

  static String seasonLabel(DateTime now) {
    if (isSummerSeason(now)) {
      return '当前：夏秋季作息（5/1起）';
    }
    return '当前：冬春季作息（10/1起）';
  }

  static ClassPeriod byIndex(int index, {DateTime? day}) {
    final catalog = catalogFor(day ?? DateTime.now());
    for (final period in catalog) {
      if (period.index == index) return period;
    }
    return ClassPeriod(
      index: index,
      start: Duration(hours: 8 + (index - 1)),
      end: Duration(hours: 8 + (index - 1), minutes: 45),
    );
  }

  @override
  List<Object?> get props => [index, start, end];
}

class Course extends Equatable {
  const Course({
    required this.id,
    required this.name,
    required this.teacher,
    required this.campus,
    required this.building,
    required this.room,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeks,
    this.weeksLabel = '1-16周',
  });

  final String id;
  final String name;
  final String teacher;
  final String campus;
  final String building;
  final String room;
  final int weekday; // DateTime.monday = 1
  final int startPeriod;
  final int endPeriod;
  final List<int> weeks;
  final String weeksLabel;

  ClassPeriod get start => ClassPeriod.byIndex(startPeriod);
  ClassPeriod get end => ClassPeriod.byIndex(endPeriod);

  ClassPeriod startOf(DateTime day) =>
      ClassPeriod.byIndex(startPeriod, day: day);

  ClassPeriod endOf(DateTime day) => ClassPeriod.byIndex(endPeriod, day: day);

  String get location => '$campus $building $room';

  String get periodLabel => periodLabelFor(DateTime.now());

  String periodLabelFor(DateTime day) {
    final s = startOf(day);
    final e = endOf(day);
    return '第$startPeriod${startPeriod == endPeriod ? '' : '-$endPeriod'}节 '
        '${s.formatClock().split('–').first}–${e.formatClock().split('–').last}';
  }

  /// 用 [day] 当天季节作息计算开课时刻。
  DateTime startAt(DateTime day) =>
      DateTime(day.year, day.month, day.day).add(startOf(day).start);

  DateTime endAt(DateTime day) =>
      DateTime(day.year, day.month, day.day).add(endOf(day).end);

  static Course? nextAfter(
    List<Course> courses,
    DateTime now, {
    int? weekNumber,
  }) {
    Course? best;
    DateTime? bestStart;
    for (var offset = 0; offset < 8; offset++) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: offset));
      final week = weekNumber == null
          ? null
          : weekNumber + ((now.weekday - 1 + offset) ~/ 7);
      final ofDay = courses.where((course) {
        if (course.weekday != day.weekday) return false;
        if (week != null &&
            course.weeks.isNotEmpty &&
            !course.weeks.contains(week)) {
          return false;
        }
        return true;
      }).toList()..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
      for (final course in ofDay) {
        final start = course.startAt(day);
        if (start.isAfter(now) &&
            (bestStart == null || start.isBefore(bestStart))) {
          best = course;
          bestStart = start;
        }
      }
    }
    return best;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'teacher': teacher,
    'campus': campus,
    'building': building,
    'room': room,
    'weekday': weekday,
    'startPeriod': startPeriod,
    'endPeriod': endPeriod,
    'weeks': weeks,
    'weeksLabel': weeksLabel,
  };

  factory Course.fromJson(Map<String, dynamic> json) {
    final weeksRaw = json['weeks'];
    final weeks = <int>[];
    if (weeksRaw is List) {
      for (final w in weeksRaw) {
        if (w is num) weeks.add(w.toInt());
      }
    }
    return Course(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      teacher: json['teacher'] as String? ?? '',
      campus: json['campus'] as String? ?? '',
      building: json['building'] as String? ?? '',
      room: json['room'] as String? ?? '',
      weekday: (json['weekday'] as num?)?.toInt() ?? 1,
      startPeriod: (json['startPeriod'] as num?)?.toInt() ?? 1,
      endPeriod: (json['endPeriod'] as num?)?.toInt() ?? 1,
      weeks: weeks,
      weeksLabel: json['weeksLabel'] as String? ?? '1-16周',
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    teacher,
    campus,
    building,
    room,
    weekday,
    startPeriod,
    endPeriod,
    weeks,
    weeksLabel,
  ];
}
