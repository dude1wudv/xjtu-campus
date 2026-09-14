/// 骨架阶段集中存放中文文案。后续可迁移到 gen-l10n。
abstract final class AppStrings {
  static const String appName = '交大校园助手';
  static const String appSubtitle = '西安交通大学校园服务';
  static const String mockBanner = '当前为本地模拟数据，尚未连接学校服务器';
  static const String liveBanner = '当前为学校实时数据（需已登录统一认证）。';
  static const String noticesLiveBanner = '当前为教务处公开教学通知（已自动归类）。';
  static const String webVpnLabel = '校外使用 WebVPN';
  static const String webVpnHint = '不在校园网时请打开，登录后通过 webvpn.xjtu.edu.cn 访问课表/教室';
  static const String liveFallbackBanner = '实时接口不可用，以下为演示数据，仅供浏览界面。';

  static const String navHome = '首页';
  static const String navSchedule = '课表';
  static const String navClassroom = '教室';
  static const String navNotices = '通知';
  static const String navAlarms = '闹钟';

  static const String loginTitle = '西安交大统一认证';
  static const String loginHint =
      '使用学号与统一认证密码登录 login.xjtu.edu.cn。也可先用演示模式浏览界面，演示不会联网。';
  static const String studentIdLabel = '学号';
  static const String studentIdHint = '请输入学号';
  static const String passwordLabel = '统一认证密码';
  static const String passwordHint = '密码只提交到学校，不会写入本地文件或日志';
  static const String passwordRequired = '请输入密码';
  static const String showPassword = '显示密码';
  static const String hidePassword = '隐藏密码';
  static const String loginAction = '统一认证登录';
  static const String loginDemo = '演示登录（不联网）';
  static const String logoutAction = '退出登录';
  static const String loginSuccess = '已登录统一认证';
  static const String loginDemoSuccess = '已进入演示会话';
  static const String loginRequired = '请输入学号';
  static const String guestName = '未登录';
  static const String guestHint = '登录后可同步课表、空闲教室与上课提醒';
  static const String loggedInAs = '当前学号';
  static const String captchaLabel = '验证码';
  static const String captchaLead = '学校要求输入图形验证码。请按图片填写，应用不会自动识别。';
  static const String refreshCaptcha = '刷新验证码';
  static const String mfaCodeLabel = '短信验证码';
  static const String mfaLead =
      '账号开启了安全验证。验证码发到学校预留手机，请填写后再次登录。应用不会绕过二次验证。';
  static const String mfaPhonePrefix = '已发送至 ';
  static const String resendMfa = '重新发送短信';
  static const String accountChoiceLead = '该账号有多个身份，请选择本次使用的身份。';
  static const String loginPrivacy =
      '学号与密码只在本机提交到 login.xjtu.edu.cn；密码不会写入本地文件，也不会上传到第三方。会话 Cookie 保存在系统安全存储中。';

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
  static const String scheduleSubtitle = '兴庆校区课表';

  static const String classroomTitle = '空闲教室';
  static const String classroomSubtitle = '按校区 / 楼宇筛选；登录后查询教务空闲教室';
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
  static const String noticesSubtitle = '教务处教学通知，可按分类过滤';
  static const String filterAll = '全部';
  static const String emptyNotices = '暂无通知';
  static const String personalizedAlert = '个性化提醒';
  static const String filterRulesHint = '按分类过滤；标题含考试/选课等关键词会自动归类';

  static const String alarmsTitle = '上课提醒';
  static const String alarmsSubtitle = '根据课表一键生成起床闹钟与课前提醒';
  static const String wakeOffsetLabel = '起床提前量';
  static const String minutesUnit = '分钟';
  static const String suggestedAlarms = '建议闹钟';
  static const String wakeUpAlarm = '起床闹钟';
  static const String classReminder = '上课提醒';
  static const String createAlarms = '一键创建闹钟';
  static const String alarmsCreated = '已创建本地通知';
  static const String noAlarms = '课表为空，无法生成提醒';
  static const String firstClass = '第一节课';
  static const String cancelAlarms = '取消已创建的提醒';
  static const String testNotification = '立即发送测试通知';
  static const String alarmStubHint =
      '一键创建会把未来 7 天仍未开始的课程写入本机通知（时区 Asia/Shanghai）：起床为当天第一节课提前量（默认 90 分钟），上课前提醒 30 / 15 分钟。Web / 部分桌面无法预约未来通知。';

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
