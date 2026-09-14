import '../../../core/constants/app_constants.dart';
import '../../schedule/domain/course.dart';
import 'alarm_suggestion.dart';

/// 根据课表计算起床闹钟与课前提醒。纯 Dart，便于单测。
class AlarmPlanner {
  const AlarmPlanner();

  List<AlarmSuggestion> plan({
    required List<Course> courses,
    required DateTime now,
    Duration wakeOffset = AppConstants.defaultWakeOffset,
    List<Duration> reminderOffsets = AppConstants.defaultClassReminders,
    int daysAhead = 7,
  }) {
    final suggestions = <AlarmSuggestion>[];
    for (var offset = 0; offset < daysAhead; offset++) {
      final day = DateTime(now.year, now.month, now.day).add(Duration(days: offset));
      final weekday = day.weekday;
      final todayCourses = courses.where((course) => course.weekday == weekday).toList()
        ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
      if (todayCourses.isEmpty) continue;

      final first = todayCourses.first;
      final firstStart = first.startAt(day);
      final wakeAt = firstStart.subtract(wakeOffset);
      if (!wakeAt.isBefore(now)) {
        suggestions.add(
          AlarmSuggestion(
            id: 'wake-${first.id}-${_ymd(day)}',
            kind: AlarmKind.wakeUp,
            title: '起床 · ${first.name}',
            body:
                '${_weekdayLabel(weekday)} 第一节 ${first.name} ${first.start.formatClock().split('–').first} @ ${first.location}',
            fireAt: wakeAt,
            course: first,
            minutesBefore: wakeOffset.inMinutes,
          ),
        );
      }

      for (final course in todayCourses) {
        final start = course.startAt(day);
        for (final reminder in reminderOffsets) {
          final fireAt = start.subtract(reminder);
          if (fireAt.isBefore(now)) continue;
          suggestions.add(
            AlarmSuggestion(
              id: 'class-${course.id}-${reminder.inMinutes}-${_ymd(day)}',
              kind: AlarmKind.classReminder,
              title: '${course.name} · ${reminder.inMinutes}分钟后上课',
              body: '${course.location}  ${course.periodLabel}',
              fireAt: fireAt,
              course: course,
              minutesBefore: reminder.inMinutes,
            ),
          );
        }
      }
    }
    suggestions.sort((a, b) => a.fireAt.compareTo(b.fireAt));
    return suggestions;
  }

  String _ymd(DateTime day) =>
      '${day.year}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}';

  String _weekdayLabel(int weekday) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return '周${labels[weekday - 1]}';
  }
}
