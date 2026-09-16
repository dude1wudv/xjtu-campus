import 'package:cookie_jar/cookie_jar.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import '../../../core/network/imported_campus_cookie.dart';
import '../domain/notice_filter.dart';
import '../domain/notifications_repository.dart';
import '../domain/school_notice.dart';
import 'dean_notices_parser.dart';
import 'dean_public_challenge.dart';
import 'mock_notifications_repository.dart';

/// 抓取教务处公开「教学通知」列表。
///
/// 主路径由 NotificationsPage 内嵌 InAppWebView 完成（页面 JS 过校验）。
/// 本仓库在 WebView 失败后作为二次路径：Dio + 本地 challenge，再不行回退演示数据。
class LiveNotificationsRepository implements NotificationsRepository {
  LiveNotificationsRepository({
    required CampusSession session,
    required MockNotificationsRepository mock,
    // Public names for DI; fields stay private.
  })  : _session = session, // ignore: prefer_initializing_formals
        _mock = mock; // ignore: prefer_initializing_formals

  final CampusSession _session;
  final MockNotificationsRepository _mock;

  @override
  Future<List<SchoolNotice>> fetchNotices({NoticeFilterRule? rule}) async {
    return (await load(rule: rule)).notices;
  }

  @override
  Future<NoticesSnapshot> load({NoticeFilterRule? rule}) async {
    try {
      final notices = await _fetchDeanListViaDio();
      final filtered = notices.where((n) => rule?.matches(n) ?? true).toList()
        ..sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          return b.publishedAt.compareTo(a.publishedAt);
        });
      if (filtered.isEmpty) {
        final demo = await _mock.fetchNotices(rule: rule);
        return NoticesSnapshot(
          notices: demo,
          live: false,
          banner: AppStrings.noticesChallengeFailedBanner,
        );
      }
      return NoticesSnapshot(
        notices: filtered,
        live: true,
        banner: AppStrings.noticesLiveBanner,
      );
    } on Object catch (e) {
      AppLogger.warn('教务通知 Dio 抓取失败，回退演示数据: $e');
      final demo = await _mock.fetchNotices(rule: rule);
      return NoticesSnapshot(
        notices: demo,
        live: false,
        banner: AppStrings.noticesChallengeFailedBanner,
      );
    }
  }

  Future<List<SchoolNotice>> _fetchDeanListViaDio() async {
    for (final entryUrl in [CampusUrls.deanNotices, CampusUrls.dueNotices]) {
      try {
        final parsed = await _fetchOneViaDio(entryUrl);
        if (parsed.isNotEmpty) {
          AppLogger.info('Dio 教务通知成功（${parsed.length} 条）');
          return parsed;
        }
      } on Object catch (error) {
        AppLogger.warn('Dio 教务通知失败 ($entryUrl): $error');
      }
    }
    throw StateError('empty notice list');
  }

  Future<List<SchoolNotice>> _fetchOneViaDio(String entryUrl) async {
    var html = await _getHtml(entryUrl);
    if (DeanPublicChallenge.looksLikeChallenge(html)) {
      final passed = await _passPublicChallenge(entryUrl, html);
      if (!passed) return const [];
      html = await _getHtml(entryUrl);
      if (DeanPublicChallenge.looksLikeChallenge(html)) {
        AppLogger.warn('教务通知仍为挑战页，重试一次 challenge');
        final retried = await _passPublicChallenge(entryUrl, html);
        if (!retried) return const [];
        html = await _getHtml(entryUrl);
      }
    }
    if (DeanPublicChallenge.looksLikeChallenge(html) ||
        !DeanNoticeParser.looksLikeNoticeList(html)) {
      return const [];
    }
    return DeanNoticeParser.parse(html, base: entryUrl);
  }

  Future<String> _getHtml(String url) async {
    final response = await _session.get(
      url,
      headers: {
        'Accept': 'text/html,application/xhtml+xml',
        'User-Agent': CampusUrls.userAgent,
      },
      rewrite: false,
    );
    return _session.responseText(response);
  }

  /// Solve challenge from [freshHtml], POST `/dynamic_challenge`, then import
  /// `client_id` into the CampusSession cookie jar (browser sets it via JS).
  Future<bool> _passPublicChallenge(String pageUrl, String freshHtml) async {
    final origin = Uri.parse(pageUrl).origin;
    final host = Uri.parse(pageUrl).host;
    final parsed = DeanPublicChallenge.parseChallenge(freshHtml);
    if (parsed == null) {
      AppLogger.warn('教务挑战页字段不完整');
      return false;
    }
    final result = DeanPublicChallenge.computeAnswer(
      parsed.a,
      parsed.b,
      parsed.op,
    );
    final ua = CampusUrls.userAgent;
    final hash = DeanPublicChallenge.hashFor(
      challengeId: parsed.challengeId,
      answer: result,
      userAgent: ua,
    );
    final response = await _session.post(
      '$origin/dynamic_challenge',
      data: {
        'challenge_id': parsed.challengeId,
        'answer': result,
        'browser_info': {
          'userAgent': ua,
          'language': 'zh-CN',
          'platform': 'Win32',
          'screen': {'width': 1280, 'height': 800, 'colorDepth': 24},
          'timezoneOffset': -480,
          'hasTouchEvents': false,
        },
        'hash': hash,
      },
      jsonBody: true,
      headers: {
        'Accept': 'application/json',
        'Origin': origin,
        'Referer': pageUrl,
        'User-Agent': ua,
      },
      rewrite: false,
    );
    final raw = _session.responseText(response);
    final clientId = DeanPublicChallenge.clientIdFromResponse(raw);
    if (clientId == null) {
      AppLogger.warn(
        'dynamic_challenge 未返回 client_id（前 120 字: ${_preview(raw)}）',
      );
      return false;
    }

    await _session.importCookies([
      ImportedCampusCookie(
        name: 'client_id',
        value: clientId,
        domain: host,
        path: '/',
        scheme: 'https',
        secure: true,
      ),
    ]);
    await _session.jar.saveFromResponse(
      Uri.parse('$origin/'),
      [
        Cookie('client_id', clientId)
          ..path = '/'
          ..httpOnly = false
          ..secure = true,
      ],
    );
    AppLogger.info('已写入 $host client_id Cookie path=/');
    return true;
  }

  static String _preview(String raw) {
    final oneLine = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= 120) return oneLine;
    return '${oneLine.substring(0, 120)}…';
  }
}
