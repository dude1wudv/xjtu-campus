import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../domain/exam_arrangement.dart';
import '../domain/exams_repository.dart';
import 'exams_mapper.dart';

class MockExamsRepository implements ExamsRepository {
  @override
  Future<ExamsSnapshot> load({String? termCode}) async {
    try {
      final raw =
          await rootBundle.loadString('docs/exams-sample-redacted.json');
      final exams = ExamsMapper.fromJson(jsonDecode(raw));
      return ExamsSnapshot(
        exams: exams,
        live: false,
        banner: AppStrings.mockBanner,
        termCode: termCode ?? '2025-2026-2',
      );
    } on Object {
      return ExamsSnapshot(
        exams: const [],
        live: false,
        banner: AppStrings.mockBanner,
        termCode: termCode,
      );
    }
  }
}
