import '../domain/alarm_suggestion.dart';

/// 系统闹钟 / 本地通知调度。
abstract class AlarmScheduler {
  Future<AlarmScheduleResult> createAlarms(List<AlarmSuggestion> suggestions);

  Future<void> cancelAlarms();

  Future<AlarmScheduleResult> showTestNotification();

  /// One-shot local notification (e.g. library seat schedule reminder).
  Future<AlarmScheduleResult> scheduleOneShot({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  });

  Future<void> cancelOneShot(int id);
}
