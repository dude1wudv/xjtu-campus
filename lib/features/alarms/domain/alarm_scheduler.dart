import '../domain/alarm_suggestion.dart';

/// 系统闹钟 / 本地通知调度。
abstract class AlarmScheduler {
  Future<AlarmScheduleResult> createAlarms(List<AlarmSuggestion> suggestions);

  Future<void> cancelAlarms();

  Future<AlarmScheduleResult> showTestNotification();
}
