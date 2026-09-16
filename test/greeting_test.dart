import 'package:flutter_test/flutter_test.dart';
import 'package:xjtu_campus/features/home/domain/greeting.dart';

void main() {
  group('greetingForHour', () {
    test('0–4 → 夜深了', () {
      expect(greetingForHour(0), '夜深了');
      expect(greetingForHour(4), '夜深了');
    });

    test('5–10 → 早上好', () {
      expect(greetingForHour(5), '早上好');
      expect(greetingForHour(10), '早上好');
    });

    test('11–13 → 中午好', () {
      expect(greetingForHour(11), '中午好');
      expect(greetingForHour(13), '中午好');
    });

    test('14–18 → 下午好', () {
      expect(greetingForHour(14), '下午好');
      expect(greetingForHour(18), '下午好');
    });

    test('19–23 → 晚上好', () {
      expect(greetingForHour(19), '晚上好');
      expect(greetingForHour(23), '晚上好');
    });

    test('00:57 (hour 0) is 夜深了 not 早上好', () {
      expect(greetingForHour(0), isNot('早上好'));
      expect(greetingForHour(0), '夜深了');
    });
  });
}
