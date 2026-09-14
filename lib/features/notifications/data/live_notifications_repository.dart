
import '../../../core/constants/campus_urls.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import '../domain/notice_filter.dart';
import '../domain/notifications_repository.dart';
import '../domain/school_notice.dart';
import 'mock_notifications_repository.dart';

/// 抓取教务处公开「教学通知」列表。
///
/// 站点有公开的浏览器特征校验；应用按学校页面逻辑完成校验后读取列表，
/// 不绕过登录墙，也不抓取未公开内容。
class LiveNotificationsRepository implements NotificationsRepository {
  LiveNotificationsRepository({
    required CampusSession session,
    required MockNotificationsRepository mock,
  }) : _session = session,
       _mock = mock;

  final CampusSession _session;
  final MockNotificationsRepository _mock;

  @override
  Future<List<SchoolNotice>> fetchNotices({NoticeFilterRule? rule}) async {
    return (await load(rule: rule)).notices;
  }

  @override
  Future<NoticesSnapshot> load({NoticeFilterRule? rule}) async {
    try {
      final notices = await _fetchDeanList();
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
          banner: AppStrings.liveFallbackBanner,
        );
      }
      return NoticesSnapshot(
        notices: filtered,
        live: true,
        banner: AppStrings.noticesLiveBanner,
      );
    } on Object catch (e) {
      AppLogger.warn('教务通知抓取失败，回退演示数据: $e');
      final demo = await _mock.fetchNotices(rule: rule);
      return NoticesSnapshot(
        notices: demo,
        live: false,
        banner: AppStrings.liveFallbackBanner,
      );
    }
  }

  Future<List<SchoolNotice>> _fetchDeanList() async {
    // Prefer dean; fall back to due if needed.
    for (final entryUrl in [CampusUrls.deanNotices, CampusUrls.dueNotices]) {
      try {
        await _passPublicChallenge(entryUrl);
        final response = await _session.get(
          entryUrl,
          headers: {'Accept': 'text/html,application/xhtml+xml'},
          rewrite: false,
        );
        final html = response.data?.toString() ?? '';
        if (html.contains('网站正在加载中') || !html.contains('教学通知')) {
          continue;
        }
        final parsed = _parseList(html, base: entryUrl);
        if (parsed.isNotEmpty) return parsed;
      } on Object {
        continue;
      }
    }
    throw StateError('empty notice list');
  }

  Future<void> _passPublicChallenge(String pageUrl) async {
    final origin = Uri.parse(pageUrl).origin;
    final response = await _session.get(
      pageUrl,
      headers: {'Accept': 'text/html'},
      rewrite: false,
    );
    final html = response.data?.toString() ?? '';
    if (!html.contains('dynamic_challenge') && !html.contains('challengeId')) {
      return;
    }

    final challengeId = _match(html, r"challengeId\s*=\s*'([^']+)'");
    final a = int.tryParse(_match(html, r'var a\s*=\s*(\d+);') ?? '');
    final b = int.tryParse(_match(html, r'var b\s*=\s*(\d+);') ?? '');
    final op = _match(html, r"var operator\s*=\s*'([^']+)';");
    if (challengeId == null || a == null || b == null || op == null) {
      return;
    }
    final result = switch (op) {
      '+' => a + b,
      '-' => a - b,
      '*' => a * b,
      _ => a - b,
    };
    final ua = CampusUrls.userAgent;
    final hash = _simpleHash('$challengeId$result${ua.substring(0, 10)}');
    await _session.post(
      '$origin/dynamic_challenge',
      data: {
        'challenge_id': challengeId,
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
      },
      rewrite: false,
    );
  }

  List<SchoolNotice> _parseList(String html, {required String base}) {
    final baseUri = Uri.parse(base);
    final items = <SchoolNotice>[];
    final liRegex = RegExp(r'<li[^>]*>(.*?)</li>', dotAll: true);
    for (final match in liRegex.allMatches(html)) {
      final block = match.group(1)!;
      final hrefMatch = RegExp(r'href="([^"]*info/\d+/\d+\.htm)"').firstMatch(block);
      if (hrefMatch == null) continue;
      final href = hrefMatch.group(1)!;
      final absolute = baseUri.resolve(href).toString();
      final plain = block
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final dateMatch = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(plain);
      if (dateMatch == null) continue;
      final date = DateTime.tryParse(dateMatch.group(1)!);
      if (date == null) continue;
      var title = plain.replaceAll(dateMatch.group(1)!, '').trim();
      String? tag;
      final tagMatch = RegExp(r'^\[([^\]]+)\]').firstMatch(title);
      if (tagMatch != null) {
        tag = tagMatch.group(1);
        title = title.substring(tagMatch.end).trim();
      }
      if (title.isEmpty) continue;
      final category = _categorize(tag, title);
      items.add(
        SchoolNotice(
          id: absolute,
          title: tag == null ? title : '[$tag]$title',
          summary: tag == null ? '教务处教学通知' : '分类：$tag',
          publishedAt: date,
          category: category,
          source: '教务处',
          keywords: [
            if (tag != null) tag,
            ..._keywordsFrom(title),
          ],
          url: absolute,
          live: true,
        ),
      );
    }
    return items;
  }

  NoticeCategory _categorize(String? tag, String title) {
    final hay = '${tag ?? ''}$title';
    if (hay.contains('考试') || hay.contains('补考') || hay.contains('成绩')) {
      return NoticeCategory.exam;
    }
    if (hay.contains('选课') ||
        hay.contains('课程') ||
        hay.contains('课表') ||
        hay.contains('停开') ||
        hay.contains('辅修')) {
      return NoticeCategory.course;
    }
    if (hay.contains('奖') || hay.contains('助学') || hay.contains('资助')) {
      return NoticeCategory.scholarship;
    }
    if (hay.contains('放假') || hay.contains('假期') || hay.contains('调休')) {
      return NoticeCategory.holiday;
    }
    return NoticeCategory.general;
  }

  List<String> _keywordsFrom(String title) {
    const seeds = ['补考', '缓考', '选课', '课表', '转专业', '毕业', '学位', '实习', '考勤'];
    return seeds.where(title.contains).toList();
  }

  static String? _match(String text, String pattern) =>
      RegExp(pattern).firstMatch(text)?.group(1);

  static int _simpleHash(String str) {
    var hash = 0;
    for (final unit in str.codeUnits) {
      hash = ((hash << 5) - hash) + unit;
      hash &= 0xffffffff;
      if (hash >= 0x80000000) hash -= 0x100000000;
    }
    return hash.abs();
  }
}
