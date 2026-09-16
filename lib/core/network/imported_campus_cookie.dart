/// Cookie payload imported from WebView / CAS into [CampusSession].
///
/// Prefer filling [scheme]/[port] when the WebView origin is known so cleartext
/// library hosts (e.g. `http://rg.lib.xjtu.edu.cn:8086`) are stored correctly.
class ImportedCampusCookie {
  const ImportedCampusCookie({
    required this.name,
    required this.value,
    this.domain,
    this.path,
    this.scheme,
    this.port,
    this.secure,
  });

  final String name;
  final String value;
  final String? domain;
  final String? path;

  /// `http` / `https` when known from the export origin.
  final String? scheme;

  /// Non-default port when known (e.g. 8086 / 8010 for rg.lib).
  final int? port;

  /// When null, derived from [scheme] (`https` → secure).
  final bool? secure;
}
