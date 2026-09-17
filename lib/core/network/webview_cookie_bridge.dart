import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../logging/app_logger.dart';
import 'campus_session.dart';
import 'imported_campus_cookie.dart';

/// Export WebView cookies into [CampusSession], preserving each origin's
/// scheme + port (needed for `http://rg.lib.xjtu.edu.cn:8086`).
class WebViewCookieBridge {
  WebViewCookieBridge._();

  static const libraryOrigins = [
    'https://www.lib.xjtu.edu.cn/',
    'http://www.lib.xjtu.edu.cn/',
    'http://rg.lib.xjtu.edu.cn:8086/',
    'http://rg.lib.xjtu.edu.cn:8086/seat/',
    'http://rg.lib.xjtu.edu.cn:8010/',
    'http://rg.lib.xjtu.edu.cn:8010/seat/',
  ];

  /// Restore encrypted HTTP cookies into the shared mobile WebView cookie jar.
  static Future<void> seedOrigins({
    required CampusSession session,
    required Iterable<String> origins,
  }) async {
    await session.restore();
    final manager = CookieManager.instance();
    for (final origin in origins) {
      final uri = Uri.parse(origin);
      final cookies = await session.jar.loadForRequest(uri);
      for (final cookie in cookies) {
        await manager.setCookie(
          url: WebUri(origin),
          name: cookie.name,
          value: cookie.value,
          domain: cookie.domain,
          path: cookie.path ?? '/',
          isSecure: cookie.secure,
          isHttpOnly: cookie.httpOnly,
        );
      }
    }
  }

  /// Pull cookies for [origins] (or [url] alone) and import into [session].
  static Future<int> importOrigins({
    required CampusSession session,
    required Iterable<String> origins,
  }) async {
    final mapped = await collectOrigins({...origins, ...origins.map(session.resolveUrl)});
    if (mapped.isEmpty) return 0;
    await session.importCookies(mapped);
    return mapped.length;
  }

  static Future<List<ImportedCampusCookie>> collectOrigins(Iterable<String> origins) async {
    final manager = CookieManager.instance();
    final mapped = <ImportedCampusCookie>[];
    final seen = <String>{};

    for (final origin in origins) {
      final uri = Uri.tryParse(origin);
      if (uri == null || uri.host.isEmpty) continue;
      List<Cookie> cookies;
      try {
        cookies = await manager.getCookies(url: WebUri(origin));
      } on Object catch (error) {
        AppLogger.warn('WebViewCookieBridge getCookies($origin) 失败: $error');
        continue;
      }
      for (final c in cookies) {
        final domain = (c.domain ?? uri.host).trim();
        final key = '$domain|${c.name}|${c.value}|${uri.scheme}|${uri.port}';
        if (!seen.add(key)) continue;
        mapped.add(
          ImportedCampusCookie(
            name: c.name,
            value: c.value.toString(),
            domain: domain,
            path: c.path ?? '/',
            scheme: uri.scheme.isEmpty ? null : uri.scheme,
            port: uri.hasPort ? uri.port : null,
            secure: c.isSecure,
          ),
        );
      }
    }

    return mapped;
  }

  /// Convenience for library seat / portal pages.
  static Future<int> importLibraryCookies(CampusSession session) =>
      importOrigins(session: session, origins: libraryOrigins);
}
