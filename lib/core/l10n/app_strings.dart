/// 骨架阶段集中存放中文文案。后续可迁移到 gen-l10n。
abstract final class AppStrings {
  static const String appName = '交大校园助手';
  static const String appSubtitle = '西安交通大学校园服务';
  static const String mockBanner = '当前为本地模拟数据，尚未连接学校服务器';

  static const String navHome = '首页';
  static const String navSchedule = '课表';
  static const String navClassroom = '教室';
  static const String navNotices = '通知';
  static const String navAlarms = '闹钟';

  static const String loginTitle = '统一身份认证（模拟）';
  static const String loginHint =
      '此页面对接学校 CAS（login.xjtu.edu.cn）的接口尚未实现。任意学号即可体验，密码不会上传，也不会写入日志。';
  static const String studentIdLabel = '学号';
  static const String studentIdHint = '请输入学号';
  static const String passwordLabel = '密码';
  static const String passwordHint = '模拟登录，不会提交到学校';
  static const String passwordRequired = '请输入密码';
  static const String loginAction = '模拟登录';
  static const String logoutAction = '退出登录';
  static const String loginSuccess = '已进入模拟会话';
  static const String loginRequired = '请输入学号';
  static const String guestName = '未登录';
  static const String guestHint = '登录后可同步课表与通知（即将支持 CAS）';
  static const String loggedInAs = '当前学号';
  static const String casAdapterNote = '真实 CAS / ehall / 一网通办适配器将在此替换 MockAuthRepository';

  static const String today = '今天';
  static const String nextClass = '下一节课';
  static const String noClassToday = '今天没有课程';
  static const String weekView = '周视图';
  static const String listView = '列表';
  static const String teacher = '教师';
  static const String location = '地点';
  static const String periods = '节次';
  static const String weeks = '周次';
  static const String emptySchedule = '本周暂无课程';
  static const String scheduleSubtitle = '兴庆校区 · 模拟课表';

  static const String classroomTitle = '空闲教室';
  static const String classroomSubtitle = '按校区 / 楼宇筛选（模拟）';
  static const String campusFilter = '校区';
  static const String buildingFilter = '教学楼';
  static const String slotFilter = '时段';
  static const String allCampuses = '全部校区';
  static const String allBuildings = '全部楼宇';
  static const String allSlots = '全天';
  static const String seats = '座位数';
  static const String emptyClassrooms = '没有符合条件的空闲教室';
  static const String freeNow = '当前空闲';

  static const String noticesTitle = '教务通知';
  static const String noticesSubtitle = '规则过滤占位，后续接入教务推送';
  static const String filterAll = '全部';
  static const String emptyNotices = '暂无通知';
  static const String personalizedAlert = '个性化提醒';
  static const String filterRulesHint = '可按关键词、课程名、考试周自动归类（骨架阶段仅本地规则）';

  static const String alarmsTitle = '上课提醒';
  static const String alarmsSubtitle = '根据课表一键生成起床闹钟与课前提醒';
  static const String wakeOffsetLabel = '起床提前量';
  static const String minutesUnit = '分钟';
  static const String suggestedAlarms = '建议闹钟';
  static const String wakeUpAlarm = '起床闹钟';
  static const String classReminder = '上课提醒';
  static const String createAlarms = '一键创建闹钟';
  static const String alarmsCreated = '已模拟创建闹钟（尚未写入系统闹钟）';
  static const String noAlarms = '课表为空，无法生成提醒';
  static const String firstClass = '第一节课';
  static const String alarmStubHint =
      '当前仅预览与模拟创建。接入系统通知后，将使用本地通知权限，不会把课表上传到第三方。';

  static const String loading = '加载中…';
  static const String retry = '重试';
  static const String errorTitle = '加载失败';
  static const String errorGeneric = '出了点问题，请稍后重试。';
  static const String quickActions = '快捷入口';
  static const String openLogin = '去登录';
  static const String weekPrefix = '第';
  static const String weekSuffix = '周';
  static const String termLabel = '2026-2027 学年 第一学期';

  static const List<String> weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  static const List<String> weekdayFull = [
    '星期一',
    '星期二',
    '星期三',
    '星期四',
    '星期五',
    '星期六',
    '星期日',
  ];
}
