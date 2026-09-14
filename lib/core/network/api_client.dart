import 'package:http/http.dart' as http;

import '../constants/campus_urls.dart';

/// HTTP 客户端占位。后续 ehall / 一网通办适配器应通过此入口发请求。
///
/// 骨架阶段不发起任何学校登录或抓取。Cookie 与 Token 只能来自用户授权后的 CAS 会话。
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 学校公开页面（非登录态）的预留读取。默认关闭，以免被误用做未授权抓取。
  Future<http.Response> getPublic(Uri uri) {
    if (!_isAllowedHost(uri.host)) {
      throw ArgumentError('拒绝访问未列入校园域名白名单的地址');
    }
    return _client.get(uri);
  }

  bool _isAllowedHost(String host) {
    const allowed = [
      'www.xjtu.edu.cn',
      'login.xjtu.edu.cn',
      'ehall.xjtu.edu.cn',
      'ywtb.xjtu.edu.cn',
      'dean.xjtu.edu.cn',
    ];
    return allowed.contains(host);
  }

  /// 后续 CasAuthRepository 将使用 [CampusUrls.casLogin]。
  Uri get casLoginUri => Uri.parse(CampusUrls.casLogin);

  void close() => _client.close();
}
