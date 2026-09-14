/// Time-of-day greeting for the home hero.
///
/// Ranges (local hour 0–23):
/// - 0–4 → 夜深了
/// - 5–10 → 早上好
/// - 11–13 → 中午好
/// - 14–18 → 下午好
/// - 19–23 → 晚上好
String greetingForHour(int hour) {
  assert(hour >= 0 && hour <= 23, 'hour must be 0–23, got $hour');
  if (hour <= 4) return '夜深了';
  if (hour <= 10) return '早上好';
  if (hour <= 13) return '中午好';
  if (hour <= 18) return '下午好';
  return '晚上好';
}
