import 'package:http/http.dart' as http;

import '../constants/campus_urls.dart';

/// 带 Cookie 的校园 HTTP 客户端。仅允许学校域名。
/// 登录后的课表 / 教室请求必须走此会话，不要另开无 Cookie 的客户端。
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
      'jwxt.xjtu.edu.cn',
      'authx-service.xjtu.edu.cn',
      'dean.xjtu.edu.cn',
    ];
    return allowed.contains(host);
  }

  /// 后续 CasAuthRepository 使用 [CampusUrls.casLogin]。
  Uri get casLoginUri => Uri.parse(CampusUrls.casLogin);

  void close() => _client.close();
}
