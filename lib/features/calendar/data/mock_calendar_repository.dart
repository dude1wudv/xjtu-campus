import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../domain/calendar_repository.dart';
import '../domain/school_calendar.dart';
import 'one2020_calendar_mapper.dart';

class MockCalendarRepository implements CalendarRepository {
  @override
  Future<CalendarSnapshot> load({
    DateTime? now,
    int? scheduleWeek,
  }) async {
    final day = now ?? DateTime.now();
    try {
      final termsRaw =
          await rootBundle.loadString('docs/one2020-terms-sample.json');
      final detailRaw =
          await rootBundle.loadString('docs/one2020-term-detail-sample.json');
      final terms = One2020CalendarMapper.termsFromJson(jsonDecode(termsRaw));
      final detail =
          One2020CalendarMapper.detailFromJson(jsonDecode(detailRaw));
      SchoolTermInfo? current = detail.term;
      if (current == null) {
        for (final t in terms) {
          if (t.contains(day)) {
            current = t;
            break;
          }
        }
        current ??= terms.isEmpty ? null : terms.first;
      }
      final week = scheduleWeek ??
          (current?.teachingWeekOf(day) ?? 1);
      return CalendarSnapshot(
        terms: terms,
        currentTerm: current,
        events: detail.events,
        teachingWeek: week,
        live: false,
        banner: AppStrings.mockBanner,
        syncedWithScheduleWeek: scheduleWeek,
      );
    } on Object {
      final term = SchoolTermInfo(
        id: 'demo',
        label: AppStrings.termLabel,
        startDate: DateTime(2026, 9, 7),
        endDate: DateTime(2027, 1, 17),
      );
      return CalendarSnapshot(
        terms: [term],
        currentTerm: term,
        events: const [],
        teachingWeek: scheduleWeek ?? term.teachingWeekOf(day),
        live: false,
        banner: AppStrings.mockBanner,
        syncedWithScheduleWeek: scheduleWeek,
      );
    }
  }
}
