import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../constants/campus_urls.dart';
import '../logging/app_logger.dart';
import '../storage/credential_store.dart';
import 'secure_cookie_storage.dart';

/// 带 Cookie 的校园 HTTP 客户端。仅允许学校域名。
class CampusSession {
  CampusSession(this._store) {
    _jar = PersistCookieJar(
      persistSession: true,
      ignoreExpires: false,
      storage: SecureCookieStorage(_store),
    );
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        maxRedirects: 8,
        validateStatus: (status) => status != null && status < 500,
        headers: {
          'User-Agent': CampusUrls.userAgent,
          'Accept-Language': 'zh-CN,zh;q=0.9',
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

  Future<void> restore() async {
    try {
      await _jar.forceInit().timeout(const Duration(seconds: 3));
      ywtbIdToken = await _store.read('session.ywtb_id_token');
    } on Object {
      AppLogger.warn('校园 Cookie 恢复失败，将以未登录会话继续');
    }
  }

  Future<bool> hasCasCookie() async {
    try {
      final cookies = await _jar.loadForRequest(Uri.parse(CampusUrls.casLogin));
      return cookies.any((cookie) => cookie.name.toUpperCase().contains('TGC'));
    } on Object {
      return false;
    }
  }

  Future<Response<dynamic>> get(
    String url, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    ResponseType? responseType,
  }) {
    _assertAllowed(url);
    return _dio.get<dynamic>(
      url,
      queryParameters: query,
      options: Options(headers: headers, responseType: responseType),
    );
  }

  Future<Uint8List> getBytes(String url) async {
    final response = await get(url, responseType: ResponseType.bytes);
    final data = response.data;
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    throw StateError('expected bytes');
  }

  Future<Response<dynamic>> post(
    String url, {
    Object? data,
    Map<String, String>? headers,
    bool jsonBody = false,
  }) {
    _assertAllowed(url);
    return _dio.post<dynamic>(
      url,
      data: data,
      options: Options(
        headers: headers,
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

  Map<String, dynamic>? tryJson(Response<dynamic> response) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } on Object {
        return null;
      }
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
      'authx-service.xjtu.edu.cn',
      'dean.xjtu.edu.cn',
      'www.xjtu.edu.cn',
      'org.xjtu.edu.cn',
    };
    if (!allowed.contains(host)) {
      throw ArgumentError('拒绝访问未列入校园域名白名单的地址');
    }
  }
}
