import 'dart:convert';

/// Browser-feature challenge used by dean/due public notice pages.
///
/// JS: `hash = ((hash<<5)-hash)+char; hash = hash & hash;` then `Math.abs(hash)`.
/// Dart ints are arbitrary-precision, so we mimic JS 32-bit signed via
/// `hash & 0xffffffff` then convert to signed before [abs].
abstract final class DeanPublicChallenge {
  /// Same algorithm as the dean page `simpleHash`.
  static int simpleHash(String str) {
    var hash = 0;
    for (final unit in str.codeUnits) {
      hash = ((hash << 5) - hash) + unit;
      hash &= 0xffffffff;
      if (hash >= 0x80000000) {
        hash -= 0x100000000;
      }
    }
    return hash.abs();
  }

  static bool looksLikeChallenge(String html) =>
      html.contains('dynamic_challenge') ||
      html.contains('challengeId') ||
      html.contains('网站正在加载中');

  static bool looksLikeNoticeList(String html) =>
      html.contains('教学通知') ||
      html.contains('line_u') ||
      html.contains('wbnewsid=') ||
      RegExp(r'info/\d+/\d+\.htm').hasMatch(html);

  /// Parse challenge fields from the interstitial HTML. Returns null if incomplete.
  static ({String challengeId, int a, int b, String op})? parseChallenge(
    String html,
  ) {
    final challengeId = _match(html, r"challengeId\s*=\s*'([^']+)'");
    final a = int.tryParse(_match(html, r'var a\s*=\s*(-?\d+);') ?? '');
    final b = int.tryParse(_match(html, r'var b\s*=\s*(-?\d+);') ?? '');
    final op = _match(html, r"var operator\s*=\s*'([^']+)'");
    if (challengeId == null || a == null || b == null || op == null) {
      return null;
    }
    return (challengeId: challengeId, a: a, b: b, op: op);
  }

  static int computeAnswer(int a, int b, String op) => switch (op) {
        '+' => a + b,
        '-' => a - b,
        '*' => a * b,
        _ => a - b,
      };

  static int hashFor({
    required String challengeId,
    required int answer,
    required String userAgent,
  }) {
    final prefix =
        userAgent.length >= 10 ? userAgent.substring(0, 10) : userAgent;
    return simpleHash('$challengeId$answer$prefix');
  }

  /// Extract `client_id` from a successful `/dynamic_challenge` JSON body.
  static String? clientIdFromResponse(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final success = decoded['success'];
      if (success != true && success != 'true') return null;
      final id = decoded['client_id']?.toString();
      if (id == null || id.isEmpty) return null;
      return id;
    } on Object {
      return null;
    }
  }

  static String? _match(String text, String pattern) =>
      RegExp(pattern).firstMatch(text)?.group(1);
}
