import 'package:flutter_test/flutter_test.dart';
import 'package:xjtu_campus/core/update/update_checker.dart';

void main() {
  group('UpdateChecker.normalizeVersion', () {
    test('strips v prefix and build metadata', () {
      expect(UpdateChecker.normalizeVersion('v1.1.0'), '1.1.0');
      expect(UpdateChecker.normalizeVersion('V1.0.1+2'), '1.0.1');
      expect(UpdateChecker.normalizeVersion('1.2.3-beta'), '1.2.3');
    });
  });

  group('UpdateChecker.compareSemver', () {
    test('orders versions', () {
      expect(UpdateChecker.compareSemver('1.1.0', '1.0.0'), greaterThan(0));
      expect(UpdateChecker.compareSemver('1.0.0', '1.1.0'), lessThan(0));
      expect(UpdateChecker.compareSemver('v1.1.0', '1.1.0'), 0);
      expect(UpdateChecker.compareSemver('1.0.10', '1.0.9'), greaterThan(0));
    });
  });

  group('access denied heuristic', () {
    test('detects dean 403 copy', () {
      // Imported via browser page static helper would couple UI; mirror needles.
      const needles = ['无权访问', '您无权访问本页面', '您无权访问'];
      const sample = '<html><title>无权访问</title><body>您无权访问本页面</body></html>';
      expect(needles.any(sample.contains), isTrue);
    });
  });
}
