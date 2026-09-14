import 'alarm_suggestion.dart';

/// 系统闹钟 / 本地通知调度。骨架使用模拟实现。
abstract class AlarmScheduler {
  Future<AlarmScheduleResult> createAlarms(List<AlarmSuggestion> suggestions);
}
