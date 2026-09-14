import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/alarm_scheduler.dart';
import '../domain/alarm_suggestion.dart';

/// 预留 [FlutterLocalNotificationsPlugin]，骨架阶段只模拟创建，不申请权限、不弹系统通知。
class StubAlarmScheduler implements AlarmScheduler {
  StubAlarmScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  // 真实接入时：初始化时区、请求权限，再 zonedSchedule。
  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<AlarmScheduleResult> createAlarms(
    List<AlarmSuggestion> suggestions,
  ) async {
    AppLogger.info(
      '模拟创建 ${suggestions.length} 个闹钟（插件 ${_plugin.runtimeType} 已预留，未调度系统通知）',
    );
    for (final item in suggestions) {
      AppLogger.debugSafe(
        '闹钟预览: ${item.kind.name} ${item.title} @ ${item.fireAt}',
      );
    }
    return AlarmScheduleResult(
      simulated: true,
      count: suggestions.length,
      message: '已模拟创建 ${suggestions.length} 个提醒，尚未写入系统闹钟',
    );
  }
}
