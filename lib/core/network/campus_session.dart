import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../constants/app_constants.dart';
import '../constants/campus_urls.dart';
import '../logging/app_logger.dart';
import '../storage/credential_store.dart';
import 'secure_cookie_storage.dart';
import 'webvpn_url.dart';

/// 带 Cookie 的校园 HTTP 客户端。仅允许学校相关域名。
class CampusSession {
  CampusSession(this._store) {
    _jar = PersistCookieJar(
      persistSession: true,
      ignoreExpires: false,
      storage: SecureCookieStorage(_store),
    );
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 25),
        receiveTimeout: const Duration(seconds: 35),
        sendTimeout: const Duration(seconds: 25),
        followRedirects: true,
        maxRedirects: 12,
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null && status < 500,
        headers: {
          'User-Agent': CampusUrls.userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      ),
    );
    _dio.interceptors.add(CookieManager(_jar));
  }

  final CredentialStore _store;
  late final PersistCookieJar _jar;
  late final Dio _dio;

  Dio get dio => _dio;
  CookieJar get jar => _jar;

  String? ywtbIdToken;
  bool useWebVpn = false;

  Future<void> restore() async {
    try {
      await _jar.forceInit().timeout(const Duration(seconds: 3));
      ywtbIdToken = await _store.read('session.ywtb_id_token');
      useWebVpn = (await _store.read(AppConstants.webVpnEnabledKey)) == '1';
    } on Object {
      AppLogger.warn('校园 Cookie 恢复失败，将以未登录会话继续');
    }
  }

  Future<void> setUseWebVpn(bool enabled) async {
    useWebVpn = enabled;
    await _store.write(
      key: AppConstants.webVpnEnabledKey,
      value: enabled ? '1' : '0',
    );
  }

  Future<bool> hasCasCookie() async {
    try {
      final origins = [
        CampusUrls.casLogin,
        CampusUrls.ywtbMain,
        CampusUrls.ehallHome,
        CampusUrls.jwxtHome,
        CampusUrls.workflowKebiaoPage,
      ];
      for (final origin in origins) {
        final cookies = await _jar.loadForRequest(Uri.parse(origin));
        for (final cookie in cookies) {
          final name = cookie.name.toUpperCase();
          if (name.contains('TGC') ||
              name.contains('CASTGC') ||
              name.contains('SESSION') ||
              name == 'ROUTE' ||
              name.contains('MOD_AUTH') ||
              name.contains('JSESSIONID') ||
              name.contains('SSO') ||
              name.contains('TOKEN')) {
            return true;
          }
        }
        if (cookies.isNotEmpty) {
          // 一网通办登录后常见仅有业务 Cookie，也视为已登录会话。
          return true;
        }
      }
      return false;
    } on Object {
      return false;
    }
  }

  /// 把 WebView 登录拿到的 Cookie 写入会话。
  Future<void> importCookies(
    Iterable<({String name, String value, String? domain, String? path})>
        cookies,
  ) async {
    final byHost = <Uri, List<Cookie>>{};
    final importedNames = <String>{};
    const mirrorHosts = [
      'login.xjtu.edu.cn',
      'ywtb.xjtu.edu.cn',
      'ehall.xjtu.edu.cn',
      'workflow.xjtu.edu.cn',
    ];

    void addCookie(
      String host,
      ({String name, String value, String? domain, String? path}) item,
    ) {
      final path = item.path ?? '/';
      final uri = Uri(scheme: 'https', host: host, path: path);
      byHost.putIfAbsent(uri, () => <Cookie>[]).add(
            Cookie(item.name, item.value)
              ..domain = host
              ..path = path
              ..httpOnly = true
              ..secure = true,
          );
    }

    for (final item in cookies) {
      var domain = (item.domain ?? '').trim().replaceFirst(RegExp(r'^\.'), '');
      if (domain.isEmpty) {
        domain = 'login.xjtu.edu.cn';
      }
      // 仅接受交大相关域名（含裸 xjtu.edu.cn / webvpn）。
      if (!domain.endsWith('xjtu.edu.cn')) {
        continue;
      }

      importedNames.add(item.name);
      addCookie(domain, item);

      // 父域 Cookie 在浏览器会发给各子域；Dio CookieJar 按 host 匹配，
      // 因此镜像到登录 / 一网通办 / 大厅，保证后续请求能带上会话。
      if (domain == 'xjtu.edu.cn') {
        for (final host in mirrorHosts) {
          addCookie(host, item);
        }
      }
    }

    for (final entry in byHost.entries) {
      await _jar.saveFromResponse(entry.key, entry.value);
    }

    if (importedNames.isNotEmpty) {
      AppLogger.info('已导入校园 Cookie 名称: ${importedNames.join(', ')}');
    } else {
      AppLogger.warn('importCookies 未写入任何校园域名 Cookie');
    }
  }

  Future<void> ensureWebVpnSession() async {
    if (!useWebVpn) return;
    try {
      await get(CampusUrls.webVpnLogin, rewrite: false);
      AppLogger.info('已尝试建立 WebVPN 会话');
    } on Object {
      AppLogger.warn('WebVPN 会话建立失败，将继续直连并在失败时回退');
    }
  }

  String _resolve(String url) =>
      WebVpnUrl.maybeConvert(url, enabled: useWebVpn);

  /// GET with optional WebVPN rewrite.
  ///
  /// Pass [rewrite]: `false` to hit the original host directly (ignores
  /// [useWebVpn]). Prefer direct for workflow/jwxt when SSO cookies were
  /// imported for those hosts; WebVPN rewrite without webvpn session cookies
  /// drops them and breaks sync.
  Future<Response<dynamic>> get(
    String url, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    ResponseType? responseType,
    bool rewrite = true,
  }) {
    final target = rewrite ? _resolve(url) : url;
    _assertAllowed(target);
    return _dio.get<dynamic>(
      target,
      queryParameters: query,
      options: Options(headers: headers, responseType: responseType),
    );
  }

  /// Direct GET that never rewrites through WebVPN.
  Future<Response<dynamic>> getDirect(
    String url, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    ResponseType? responseType,
  }) =>
      get(
        url,
        query: query,
        headers: headers,
        responseType: responseType,
        rewrite: false,
      );

  Future<Uint8List> getBytes(String url) async {
    final response = await get(url, responseType: ResponseType.bytes);
    final data = response.data;
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    if (data is String) return Uint8List.fromList(utf8.encode(data));
    throw StateError('expected bytes');
  }

  Future<Response<dynamic>> post(
    String url, {
    Object? data,
    Map<String, String>? headers,
    bool jsonBody = false,
    bool rewrite = true,
    ResponseType? responseType,
  }) {
    final target = rewrite ? _resolve(url) : url;
    _assertAllowed(target);
    return _dio.post<dynamic>(
      target,
      data: data,
      options: Options(
        headers: headers,
        responseType: responseType,
        contentType: jsonBody
            ? Headers.jsonContentType
            : Headers.formUrlEncodedContentType,
      ),
    );
  }

  Future<void> saveYwtbIdToken(String token) async {
    ywtbIdToken = token;
    await _store.write(key: 'session.ywtb_id_token', value: token);
  }

  Future<void> clear() async {
    await _jar.deleteAll();
    ywtbIdToken = null;
    AppLogger.info('已清除校园会话 Cookie');
  }

  String responseText(Response<dynamic> response) {
    final data = response.data;
    if (data == null) return '';
    if (data is String) return data;
    if (data is List<int>) return utf8.decode(data, allowMalformed: true);
    return data.toString();
  }

  Map<String, dynamic>? tryJson(Response<dynamic> response) {
    final raw = responseText(response);
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } on Object {
      return null;
    }
    return null;
  }

  void _assertAllowed(String url) {
    final host = Uri.parse(url).host;
    const allowed = {
      'login.xjtu.edu.cn',
      'ehall.xjtu.edu.cn',
      'ywtb.xjtu.edu.cn',
      'jwxt.xjtu.edu.cn',
      'workflow.xjtu.edu.cn',
      'authx-service.xjtu.edu.cn',
      'dean.xjtu.edu.cn',
      'due.xjtu.edu.cn',
      'www.xjtu.edu.cn',
      'org.xjtu.edu.cn',
      'webvpn.xjtu.edu.cn',
    };
    if (!allowed.contains(host)) {
      throw ArgumentError('拒绝访问未列入校园域名白名单的地址: $host');
    }
  }
}
