/// Spoof mobile browser signals so ncard H5 does not show
/// 「请浏览器调成移动端模式访问！」.
abstract final class NcardMobileStealth {
  /// iPhone Safari–like UA (also set on the WebView itself).
  static const userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) '
      'Version/17.0 Mobile/15E148 Safari/604.1';

  static const script = r'''
(function() {
  var ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
  try {
    Object.defineProperty(navigator, 'userAgent', { get: function() { return ua; }, configurable: true });
  } catch (e) {}
  try {
    Object.defineProperty(navigator, 'vendor', { get: function() { return 'Apple Computer, Inc.'; }, configurable: true });
  } catch (e) {}
  try {
    Object.defineProperty(navigator, 'platform', { get: function() { return 'iPhone'; }, configurable: true });
  } catch (e) {}
  try {
    Object.defineProperty(navigator, 'maxTouchPoints', { get: function() { return 5; }, configurable: true });
  } catch (e) {}
  try {
    if (!('ontouchstart' in window)) {
      window.ontouchstart = null;
    }
  } catch (e) {}
  try {
    var origMatchMedia = window.matchMedia.bind(window);
    window.matchMedia = function(query) {
      try {
        if (typeof query === 'string' && query.indexOf('(pointer:coarse)') !== -1) {
          return { matches: true, media: query, onchange: null,
            addListener: function() {}, removeListener: function() {},
            addEventListener: function() {}, removeEventListener: function() {},
            dispatchEvent: function() { return false; } };
        }
      } catch (e) {}
      return origMatchMedia(query);
    };
  } catch (e) {}
})();
''';

  /// Click「确认」on the mobile-mode dialog if present.
  static const dismissMobileDialogScript = r'''
(function() {
  try {
    var nodes = document.querySelectorAll('button, a, div, span, .van-button, .van-dialog__confirm');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var text = (el.innerText || el.textContent || '').trim();
      if (!text) continue;
      if (text.indexOf('确认') !== -1 || text === '确定' || text === 'OK') {
        var root = el.closest ? (el.closest('.van-dialog') || el.closest('[class*="dialog"]') || el.parentElement) : null;
        var hay = ((root && (root.innerText || root.textContent)) || document.body.innerText || '');
        if (hay.indexOf('移动端') !== -1 || hay.indexOf('手机') !== -1 || text.indexOf('确认') !== -1) {
          el.click();
          return true;
        }
      }
    }
    // van-dialog confirm by class
    var confirm = document.querySelector('.van-dialog__confirm, .van-button--primary');
    if (confirm) {
      var dlg = confirm.closest('.van-dialog') || document.body;
      var t = (dlg.innerText || dlg.textContent || '');
      if (t.indexOf('移动端') !== -1) {
        confirm.click();
        return true;
      }
    }
  } catch (e) {}
  return false;
})();
''';
}
