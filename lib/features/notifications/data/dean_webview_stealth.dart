/// Hide automation flags before challenge JS runs (`navigator.webdriver`).
abstract final class DeanWebViewStealth {
  static const script = r'''
(function() {
  try {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
  } catch (e) {}
  try {
    Object.defineProperty(Navigator.prototype, 'webdriver', {
      get: () => undefined,
      configurable: true,
    });
  } catch (e) {}
  try { delete window.callPhantom; } catch (e) {}
  try { delete window._phantom; } catch (e) {}
  try { delete window.__nightmare; } catch (e) {}
  try { delete window.phantom; } catch (e) {}
  try { delete window.domAutomation; } catch (e) {}
  try { delete window.domAutomationController; } catch (e) {}
})();
''';
}
