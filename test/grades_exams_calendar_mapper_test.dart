import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:xjtu_campus/features/calendar/data/one2020_calendar_mapper.dart';
import 'package:xjtu_campus/features/exams/data/exams_mapper.dart';
import 'package:xjtu_campus/features/grades/data/grades_mapper.dart';

void main() {
  test('GradesMapper 解析 redact 样例并按学期分组', () {
    final file = File('docs/grades-sample-redacted.json');
    expect(file.existsSync(), isTrue);
    final root = jsonDecode(file.readAsStringSync());
    final snap = GradesMapper.fromJson(root);
    expect(snap.records, hasLength(3));
    expect(snap.records.first.courseName, '线性代数');
    expect(snap.records.first.credit, 3.0);
    expect(snap.records.first.gpaPoints, 4.0);
    expect(snap.records.first.score, '90');
    expect(snap.groupedByTerm.keys.first, '2025-2026-2');
    expect(snap.groupedByTerm['2025-2026-2'], hasLength(2));
    // Fixture must not leak a real student id pattern into assertions logging.
    final raw = file.readAsStringSync();
    expect(raw.contains('REDACTED'), isTrue);
  });

  test('ExamsMapper 解析 redact 样例并排序', () {
    final file = File('docs/exams-sample-redacted.json');
    final exams = ExamsMapper.fromJson(jsonDecode(file.readAsStringSync()));
    expect(exams, hasLength(2));
    expect(exams.first.courseName, '线性代数');
    expect(exams.first.date, '2026-06-20');
    expect(exams.first.timeLabel, '08:30-10:30');
    expect(exams.first.location, '主楼A-203');
    expect(exams.first.dateTimeLabel, contains('2026-06-20'));
  });

  test('One2020CalendarMapper 解析学期与重要日期', () {
    final terms = One2020CalendarMapper.termsFromJson(
      jsonDecode(File('docs/one2020-terms-sample.json').readAsStringSync()),
    );
    expect(terms, hasLength(2));
    expect(terms.first.label, contains('2026-2027'));
    final detail = One2020CalendarMapper.detailFromJson(
      jsonDecode(
        File('docs/one2020-term-detail-sample.json').readAsStringSync(),
      ),
    );
    expect(detail.term, isNotNull);
    expect(detail.events, isNotEmpty);
    expect(detail.events.first.name, '开学');
    final week = detail.term!.teachingWeekOf(DateTime(2026, 9, 14));
    expect(week, greaterThanOrEqualTo(1));
  });
}
