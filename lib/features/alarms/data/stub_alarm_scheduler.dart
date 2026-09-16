import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/alarm_scheduler.dart';
import '../domain/alarm_suggestion.dart';

/// 测试或无插件环境使用的模拟调度。
class StubAlarmScheduler implements AlarmScheduler {
  StubAlarmScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<AlarmScheduleResult> createAlarms(
    List<AlarmSuggestion> suggestions,
  ) async {
    AppLogger.info(
      '模拟创建 ${suggestions.length} 个闹钟（${_plugin.runtimeType}）',
    );
    return AlarmScheduleResult(
      simulated: true,
      count: suggestions.length,
      message: '已模拟创建 ${suggestions.length} 个提醒',
    );
  }

  @override
  Future<void> cancelAlarms() async {}

  @override
  Future<AlarmScheduleResult> showTestNotification() async {
    return const AlarmScheduleResult(
      simulated: true,
      count: 1,
      message: '演示环境已模拟发送测试通知',
    );
  }

  @override
  Future<AlarmScheduleResult> scheduleOneShot({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    return AlarmScheduleResult(
      simulated: true,
      count: 1,
      message: '演示环境已模拟定时提醒',
    );
  }

  @override
  Future<void> cancelOneShot(int id) async {}
}
