import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/network/campus_session.dart';
import '../../../core/network/webview_cookie_bridge.dart';
import '../../../core/network/webvpn_url.dart';
import '../domain/homework.dart';

/// Read-only LMS protocol integration; see XJTUToolBox/lms/lms.py.
/// Only summaries are warmed. Descriptions and submission counts are lazy.
class HomeworkRepository {
  HomeworkRepository(this.session);
  static const origin = 'https://lms.xjtu.edu.cn';
  final CampusSession session;
  final _cancel = CancelToken();
  void cancel() => _cancel.cancel('Homework sync stopped');

  Future<Map<String, dynamic>> _json(String path, {bool post = false}) async {
    final response = post
        ? await session.post('$origin$path', cancelToken: _cancel)
        : await session.get('$origin$path', cancelToken: _cancel);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const HomeworkAuthRequired();
    }
    final data = session.tryJson(response);
    if (data == null) {
      final target = response.realUri;
      if (WebVpnUrl.isLoginPage(target) || '${response.data}'.contains('<html')) {
        throw const HomeworkAuthRequired();
      }
      throw const FormatException('思源学堂返回格式变化');
    }
    return data;
  }

  Future<HomeworkSnapshot> load() async {
    await session.restore();
    Map<String, dynamic> courses;
    try {
      courses = await _json('/api/my-courses', post: true);
    } on HomeworkAuthRequired {
      await _login();
      courses = await _json('/api/my-courses', post: true);
    }
    final list = courses['courses'];
    if (list is! List) throw const FormatException('无法读取思源学堂课程列表');
    final items = <int, Homework>{};
    var failures = 0;
    // Sequential requests inside the shared queue avoid flooding the school.
    for (final raw in list) {
      if (_cancel.isCancelled) throw _cancel.cancelError!;
      if (raw is! Map) { failures++; continue; }
      final courseId = int.tryParse('${raw['id']}');
      if (courseId == null) { failures++; continue; }
      // Past courses remain available on the official site. Startup only warms
      // active courses; do not discard a course whose end date is absent.
      final end = homeworkDate(raw['end_date']);
      if (end != null && end.isBefore(DateTime.now().subtract(const Duration(days: 14)))) continue;
      try {
        final data = await _json('/api/courses/$courseId/activities');
        final activities = data['activities'];
        if (activities is! List) throw const FormatException('作业列表格式变化');
        for (final activity in activities) {
          if (activity is! Map) throw const FormatException('作业格式变化');
          if (activity['type'] != 'homework' || activity['published'] == false) continue;
          final id = int.tryParse('${activity['id']}');
          if (id == null || activity['title'] is! String) {
            throw const FormatException('作业信息不完整');
          }
          items[id] = Homework(id: id, courseId: courseId,
            courseName: '${raw['name'] ?? '未命名课程'}', title: activity['title'] as String,
            dueAt: homeworkDate(activity['end_time']), group: activity['submit_by_group'] == true);
        }
      } on HomeworkAuthRequired {
        rethrow;
      } catch (_) {
        if (_cancel.isCancelled) rethrow;
        failures++;
      }
    }
    if (items.isEmpty && failures > 0) throw StateError('课程作业未能同步，请稍后重试');
    final sorted = items.values.toList()..sort((a, b) {
      if (a.dueAt == null) return b.dueAt == null ? a.id.compareTo(b.id) : 1;
      if (b.dueAt == null) return -1;
      return a.dueAt!.compareTo(b.dueAt!);
    });
    return HomeworkSnapshot(sorted, DateTime.now(), failedCourses: failures);
  }

  Future<HomeworkDetail> detail(int id) async {
    final data = await _json('/api/activities/$id');
    if (data['type'] != 'homework' || int.tryParse('${data['id']}') != id) {
      throw const FormatException('无法读取该作业详情');
    }
    final count = int.tryParse('${data['user_submit_count']}');
    // A personal count does not establish a whole group's submission state.
    final status = data['submit_by_group'] == true || count == null || count < 0
        ? HomeworkStatus.unknown
        : count > 0 ? HomeworkStatus.submitted : HomeworkStatus.pending;
    final body = data['data'];
    final description = body is Map ? '${body['description'] ?? ''}' : '';
    // Render a plain-text preview, never execute school-supplied HTML.
    final text = description
        .replaceAll(RegExp(r'<(script|style)\b[^>]*>[\s\S]*?</\1>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<br\s*/?>|</(?:p|div|li|h[1-6])>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ').replaceAll('&lt;', '<').replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"').replaceAll('&#39;', "'").replaceAll('&amp;', '&')
        .trim();
    final uploads = data['uploads'];
    return HomeworkDetail(text, status,
      uploads is List ? uploads.whereType<Map>().map((u) => '${u['name'] ?? '附件'}').toList() : []);
  }

  Future<void> _login() async {
    final ready = Completer<bool>();
    HeadlessInAppWebView? browser;
    _cancel.whenCancel.then((_) {
      if (!ready.isCompleted) ready.complete(false);
    });
    // Attach the timeout/error handler before callbacks can complete the future.
    final completed = ready.future.timeout(const Duration(seconds: 35), onTimeout: () => false);
    try {
      await WebViewCookieBridge.seedOrigins(session: session,
        origins: [CampusUrls.casLogin, session.resolveUrl(origin)]);
      if (_cancel.isCancelled) throw _cancel.cancelError!;
      browser = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(session.resolveUrl(origin))),
        initialSettings: InAppWebViewSettings(javaScriptEnabled: true,
          domStorageEnabled: true, thirdPartyCookiesEnabled: true, userAgent: CampusUrls.userAgent),
        onLoadStop: (controller, url) async {
          if (ready.isCompleted || url == null) return;
          final uri = Uri.parse(url.toString());
          if (!WebVpnUrl.matchesHost(uri, 'lms.xjtu.edu.cn')) return;
          try {
            final signedIn = await controller.evaluateJavascript(
              source: 'typeof globalData !== "undefined" && !!globalData.user && !!globalData.user.id');
            if (signedIn == true && !ready.isCompleted) ready.complete(true);
          } catch (_) { /* Keep waiting for the final redirect. */ }
        },
      );
      await browser.run();
      final signedIn = await completed;
      if (_cancel.isCancelled) throw _cancel.cancelError!;
      if (!signedIn) throw const HomeworkAuthRequired();
      await WebViewCookieBridge.importOrigins(session: session,
        origins: [origin, '$origin/user/index', '$origin/api/my-courses']);
    } on TimeoutException {
      throw const HomeworkAuthRequired();
    } finally {
      if (!ready.isCompleted) ready.complete(true);
      try { await browser?.dispose(); } catch (_) { /* Best effort. */ }
    }
  }
}
