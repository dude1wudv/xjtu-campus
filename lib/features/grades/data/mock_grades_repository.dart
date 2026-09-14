import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../domain/grade_record.dart';
import '../domain/grades_repository.dart';
import 'grades_mapper.dart';

class MockGradesRepository implements GradesRepository {
  @override
  Future<GradesSnapshot> load() async {
    try {
      final raw = await rootBundle.loadString(
        'docs/grades-sample-redacted.json',
      );
      final snap = GradesMapper.fromJson(jsonDecode(raw));
      return GradesSnapshot(
        records: snap.records,
        live: false,
        banner: AppStrings.mockBanner,
        groupedByTerm: snap.groupedByTerm,
      );
    } on Object {
      final demo = [
        const GradeRecord(
          termCode: '2025-2026-2',
          courseName: '线性代数（演示）',
          credit: 3,
          gpaPoints: 4.0,
          score: '90',
          courseNature: '必修',
        ),
      ];
      return GradesSnapshot(
        records: demo,
        live: false,
        banner: AppStrings.mockBanner,
        groupedByTerm: GradesMapper.groupByTerm(demo),
      );
    }
  }
}
