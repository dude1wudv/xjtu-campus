import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:dio/dio.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/network/campus_session.dart';
import '../../../core/network/webview_cookie_bridge.dart';
import '../../../core/network/webvpn_url.dart';
import '../domain/attendance_record.dart';

enum AttendanceSystem {
  undergraduate('本科生', 'bkkq.xjtu.edu.cn', '1372'),
  postgraduate('研究生', 'yjskq.xjtu.edu.cn', '1245');
  const AttendanceSystem(this.label, this.host, this.appId);
  final String label, host, appId;
  String get origin => 'https://$host';
  String get loginUrl => Uri.https('org.xjtu.edu.cn', '/openplatform/oauth/authorize', {
    'appId': appId,
    'redirectUri': '$origin/berserker-auth/auth/attendance-pc/casReturn',
    'responseType': 'code', 'scope': 'user_info', 'state': '1234',
  }).toString();
}

/// Read-only integration with the school's attendance-student API.
/// Protocol reference: XJTUToolBox attendance/attendance.py (endpoints and fields).
/// Attendance status is read from classWaterBean, never inferred from swipes.
class AttendanceRepository {
  AttendanceRepository(this.session);
  final CampusSession session;
  final _cancelToken = CancelToken();

  void cancel() => _cancelToken.cancel('Attendance sync stopped');

  Future<AttendanceSnapshot> load(AttendanceSystem system) async {
    final timer = Timer(const Duration(seconds: 90), cancel);
    try {
      return await _load(system);
    } finally {
      timer.cancel();
    }
  }

  Future<AttendanceSnapshot> _load(AttendanceSystem system) async {
    await session.restore();
    var token = await session.readAttendanceToken(system.host);
    for (var attempt = 0; attempt < 2; attempt++) {
      token ??= await _browserToken(system);
      if (token == null) throw const AttendanceAuthRequired();
      try {
        final term = await _post(system, token, '/global/getNearTerm', const {});
        if (term is! Map || term['bh'] == null || term['startdate'] == null) {
          throw const FormatException('考勤学期信息格式变化');
        }
        final start = '${term['startdate']}'.split(' ').first;
        final end = DateTime.now().toIso8601String().split('T').first;
        final records = <String, AttendanceRecord>{};
        for (var page = 1; page <= 100; page++) {
          final data = await _post(system, token, '/classWater/getClassWaterPage', {
            'startDate': start, 'endDate': end, 'current': page, 'pageSize': 100,
            'timeCondition': '', 'subjectBean': {'sCode': ''},
            'classWaterBean': {'status': ''}, 'classBean': {'termNo': term['bh']},
          });
          if (data is! Map || data['list'] is! List) {
            throw const FormatException('考勤明细格式变化');
          }
          final rows = data['list'] as List;
          final before = records.length;
          for (final row in rows) {
            if (row is! Map) throw const FormatException('考勤记录格式变化');
            final record = AttendanceRecord.fromResponse(Map<String, dynamic>.from(row));
            records[record.id] = record;
          }
          final total = int.tryParse('${data['totalCount']}');
          if (rows.isEmpty || (total != null && records.length >= total) ||
              (total == null && rows.length < 100)) {
            return AttendanceSnapshot(
              records: records.values.toList()..sort((a, b) => b.date.compareTo(a.date)),
              term: '${term['name'] ?? ''}', updatedAt: DateTime.now(),
            );
          }
          if (records.length == before || page == 100) {
            throw const FormatException('考勤分页未完整返回，请稍后重试');
          }
        }
      } on _AttendanceAuthExpired {
        await session.clearAttendanceToken(system.host);
        token = null;
      }
    }
    throw const AttendanceAuthRequired();
  }

  Future<Object?> _post(AttendanceSystem system, String token,
      String path, Map<String, dynamic> body) async {
    final response = await session.post('${system.origin}/attendance-student$path',
      data: body, jsonBody: true, cancelToken: _cancelToken,
      headers: {'Synjones-Auth': 'bearer $token', 'Referer': '${system.origin}/',
        'Accept': 'application/json'},
    );
    final json = session.tryJson(response);
    if (response.statusCode == 401 || response.statusCode == 403 || json == null ||
        '${json['code']}' == '401' || '${json['code']}' == '403') {
      throw const _AttendanceAuthExpired();
    }
    if (json['success'] != true) throw StateError('学校考勤接口暂未返回有效数据，请稍后重试');
    return json['data'];
  }

  Future<String?> _browserToken(AttendanceSystem system) async {
    if (_cancelToken.isCancelled) throw _cancelToken.cancelError!;
    final result = Completer<String?>();
    _cancelToken.whenCancel.then((_) {
      if (!result.isCompleted) result.complete(null);
    });
    HeadlessInAppWebView? browser;
    final entry = session.useWebVpn
        ? WebVpnUrl.convert('http://${system.host}/') : system.loginUrl;
    try {
      await WebViewCookieBridge.seedOrigins(session: session,
        origins: {
          CampusUrls.casLogin,
          entry,
          system.loginUrl,
          session.resolveUrl(system.loginUrl),
          session.resolveUrl(system.origin),
        });
      void capture(WebUri? url) {
        if (url == null || result.isCompleted) return;
        final uri = Uri.parse(url.toString());
        if (!WebVpnUrl.matchesHost(uri, system.host)) return;
        final token = tokenFromUri(uri);
        if (token != null) result.complete(token);
      }
      browser = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(entry)),
        initialSettings: InAppWebViewSettings(javaScriptEnabled: true,
          domStorageEnabled: true, thirdPartyCookiesEnabled: true,
          userAgent: CampusUrls.userAgent),
        onLoadStart: (_, url) => capture(url),
        onLoadStop: (_, url) => capture(url),
        onUpdateVisitedHistory: (_, url, _) => capture(url),
        onReceivedError: (_, request, _) {
          if (request.isForMainFrame == true && !result.isCompleted) result.complete(null);
        },
      );
      if (_cancelToken.isCancelled) throw _cancelToken.cancelError!;
      await browser.run();
      final token = await result.future.timeout(const Duration(seconds: 40), onTimeout: () => null);
      if (_cancelToken.isCancelled) throw _cancelToken.cancelError!;
      if (token != null) {
        // The login redirects also establish service cookies. The HTTP client
        // must receive these before it starts calling the attendance API.
        await WebViewCookieBridge.importOrigins(session: session, origins: {
          entry,
          system.origin,
          system.loginUrl,
          session.resolveUrl('${system.origin}/attendance-student/'),
        });
        await session.saveAttendanceToken(system.host, token);
      }
      return token;
    } catch (_) {
      if (_cancelToken.isCancelled) throw _cancelToken.cancelError!;
      rethrow;
    } finally {
      try { await browser?.dispose(); } catch (_) { /* Best-effort WebView teardown. */ }
    }
  }

  static String? tokenFromUri(Uri uri) {
    final direct = uri.queryParameters['token'];
    if (direct != null && direct.isNotEmpty) return direct;
    final fragment = Uri.tryParse('https://local/${uri.fragment}');
    final value = fragment?.queryParameters['token'];
    return value == null || value.isEmpty ? null : value;
  }
}

class _AttendanceAuthExpired implements Exception {
  const _AttendanceAuthExpired();
}

class AttendanceAuthRequired implements Exception {
  const AttendanceAuthRequired();

  @override
  String toString() => '请打开官方考勤系统完成认证';
}
