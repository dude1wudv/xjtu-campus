import 'grade_record.dart';

/// Aggregates over grade rows (credit-weighted GPA).
abstract final class GradeStats {
  /// Credit-weighted GPA: Σ(gpaPoints × credits) / Σ(credits).
  /// Skips rows with null [GradeRecord.gpaPoints] or non-positive credits.
  /// Returns null when no eligible rows.
  static double? weightedGpa(List<GradeRecord> records) {
    var weighted = 0.0;
    var credits = 0.0;
    for (final r in records) {
      final gpa = r.gpaPoints;
      if (gpa == null) continue;
      if (r.credit <= 0) continue;
      weighted += gpa * r.credit;
      credits += r.credit;
    }
    if (credits <= 0) return null;
    return weighted / credits;
  }

  /// Sum of credits for rows that contribute to [weightedGpa].
  static double countedCredits(List<GradeRecord> records) {
    var credits = 0.0;
    for (final r in records) {
      if (r.gpaPoints == null) continue;
      if (r.credit <= 0) continue;
      credits += r.credit;
    }
    return credits;
  }
}
