/// 西安交通大学官方入口（仅作后续适配器对接说明，骨架阶段不会发起登录请求）。
///
/// 真实接入时请通过学校公开文档 / 开放接口 / 官方授权渠道实现，
/// **禁止**验证码绕过、抢课脚本或未授权抓取。
abstract final class CampusUrls {
  /// 统一身份认证 CAS。后续由 `CasAuthRepository` 对接。
  static const String casLogin = 'https://login.xjtu.edu.cn';

  /// 办事大厅 / 一网通办。课表、空闲教室等可在获得授权后从这里拉取。
  static const String ehall = 'https://ehall.xjtu.edu.cn';

  /// 一网通办移动端入口（路径以学校当期部署为准）。
  static const String ywtb = 'https://ywtb.xjtu.edu.cn';

  /// 教务处通知栏目（后续用官方 RSS / API，而不是页面抓取）。
  static const String jwcNotices = 'https://dean.xjtu.edu.cn';

  static const String schoolHome = 'https://www.xjtu.edu.cn';
}
