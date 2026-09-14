/// 西安交通大学官方入口。仅用于学生本人登录后访问自己的课表 / 教室。
///
/// **禁止**验证码绕过、抢课脚本或未授权抓取。
abstract final class CampusUrls {
  static const String casOrigin = 'https://login.xjtu.edu.cn';
  static const String casLogin = 'https://login.xjtu.edu.cn/cas/login';
  /// 学校 CAS 已注册服务：一网通办（不要用 jwxt home 当 service，会报 missing service）。
  static const String casServiceYwtb =
      'https://ywtb.xjtu.edu.cn/?path=https%3A%2F%2Fywtb.xjtu.edu.cn%2Fmain.html%23%2FIndex';
  static const String casServiceEhall =
      'https://ehall.xjtu.edu.cn/new/index.html?browser=no';
  static const String casLoginYwtb =
      'https://login.xjtu.edu.cn/cas/login?service=https%3A%2F%2Fywtb.xjtu.edu.cn%2F%3Fpath%3Dhttps%253A%252F%252Fywtb.xjtu.edu.cn%252Fmain.html%2523%252FIndex&locale=zh';
  static const String casLoginEhall =
      'https://login.xjtu.edu.cn/cas/login?service=https%3A%2F%2Fehall.xjtu.edu.cn%2Fnew%2Findex.html%3Fbrowser%3Dno&locale=zh';
  static const String casPublicKey = 'https://login.xjtu.edu.cn/cas/jwt/publicKey';
  static const String casCaptcha = 'https://login.xjtu.edu.cn/cas/captcha.jpg';
  static const String casMfaDetect = 'https://login.xjtu.edu.cn/cas/mfa/detect';
  static const String casMfaInitPhone =
      'https://login.xjtu.edu.cn/cas/mfa/initByType/securephone';
  static const String casSecInitPhone =
      'https://login.xjtu.edu.cn/cas/sec/initByType/securephone';
  static const String casMfaSend =
      'https://login.xjtu.edu.cn/attest/api/guard/securephone/send';
  static const String casMfaValid =
      'https://login.xjtu.edu.cn/attest/api/guard/securephone/valid';

  static const String ehall = 'https://ehall.xjtu.edu.cn';
  static const String ehallHome =
      'https://ehall.xjtu.edu.cn/new/index.html?browser=no';
  static const String ehallLogin =
      'https://ehall.xjtu.edu.cn/login?service=https%3A%2F%2Fehall.xjtu.edu.cn%2Fnew%2Findex.html%3Fbrowser%3Dno';

  /// 本科教务已迁至 jwxt，课表模块路径与原 ehall「我的课表」一致。
  static const String jwxt = 'https://jwxt.xjtu.edu.cn';
  static const String jwxtHome =
      'https://jwxt.xjtu.edu.cn/jwapp/sys/homeapp/index.do';
  static const String jwxtCurrentTerm =
      'https://jwxt.xjtu.edu.cn/jwapp/sys/wdkb/modules/jshkcb/dqxnxq.do';
  static const String jwxtSchedule =
      'https://jwxt.xjtu.edu.cn/jwapp/sys/wdkb/modules/xskcb/xskcb.do';
  static const String jwxtTermStart =
      'https://jwxt.xjtu.edu.cn/jwapp/sys/wdkb/modules/jshkcb/cxjcs.do';
  static const String ehallCurrentTerm =
      'https://ehall.xjtu.edu.cn/jwapp/sys/wdkb/modules/jshkcb/dqxnxq.do';
  static const String ehallSchedule =
      'https://ehall.xjtu.edu.cn/jwapp/sys/wdkb/modules/xskcb/xskcb.do';
  static const String ehallTermStart =
      'https://ehall.xjtu.edu.cn/jwapp/sys/wdkb/modules/jshkcb/cxjcs.do';

  static const String jwxtCampusCode =
      'https://jwxt.xjtu.edu.cn/jwapp/code/83a986fc-e677-400e-99a4-c7bb39c2ca35.do';
  static const String jwxtBuildingCode =
      'https://jwxt.xjtu.edu.cn/jwapp/code/551fbcc3-cf07-4566-af1e-fc7ce272ddc1.do';
  static const String jwxtEmptyRoom =
      'https://jwxt.xjtu.edu.cn/jwapp/sys/kxjas/modules/kxjscx/cxkxjs.do';
  static const String jwxtCurrentUser =
      'https://jwxt.xjtu.edu.cn/jwapp/sys/homeapp/api/home/currentUser.do';
  static const String jwxtChangeRole =
      'https://jwxt.xjtu.edu.cn/jwapp/sys/homeapp/api/home/changeAppRole.do';
  static const String ehallKxjasIndex =
      'https://ehall.xjtu.edu.cn/jwapp/sys/kxjas/*default/index.do';
  static const String jwxtKxjasIndex =
      'https://jwxt.xjtu.edu.cn/jwapp/sys/kxjas/*default/index.do';
  static const String ehallEmptyRoom =
      'https://ehall.xjtu.edu.cn/jwapp/sys/kxjas/modules/kxjscx/cxkxjs.do';
  static const String ehallCampusCode =
      'https://ehall.xjtu.edu.cn/jwapp/code/83a986fc-e677-400e-99a4-c7bb39c2ca35.do';
  static const String ehallBuildingCode =
      'https://ehall.xjtu.edu.cn/jwapp/code/551fbcc3-cf07-4566-af1e-fc7ce272ddc1.do';
  static const String ehallCurrentUser =
      'https://ehall.xjtu.edu.cn/jwapp/sys/homeapp/api/home/currentUser.do';
  static const String ehallChangeRole =
      'https://ehall.xjtu.edu.cn/jwapp/sys/homeapp/api/home/changeAppRole.do';

  static const String ywtb = 'https://ywtb.xjtu.edu.cn';
  static const String ywtbMain = 'https://ywtb.xjtu.edu.cn/main.html';
  static const String ywtbCasLogin =
      'https://login.xjtu.edu.cn/cas/login?service=https%3A%2F%2Fywtb.xjtu.edu.cn%2F%3Fpath%3Dhttps%253A%252F%252Fywtb.xjtu.edu.cn%252Fmain.html%2523%252FIndex';
  static const String ywtbUser =
      'https://authx-service.xjtu.edu.cn/personal/api/v1/personal/me/user';

  /// 一网通办「课表查询」workflow（YWTB selectpage），浏览器实测 XHR。
  static const String workflow = 'https://workflow.xjtu.edu.cn';
  static const String workflowKebiaoPage =
      'https://workflow.xjtu.edu.cn/selectpage/page/site/newkebiao';
  static const String workflowSelKxueqi =
      'https://workflow.xjtu.edu.cn/selectpage/site/kebiao/selkxueqi';
  static const String workflowUndergraduateKebiao =
      'https://workflow.xjtu.edu.cn/selectpage/site/newkebiao/getUndergraduateKebiao';
  static const String workflowGroupKebiao =
      'https://workflow.xjtu.edu.cn/selectpage/site/newkebiao/getGroupKebiao';

  static const String jwcNotices = 'https://dean.xjtu.edu.cn';
  static const String schoolHome = 'https://www.xjtu.edu.cn';
  static const String webVpn = 'https://webvpn.xjtu.edu.cn';
  static const String webVpnLogin =
      'https://webvpn.xjtu.edu.cn/login?vpn-0';
  static const String deanNotices =
      'https://dean.xjtu.edu.cn/jxxx/jxtz2.htm';
  static const String dueNotices =
      'https://due.xjtu.edu.cn/jxxx/jxtz2.htm';

  /// 成绩查询（本科 jwxt cjcx）。
  static const String jwxtCjcxIndex =
      'https://jwxt.xjtu.edu.cn/jwapp/sys/cjcx/*default/index.do';
  static const String jwxtGrades =
      'https://jwxt.xjtu.edu.cn/jwapp/sys/cjcx/modules/cjcx/xscjcx.do';

  /// 我的考试安排。
  static const String jwxtWdksapIndex =
      'https://jwxt.xjtu.edu.cn/jwapp/sys/studentWdksapApp/*default/index.do';
  static const String jwxtExams =
      'https://jwxt.xjtu.edu.cn/jwapp/sys/studentWdksapApp/modules/wdksap/wdksap.do';

  /// 我的课表模块首页（soft-warm dqxnxq / cxjcs）。
  static const String jwxtWdkbIndex =
      'https://jwxt.xjtu.edu.cn/jwapp/sys/wdkb/*default/index.do';

  /// 校历（one2020 公开页；优先于 ywtb portal-api JWT）。
  static const String one2020Origin = 'http://one2020.xjtu.edu.cn';
  static const String one2020CalendarPage =
      'http://one2020.xjtu.edu.cn/EIP/edu/education/schoolcalendar/showCalendar.htm';
  static const String one2020Terms =
      'http://one2020.xjtu.edu.cn/EIP/schoolcalendar/terms.htm';
  static const String one2020TermById =
      'http://one2020.xjtu.edu.cn/EIP/edu/education/schoolcalendar/queryTermById.htm';
  static const String one2020OriginHttps = 'https://one2020.xjtu.edu.cn';
  static const String one2020CalendarPageHttps =
      'https://one2020.xjtu.edu.cn/EIP/edu/education/schoolcalendar/showCalendar.htm';
  static const String one2020TermsHttps =
      'https://one2020.xjtu.edu.cn/EIP/schoolcalendar/terms.htm';
  static const String one2020TermByIdHttps =
      'https://one2020.xjtu.edu.cn/EIP/edu/education/schoolcalendar/queryTermById.htm';

  /// 校园卡（本 sprint 不实现；仅保留 URL 备忘）。
  // TODO(ncard): 校园卡余额/流水 — https://ncard.xjtu.edu.cn/plat
  static const String ncardPlat = 'https://ncard.xjtu.edu.cn/plat';


  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
}
