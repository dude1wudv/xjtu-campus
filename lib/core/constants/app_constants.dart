/// 应用级常量。
abstract final class AppConstants {
  static const String appName = '交大校园助手';
  static const String appNameEn = 'xjtu_campus';
  static const String packageName = 'cn.edu.xjtu.xjtu_campus';

  /// 默认起床闹钟：第一节课开始前 90 分钟。
  static const Duration defaultWakeOffset = Duration(minutes: 90);

  /// 上课提醒可选提前量（分钟）。
  static const List<int> availableReminderMinutes = [45, 30, 15, 10, 5];

  /// 上课提醒：开课前 30 / 15 分钟。
  static const List<Duration> defaultClassReminders = [
    Duration(minutes: 30),
    Duration(minutes: 15),
  ];

  static const String alarmEnableWakeKey = 'settings.alarm.enable_wake';
  static const String alarmEnableClassKey = 'settings.alarm.enable_class';
  static const String alarmWakeMinutesKey = 'settings.alarm.wake_minutes';
  static const String alarmReminderMinutesKey =
      'settings.alarm.reminder_minutes';

  /// 一键闹钟覆盖今天起 7 天内仍未开始的课程。
  static const int alarmDaysAhead = 7;

  static const String sessionStudentIdKey = 'session.student_id';
  static const String sessionTokenKey = 'session.token';
  static const String sessionDisplayNameKey = 'session.display_name';
  static const String sessionModeKey = 'session.mode';
  static const String sessionYwtbIdTokenKey = 'session.ywtb_id_token';
  static const String cookiePrefix = 'cj.';

  static const String modeDemo = 'demo';
  static const String webVpnEnabledKey = 'settings.webvpn_enabled';
  static const String modeCas = 'cas';

  /// 凭据存储中禁止使用的键：明文密码不得长期驻留。
  static const String forbiddenPasswordKey = 'cas.password';

  /// GitHub 发布页（正式发布仓库）。
  static const String githubOwner = 'dude1wudv';
  static const String githubRepo = 'xjtu-campus';
  static const String githubRepoUrl = 'https://github.com/dude1wudv/xjtu-campus';
  static const String githubReleasesApi =
      'https://api.github.com/repos/dude1wudv/xjtu-campus/releases/latest';
}
