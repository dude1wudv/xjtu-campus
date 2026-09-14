import 'dean_webview_stealth.dart';

/// Legacy Headless path — device WebView prefers the embedded loader in
/// NotificationsPage. Kept for stealth-script unit tests / reference.
class DeanWebViewNoticesFetcher {
  /// Hide automation flags before challenge JS runs (`navigator.webdriver`).
  static const stealthScript = DeanWebViewStealth.script;
}
