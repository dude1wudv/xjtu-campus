import 'package:flutter_test/flutter_test.dart';
import 'package:xjtu_campus/features/grades/domain/grade_record.dart';
import 'package:xjtu_campus/features/grades/domain/grade_stats.dart';

void main() {
  GradeRecord row({
    required String name,
    required double credit,
    double? gpa,
    String term = '2025-2026-2',
  }) {
    return GradeRecord(
      termCode: term,
      courseName: name,
      credit: credit,
      gpaPoints: gpa,
      score: '90',
    );
  }

  test('weightedGpa = Σ(gpa×credits)/Σ(credits)', () {
    final records = [
      row(name: 'A', credit: 3.0, gpa: 4.0),
      row(name: 'B', credit: 1.5, gpa: 3.7),
      row(name: 'C', credit: 2.0, gpa: 4.3),
    ];
    // (4*3 + 3.7*1.5 + 4.3*2) / (3+1.5+2) = (12 + 5.55 + 8.6) / 6.5 = 26.15/6.5
    final gpa = GradeStats.weightedGpa(records);
    expect(gpa, isNotNull);
    expect(gpa!, closeTo(26.15 / 6.5, 1e-9));
    expect(GradeStats.countedCredits(records), closeTo(6.5, 1e-9));
  });

  test('skips null gpaPoints and non-positive credits', () {
    final records = [
      row(name: 'ok', credit: 2.0, gpa: 4.0),
      row(name: 'noGpa', credit: 3.0, gpa: null),
      row(name: 'zeroCredit', credit: 0, gpa: 3.0),
    ];
    expect(GradeStats.weightedGpa(records), closeTo(4.0, 1e-9));
    expect(GradeStats.countedCredits(records), closeTo(2.0, 1e-9));
  });

  test('empty or all-skipped returns null', () {
    expect(GradeStats.weightedGpa(const []), isNull);
    expect(
      GradeStats.weightedGpa([
        row(name: 'x', credit: 1, gpa: null),
      ]),
      isNull,
    );
  });
}
