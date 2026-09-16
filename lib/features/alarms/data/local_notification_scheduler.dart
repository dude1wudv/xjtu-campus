import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/logging/app_logger.dart';
import '../domain/alarm_scheduler.dart';
import '../domain/alarm_suggestion.dart';

/// 使用 [FlutterLocalNotificationsPlugin] 在 Asia/Shanghai 调度本地通知。
class LocalNotificationScheduler implements AlarmScheduler {
  LocalNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  Future<void> ensureReady() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
      linux: LinuxInitializationSettings(defaultActionName: '打开'),
    );
    await _plugin.initialize(settings: init);
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
    _ready = true;
  }

  @override
  Future<AlarmScheduleResult> createAlarms(
    List<AlarmSuggestion> suggestions,
  ) async {
    try {
      await ensureReady();
    } on Object {
      AppLogger.warn('通知插件初始化失败，本平台可能不支持调度');
      return AlarmScheduleResult(
        simulated: true,
        count: 0,
        message: '当前平台无法注册系统通知（Web / 部分桌面），请在 Android 或 iOS 真机上使用',
      );
    }

    await cancelAlarms();
    final shanghai = tz.getLocation('Asia/Shanghai');
    var scheduled = 0;
    var fallbackShow = 0;

    for (var i = 0; i < suggestions.length; i++) {
      final item = suggestions[i];
      final when = tz.TZDateTime.from(item.fireAt, shanghai);
      if (when.isBefore(tz.TZDateTime.now(shanghai))) continue;
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          item.kind == AlarmKind.wakeUp ? 'wake_up' : 'class_reminders',
          item.kind == AlarmKind.wakeUp ? '起床闹钟' : '上课提醒',
          channelDescription: '根据课表生成的本地提醒，不会上传到学校以外的服务器',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      );
      try {
        await _plugin.zonedSchedule(
          id: 1000 + i,
          title: item.title,
          body: item.body,
          scheduledDate: when,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        scheduled += 1;
      } on Object {
        try {
          await _plugin.zonedSchedule(
            id: 1000 + i,
            title: item.title,
            body: item.body,
            scheduledDate: when,
            notificationDetails: details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
          scheduled += 1;
        } on Object {
          if (kIsWeb) {
            fallbackShow += 1;
          }
        }
      }
    }

    AppLogger.info('已调度 $scheduled 个本地通知（时区 Asia/Shanghai）');
    if (scheduled == 0) {
      return AlarmScheduleResult(
        simulated: true,
        count: fallbackShow,
        message: kIsWeb
            ? 'Web 端无法可靠预约未来通知，请使用 Android / iOS 客户端'
            : '未能写入系统闹钟，请检查通知权限',
      );
    }
    return AlarmScheduleResult(
      simulated: false,
      count: scheduled,
      message: '已创建 $scheduled 个本地通知（未来 7 天，Asia/Shanghai）',
    );
  }

  @override
  Future<AlarmScheduleResult> showTestNotification() async {
    try {
      await ensureReady();
    } on Object {
      return const AlarmScheduleResult(
        simulated: true,
        count: 0,
        message: '当前平台无法弹出系统通知（请使用 Android / iOS 客户端）',
      );
    }
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'class_reminders',
        '上课提醒',
        channelDescription: '根据课表生成的本地提醒，不会上传到学校以外的服务器',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    try {
      await _plugin.show(
        id: 9,
        title: '交大校园助手',
        body: '本地通知已就绪。一键创建闹钟会按课表预约未来 7 天的提醒。',
        notificationDetails: details,
      );
      return const AlarmScheduleResult(
        simulated: false,
        count: 1,
        message: '已发送一条即时测试通知',
      );
    } on Object {
      return AlarmScheduleResult(
        simulated: true,
        count: 0,
        message: kIsWeb
            ? 'Web 端无法可靠预约未来通知，即时通知也受浏览器限制，请使用 Android / iOS 客户端'
            : '未能弹出系统通知，请检查通知权限',
      );
    }
  }

  @override
  Future<void> cancelAlarms() async {
    try {
      await _plugin.cancelAll();
    } on Object {
      // 未初始化时忽略。
    }
  }

  static const int librarySeatNotifyId = 71001;

  @override
  Future<AlarmScheduleResult> scheduleOneShot({
    required int id,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    try {
      await ensureReady();
    } on Object {
      return const AlarmScheduleResult(
        simulated: true,
        count: 0,
        message: '当前平台无法注册系统通知',
      );
    }
    final shanghai = tz.getLocation('Asia/Shanghai');
    final whenTz = tz.TZDateTime.from(when, shanghai);
    if (whenTz.isBefore(tz.TZDateTime.now(shanghai))) {
      return const AlarmScheduleResult(
        simulated: true,
        count: 0,
        message: '开始时间已过期',
      );
    }
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'library_seats',
        '图书馆座位',
        channelDescription: '定时座位预约提醒（仅本地）',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: whenTz,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'library_seat_book',
      );
      return AlarmScheduleResult(
        simulated: false,
        count: 1,
        message: '已设置本地提醒',
      );
    } on Object {
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: whenTz,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'library_seat_book',
        );
        return const AlarmScheduleResult(
          simulated: false,
          count: 1,
          message: '已设置本地提醒（非精确闹钟）',
        );
      } on Object {
        return const AlarmScheduleResult(
          simulated: true,
          count: 0,
          message: '未能写入系统通知，请检查权限',
        );
      }
    }
  }

  @override
  Future<void> cancelOneShot(int id) async {
    try {
      await _plugin.cancel(id: id);
    } on Object {
      // ignore
    }
  }
}
