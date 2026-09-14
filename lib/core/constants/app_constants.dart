/// 应用级常量。真实教务接口尚未接入，时间偏移等仅用于本地模拟。
abstract final class AppConstants {
  static const String appName = '交大校园助手';
  static const String appNameEn = 'xjtu_campus';
  static const String packageName = 'cn.edu.xjtu.xjtu_campus';

  /// 默认起床闹钟：第一节课开始前 90 分钟。
  static const Duration defaultWakeOffset = Duration(minutes: 90);

  /// 上课提醒：开课前 30 / 15 分钟。
  static const List<Duration> defaultClassReminders = [
    Duration(minutes: 30),
    Duration(minutes: 15),
  ];

  static const String sessionStudentIdKey = 'session.student_id';
  static const String sessionTokenKey = 'session.token';
  static const String sessionDisplayNameKey = 'session.display_name';

  /// 凭据存储中禁止使用的键：明文密码不得长期驻留。
  static const String forbiddenPasswordKey = 'cas.password';
}
