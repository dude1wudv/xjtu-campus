import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../constants/app_constants.dart';
import '../constants/campus_urls.dart';
import '../logging/app_logger.dart';
import '../storage/credential_store.dart';
import 'imported_campus_cookie.dart';
import 'secure_cookie_storage.dart';
import 'webvpn_url.dart';
import 'campus_read_queue.dart';

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
  final readQueue = CampusReadQueue();
  late final PersistCookieJar _jar;
  late final Dio _dio;

  Dio get dio => _dio;
  CookieJar get jar => _jar;

  String? ywtbIdToken;
  bool useWebVpn = false;

  Future<void>? _restoreFuture;

  Future<void> restore() => _restoreFuture ??= _restore();

  Future<void> _restore() async {
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
    await restore();
    try {
      final origins = [
        CampusUrls.casLogin,
        CampusUrls.ywtbMain,
        CampusUrls.ehallHome,
        CampusUrls.jwxtHome,
        CampusUrls.workflowKebiaoPage,
        CampusUrls.ncardPlat,
        CampusUrls.webVpn,
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
  ///
  /// 默认按 `https://host` 写入。图书馆座位等 cleartext 主机需保留 scheme+port：
  /// `http://rg.lib.xjtu.edu.cn:8086` 不会带上仅存于 https jar 槽位且 `secure` 的 Cookie。
  /// 对 `*.lib.xjtu.edu.cn` 会额外镜像 http:8086 / http:8010（及 https）变体。
  Future<void> importCookies(Iterable<ImportedCampusCookie> cookies) async {
    final byHost = <Uri, List<Cookie>>{};
    final importedNames = <String>{};
    const mirrorHosts = [
      'login.xjtu.edu.cn',
      'ywtb.xjtu.edu.cn',
      'ehall.xjtu.edu.cn',
      'workflow.xjtu.edu.cn',
      'jwxt.xjtu.edu.cn',
      'ncard.xjtu.edu.cn',
    ];

    bool isLibHost(String host) =>
        host == 'lib.xjtu.edu.cn' || host.endsWith('.lib.xjtu.edu.cn');

    void addCookie(
      String host,
      ImportedCampusCookie item, {
      required String scheme,
      int? port,
      required bool secure,
    }) {
      final path = item.path ?? '/';
      final uri = (port != null && port > 0)
          ? Uri(scheme: scheme, host: host, port: port, path: path)
          : Uri(scheme: scheme, host: host, path: path);
      byHost.putIfAbsent(uri, () => <Cookie>[]).add(
            Cookie(item.name, item.value)
              ..domain = host
              ..path = path
              ..httpOnly = true
              ..secure = secure,
          );
    }

    void addForHost(String host, ImportedCampusCookie item) {
      final knownScheme = (item.scheme ?? '').trim().toLowerCase();
      final knownPort = item.port;
      final lib = isLibHost(host);
      // Lib seats are cleartext; never mark Secure or Dio won't send on :8086
      // once cookie_jar enforces the flag. Domain-keyed saves share one slot.
      final preferHttp = lib ||
          knownScheme == 'http' ||
          (knownPort != null && (knownPort == 8086 || knownPort == 8010));

      if (preferHttp) {
        final port = (knownPort == 8086 || knownPort == 8010)
            ? knownPort
            : (lib ? 8086 : knownPort);
        addCookie(
          host,
          item,
          scheme: 'http',
          port: port ?? (lib ? 8086 : null),
          secure: false,
        );
      } else {
        addCookie(
          host,
          item,
          scheme: 'https',
          secure: item.secure ?? true,
        );
      }

      // Library seats talk cleartext :8086/:8010; always mirror both schemes.
      if (lib) {
        for (final port in const [8086, 8010]) {
          addCookie(host, item, scheme: 'http', port: port, secure: false);
        }
        addCookie(host, item, scheme: 'https', secure: false);
      }
    }

    for (final item in cookies) {
      var domain = (item.domain ?? '').trim().replaceFirst(RegExp(r'^\.'), '');
      if (domain.isEmpty) {
        domain = 'login.xjtu.edu.cn';
      }
      // 仅接受交大相关域名（含裸 xjtu.edu.cn / webvpn）。
      if (domain != 'xjtu.edu.cn' && !domain.endsWith('.xjtu.edu.cn')) {
        continue;
      }

      importedNames.add(item.name);
      addForHost(domain, item);

      // 父域 Cookie 在浏览器会发给各子域；Dio CookieJar 按 host 匹配，
      // 因此镜像到登录 / 一网通办 / 大厅，保证后续请求能带上会话。
      if (domain == 'xjtu.edu.cn') {
        for (final host in mirrorHosts) {
          addForHost(host, item);
        }
      }
      // www.lib / lib portal cookies must also hit rg.lib:8086 seat API.
      if (isLibHost(domain) && domain != 'rg.lib.xjtu.edu.cn') {
        addForHost('rg.lib.xjtu.edu.cn', item);
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

  /// WebVPN authentication is interactive. Never repeatedly warm its login
  /// endpoint from every service request; that can restart an active session.
  Future<void> ensureWebVpnSession() async {
    await restore();
  }

  String resolveUrl(String url) =>
      WebVpnUrl.maybeConvert(url, enabled: useWebVpn);

  Map<String, String>? _resolveHeaders(Map<String, String>? headers, bool rewrite) {
    if (headers == null || !rewrite || !useWebVpn) return headers;
    return headers.map((key, value) {
      final name = key.toLowerCase();
      if (name == 'referer') return MapEntry(key, resolveUrl(value));
      if (name == 'origin' && WebVpnUrl.isCampusUrl(value)) {
        return MapEntry(key, WebVpnUrl.base);
      }
      return MapEntry(key, value);
    });
  }

  /// GET with optional WebVPN rewrite.
  ///
  /// Pass [rewrite]: `false` to hit the original host directly (ignores
  /// [useWebVpn]). Campus services should use the default so a verified
  /// WebVPN session is shared consistently across native and WebView paths.
  ///
  /// Optional [followRedirects] / [maxRedirects] / [validateStatus] override
  /// [BaseOptions] for callers that need a manual redirect walk (e.g. ncard
  /// CAS ticket capture). Other callers are unchanged when left null.
  Future<Response<dynamic>> get(
    String url, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
    Map<String, String>? headers,
    ResponseType? responseType,
    bool rewrite = true,
    bool? followRedirects,
    int? maxRedirects,
    ValidateStatus? validateStatus,
  }) {
    final target = rewrite ? resolveUrl(url) : url;
    _assertAllowed(target);
    return _dio.get<dynamic>(
      target,
      queryParameters: query,
      cancelToken: cancelToken,
      options: Options(
        headers: _resolveHeaders(headers, rewrite),
        responseType: responseType,
        followRedirects: followRedirects,
        maxRedirects: maxRedirects,
        validateStatus: validateStatus,
      ),
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
    CancelToken? cancelToken,
    bool? followRedirects,
    ValidateStatus? validateStatus,
  }) {
    final target = rewrite ? resolveUrl(url) : url;
    _assertAllowed(target);
    return _dio.post<dynamic>(
      target,
      data: data,
      cancelToken: cancelToken,
      options: Options(
        headers: _resolveHeaders(headers, rewrite),
        responseType: responseType,
        followRedirects: followRedirects,
        validateStatus: validateStatus,
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

  static const ncardAccessTokenKey = 'ncard.access_token';

  Future<void> saveNcardAccessToken(String token) async {
    await _store.write(key: ncardAccessTokenKey, value: token);
  }

  Future<String?> readNcardAccessToken() => _store.read(ncardAccessTokenKey);

  Future<void> clearNcardAccessToken() async {
    await _store.delete(ncardAccessTokenKey);
  }

  Future<void> saveAttendanceToken(String host, String token) =>
      _store.write(key: 'attendance.token.$host', value: token);

  Future<String?> readAttendanceToken(String host) => _store.read('attendance.token.$host');

  Future<void> clearAttendanceToken(String host) => _store.delete('attendance.token.$host');

  // The /sa undergraduate service uses X-Business-Token, not Synjones-Auth.
  Future<void> saveUndergraduateAttendanceToken(String token) =>
      _store.write(key: 'attendance.business_token.bk-kq.xjtu.edu.cn', value: token);

  Future<String?> readUndergraduateAttendanceToken() =>
      _store.read('attendance.business_token.bk-kq.xjtu.edu.cn');

  Future<void> clearUndergraduateAttendanceToken() =>
      _store.delete('attendance.business_token.bk-kq.xjtu.edu.cn');

  Future<bool> undergraduateAttendanceUsesWebVpn() async =>
      await _store.read('attendance.undergraduate.webvpn') == '1';

  Future<void> setUndergraduateAttendanceWebVpn(bool enabled) =>
      _store.write(key: 'attendance.undergraduate.webvpn', value: enabled ? '1' : '0');

  Future<void> clear() async {
    await _jar.deleteAll();
    ywtbIdToken = null;
    await _store.delete('session.ywtb_id_token');
    await clearNcardAccessToken();
    await clearAttendanceToken('bkkq.xjtu.edu.cn');
    await clearAttendanceToken('bk-kq.xjtu.edu.cn');
    await clearUndergraduateAttendanceToken();
    await clearAttendanceToken('yjskq.xjtu.edu.cn');
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
      'one2020.xjtu.edu.cn',
      'ncard.xjtu.edu.cn',
      'www.lib.xjtu.edu.cn',
      'rg.lib.xjtu.edu.cn',
      'lib.xjtu.edu.cn',
      'bkkq.xjtu.edu.cn',
      'bk-kq.xjtu.edu.cn',
      'kq.xjtu.edu.cn',
      'yjskq.xjtu.edu.cn',
      'lms.xjtu.edu.cn',
    };
    if (!allowed.contains(host)) {
      throw ArgumentError('拒绝访问未列入校园域名白名单的地址: $host');
    }
  }
}
