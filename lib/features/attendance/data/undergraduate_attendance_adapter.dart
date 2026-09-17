import 'package:dio/dio.dart';

import '../../../core/network/campus_session.dart';
import '../../../core/network/webvpn_url.dart';
import '../domain/attendance_record.dart';
import 'attendance_diagnostics.dart';
import 'attendance_repository.dart';

/// Adapter for the undergraduate attendance service under `/sa`.
///
/// The route and field names below were read from the public application
/// chunks `app.125a71c1.js`, `chunk-56370065.ad35f9fc.js`, and
/// `chunk-80db7750.23aa550b.js`. The login response itself is not treated as verified;
/// [verifySession] checks the authenticated terminal before the UI closes.
class UndergraduateAttendanceAdapter {
  UndergraduateAttendanceAdapter(this.session, this.cancelToken);

  static const _origin = 'https://bk-kq.xjtu.edu.cn';
  static const _basePath = '/sa';
  static const _pageSize = 50;
  static const _maxPages = 100;

  final CampusSession session;
  final CancelToken cancelToken;
  Future<bool>? _webVpnFuture;

  Future<AttendanceSnapshot> load() async {
    await session.restore();
    _ensureActive();
    final token = await _readToken();
    if (token == null) throw const AttendanceAuthRequired();

    final home = _asMap(await _requestData(
      method: 'GET',
      path: '/student/home',
      token: token,
    ));
    if (home == null) throw const AttendanceProtocolChanged();
    final semester = _asMap(home['semester']);
    if (semester == null) throw const AttendanceProtocolChanged();
    final termName = _requiredText(semester, 'semesterName');
    final startDate = _semesterDate(semester, 'startDate');
    final endDate = _semesterDate(semester, 'endDate');
    if (startDate.compareTo(endDate) > 0) {
      throw const FormatException('本科生考勤学期日期范围无效');
    }

    final records = <AttendanceRecord>[];
    final seenIds = <String>{};
    var page = 1;
    var total = 0;
    while (true) {
      _ensureActive();
      if (page > _maxPages) {
        throw const FormatException('本科生考勤分页超过安全上限');
      }
      final pageData = _asMap(await _requestData(
        method: 'POST',
        path: '/student/pc/attendance-records/page',
        token: token,
        body: {
          'pageNum': page,
          'pageSize': _pageSize,
          'data': {'startDate': startDate, 'endDate': endDate},
        },
      ));
      if (pageData == null) throw const AttendanceProtocolChanged();

      final rows = pageData['rows'];
      final pageTotal = _strictInteger(pageData['total']);
      final returnedPage = pageData['pageNum'] == null
          ? null
          : _strictInteger(pageData['pageNum']);
      final returnedSize = pageData['pageSize'] == null
          ? null
          : _strictInteger(pageData['pageSize']);
      if (rows is! List || pageTotal == null || pageTotal < 0 ||
          (pageData['pageNum'] != null &&
              (returnedPage == null || returnedPage < 1)) ||
          (pageData['pageSize'] != null &&
              (returnedSize == null || returnedSize < 1))) {
        throw const AttendanceProtocolChanged();
      }
      if (returnedPage != null && returnedPage != page) {
        throw const FormatException('本科生考勤分页页码不一致');
      }
      if (returnedSize != null && rows.length > returnedSize) {
        throw const FormatException('本科生考勤分页返回数量异常');
      }
      if (page == 1) {
        total = pageTotal;
      } else if (pageTotal != total) {
        throw const FormatException('本科生考勤分页总数不一致');
      }

      for (final row in rows) {
        if (row is! Map) throw const AttendanceProtocolChanged();
        final record = AttendanceRecord.fromUndergraduateResponse(
          Map<String, dynamic>.from(row),
        );
        if (!seenIds.add(record.id)) {
          throw const FormatException('本科生考勤分页出现重复记录');
        }
        records.add(record);
        if (records.length > total) {
          throw const FormatException('本科生考勤分页超过总数');
        }
      }

      if (records.length == total) {
        return AttendanceSnapshot(
          records: records..sort((a, b) => b.date.compareTo(a.date)),
          term: termName,
          updatedAt: DateTime.now(),
        );
      }
      if (rows.isEmpty) {
        throw const FormatException('本科生考勤分页提前截断');
      }
      page++;
    }
  }

  /// Verify the token's authenticated terminal before considering login done.
  Future<void> verifySession() async {
    await session.restore();
    _ensureActive();
    final token = await _readToken();
    if (token == null) throw const AttendanceAuthRequired();
    final data = _asMap(await _requestData(
      method: 'GET',
      path: '/sso/current-user',
      token: token,
    ));
    if (data == null || !data.containsKey('terminal')) {
      throw const AttendanceProtocolChanged();
    }
    if ('${data['terminal']}'.trim().toUpperCase() != 'STUDENT') {
      await session.clearUndergraduateAttendanceToken();
      throw const AttendanceAuthRequired();
    }
  }

  Future<String?> _readToken() async {
    final value = await session.readUndergraduateAttendanceToken();
    final token = value?.trim();
    return token == null || token.isEmpty ? null : token;
  }

  Future<Object?> _requestData({
    required String method,
    required String path,
    required String token,
    Map<String, dynamic>? body,
  }) async {
    _ensureActive();
    final rawUrl = '$_origin$_basePath$path';
    final actualUrl = WebVpnUrl.maybeConvert(
      rawUrl,
      enabled: await (_webVpnFuture ??= session.undergraduateAttendanceUsesWebVpn()),
    );
    final actualUri = Uri.parse(actualUrl);
    final headers = await _headers(actualUri, token);
    AttendanceDiagnostics.add(
      actualUrl == rawUrl ? 'api-request-direct' : 'api-request-vpn',
      url: actualUrl,
      method: method,
    );

    Response<dynamic> response;
    try {
      response = method == 'GET'
          ? await session.get(
              actualUrl,
              rewrite: false,
              cancelToken: cancelToken,
              headers: headers,
              followRedirects: false,
              validateStatus: (status) => status != null,
            )
          : await session.post(
              actualUrl,
              rewrite: false,
              cancelToken: cancelToken,
              data: body,
              jsonBody: true,
              headers: headers,
              followRedirects: false,
              validateStatus: (status) => status != null,
            );
    } on DioException catch (error) {
      _ensureActive();
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) await _throwAuth();
      if (status == 404 || status == 405) {
        throw const AttendanceProtocolChanged();
      }
      if (status != null && status >= 400) {
        throw const AttendanceRequestFailed();
      }
      // Keep cancellation/timeout/network details typed for the provider's
      // fixed diagnostic classification; never include their text in UI.
      rethrow;
    }

    _ensureActive();
    final decoded = _responseMap(response);
    AttendanceDiagnostics.add(
      'api-response',
      url: response.realUri.toString(),
      method: method,
      status: response.statusCode,
      response: decoded ?? response.data,
    );
    final status = response.statusCode ?? 0;
    if (status >= 300 && status < 400) {
      final location = response.headers.value('location');
      final target = location == null
          ? null
          : _redirectTarget(response.realUri, location);
      if (target != null && _isKnownLoginHost(target)) await _throwAuth();
      throw const AttendanceProtocolChanged();
    }
    if (status == 401 || status == 403) await _throwAuth();
    if (status == 404 || status == 405) {
      throw const AttendanceProtocolChanged();
    }
    if (status >= 400) throw const AttendanceRequestFailed();
    if (AttendanceConnectionFailed.isGatewayError(session.responseText(response))) {
      throw const AttendanceConnectionFailed();
    }
    if (decoded == null) throw const AttendanceProtocolChanged();

    final code = decoded['code'];
    if (decoded.containsKey('code') && !_isSuccessCode(code)) {
      if (_isAuthCode(code)) await _throwAuth();
      throw const AttendanceRequestFailed();
    }
    if (!decoded.containsKey('data')) {
      throw const AttendanceProtocolChanged();
    }
    return decoded['data'];
  }

  Future<Map<String, String>> _headers(Uri actualUri, String token) async {
    final headers = <String, String>{
      'X-System': 'WEB',
      'X-Business-Token': token,
      'Accept': 'application/json',
      'Origin': '${actualUri.scheme}://${actualUri.authority}',
      'Referer': WebVpnUrl.maybeConvert(
        '$_origin/studentpc/workbench',
        enabled: WebVpnUrl.isWebVpn(actualUri.toString()),
      ),
    };
    try {
      final cookies = await session.jar.loadForRequest(actualUri);
      for (final cookie in cookies) {
        if (cookie.name.toUpperCase() == 'TOKEN-AUTH' && cookie.value.isNotEmpty) {
          headers['TOKEN-AUTH'] = cookie.value;
          break;
        }
      }
    } on Object {
      // TOKEN-AUTH is optional; Dio's CookieManager still sends session
      // cookies from the shared jar when the cookie lookup is unavailable.
    }
    return headers;
  }

  Future<Never> _throwAuth() async {
    await session.clearUndergraduateAttendanceToken();
    throw const AttendanceAuthRequired();
  }

  void _ensureActive() {
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;
  }

  Map<String, dynamic>? _responseMap(Response<dynamic> response) {
    final data = response.data;
    if (data is Map) return _asMap(data);
    return session.tryJson(response);
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.fromEntries(
      value.entries.map((entry) => MapEntry('${entry.key}', entry.value)),
    );
  }

  String _requiredText(Map<String, dynamic> map, String key) {
    final value = map[key];
    final text = value is String ? value.trim() : '';
    if (text.isEmpty) throw const AttendanceProtocolChanged();
    return text;
  }

  String _semesterDate(Map<String, dynamic> semester, String key) {
    if (!semester.containsKey(key)) throw const AttendanceProtocolChanged();
    final raw = semester[key];
    final text = raw is String ? raw.trim() : '';
    final parsed = _parseDate(text);
    if (text.isEmpty || parsed == null) {
      throw const FormatException('本科生考勤学期日期无法解析');
    }
    return '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
  }

  DateTime? _parseDate(String text) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|[T ])').firstMatch(text);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime.tryParse(text);
    return parsed != null && parsed.year == year && parsed.month == month &&
            parsed.day == day
        ? parsed
        : null;
  }

  int? _strictInteger(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    if (value is String && RegExp(r'^\d+$').hasMatch(value.trim())) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  bool _isSuccessCode(Object? value) => value == 0 ||
      value == 200 || value.toString() == '0' || value.toString() == '200';

  bool _isAuthCode(Object? value) => value == 401 || value == 403 ||
      value.toString() == '401' || value.toString() == '403';

  bool _isKnownLoginHost(Uri uri) => WebVpnUrl.isLoginPage(uri) ||
      (['kq.xjtu.edu.cn', 'bk-kq.xjtu.edu.cn'].any(
        (host) => WebVpnUrl.matchesHost(uri, host)) &&
        (uri.path.contains('/cas/') || uri.path.contains('/sa/auth/cas/') ||
          uri.path.endsWith('/studentpc/student/entry')));

  Uri? _redirectTarget(Uri base, String location) {
    try {
      return base.resolve(location);
    } on FormatException {
      return null;
    }
  }
}
