import '../domain/school_notice.dart';

/// Parses dean/due 「教学通知」list HTML (Visual SiteBuilder + live jxtz2).
abstract final class DeanNoticeParser {
  static final _hrefRegex = RegExp(
    r'''href\s*=\s*["']([^"']*(?:info/\d+/\d+\.html?|content\.jsp\?[^"']*wbnewsid=\d+))["']''',
    caseSensitive: false,
  );

  static final _lineItemRegex = RegExp(
    r'<li[^>]*id="line_u[^"]*"[^>]*>(.*?)</li>',
    caseSensitive: false,
    dotAll: true,
  );

  static final _liRegex = RegExp(
    r'<li[^>]*>(.*?)</li>',
    caseSensitive: false,
    dotAll: true,
  );

  static bool looksLikeNoticeList(String html) =>
      html.contains('教学通知') ||
      html.contains('line_u') ||
      html.contains('wbnewsid=') ||
      RegExp(r'info/\d+/\d+\.htm').hasMatch(html);

  static List<SchoolNotice> parse(String html, {required String base}) {
    final decoded = html.replaceAll('&amp;', '&');
    final baseUri = Uri.parse(base);
    var blocks = _lineItemRegex
        .allMatches(decoded)
        .map((match) => match.group(1)!)
        .toList();
    if (blocks.isEmpty) {
      blocks = _liRegex
          .allMatches(decoded)
          .map((match) => match.group(1)!)
          .toList();
    }
    if (blocks.isEmpty) blocks = [decoded];

    final items = <SchoolNotice>[];
    final seen = <String>{};
    for (final block in blocks) {
      final hrefMatch = _hrefRegex.firstMatch(block);
      if (hrefMatch == null) continue;
      final href = hrefMatch.group(1)!.replaceAll('&amp;', '&').trim();
      final absolute = baseUri.resolve(href).toString();
      if (!seen.add(absolute)) continue;

      final parsed = _titleTagDate(block);
      if (parsed.title.isEmpty) continue;

      final category = categorize(parsed.tag, parsed.title);
      items.add(
        SchoolNotice(
          id: absolute,
          title: parsed.tag == null ? parsed.title : '[${parsed.tag}]${parsed.title}',
          summary: parsed.tag == null ? '教务处教学通知' : '分类：${parsed.tag}',
          publishedAt: parsed.date ?? DateTime.now(),
          category: category,
          source: '教务处',
          keywords: [
            ?parsed.tag,
            ...keywordsFrom(parsed.title),
          ],
          url: absolute,
          live: true,
        ),
      );
    }
    return items;
  }

  static ({String title, String? tag, DateTime? date}) _titleTagDate(String block) {
    final anchor = RegExp(
      r'<a\b[^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(block);
    var inner = anchor?.group(1) ?? block;
    String? tag;
    final italic = RegExp(
      r'<i\b[^>]*>(.*?)</i>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(inner);
    if (italic != null) {
      tag = _plain(italic.group(1)!).replaceAll(RegExp(r'[\[\]【】]'), '').trim();
      if (tag.isEmpty) tag = null;
      inner = inner.replaceFirst(italic.group(0)!, ' ');
    }

    var title = _plain(inner);
    final span = RegExp(
      r'<span\b[^>]*>(.*?)</span>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(block);
    DateTime? date = _parseDate(_plain(span?.group(1) ?? ''));
    date ??= _parseDate(title);

    if (date != null) {
      title = title.replaceAll(RegExp(r'\d{4}[-/.]\d{1,2}[-/.]\d{1,2}'), '').trim();
    }
    title = title.replaceAll(RegExp(r'^(更多|More)\s*', caseSensitive: false), '').trim();

    if (tag == null) {
      final bracket = RegExp(r'^\[([^\]]+)\]').firstMatch(title);
      if (bracket != null) {
        tag = bracket.group(1);
        title = title.substring(bracket.end).trim();
      }
    }
    if (tag == null) {
      final full = RegExp(r'^【([^】]+)】').firstMatch(title);
      if (full != null) {
        tag = full.group(1);
        title = title.substring(full.end).trim();
      }
    }
    return (title: title, tag: tag, date: date);
  }

  static String _plain(String raw) => raw
      .replaceAll(RegExp(r'&nbsp;', caseSensitive: false), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'&#\d+;'), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static DateTime? _parseDate(String text) {
    final match = RegExp(r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(text);
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  static NoticeCategory categorize(String? tag, String title) {
    final hay = '${tag ?? ''}$title';
    if (hay.contains('考试') || hay.contains('补考') || hay.contains('成绩')) {
      return NoticeCategory.exam;
    }
    if (hay.contains('选课') ||
        hay.contains('课程') ||
        hay.contains('课表') ||
        hay.contains('停开') ||
        hay.contains('辅修') ||
        hay.contains('微专业') ||
        hay.contains('培养方案')) {
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

  static List<String> keywordsFrom(String title) {
    const seeds = ['补考', '缓考', '选课', '课表', '转专业', '毕业', '学位', '实习', '考勤', '辅修'];
    return seeds.where(title.contains).toList();
  }
}
