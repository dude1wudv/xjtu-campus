import 'dart:convert';

import '../domain/school_calendar.dart';

abstract final class One2020CalendarMapper {
  static List<SchoolTermInfo> termsFromJson(Object? root) {
    final list = _dataList(root);
    final out = <SchoolTermInfo>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final m = raw.map((k, v) => MapEntry(k.toString(), v));
      final start = _date(m['start_date']);
      final end = _date(m['end_date']);
      if (start == null || end == null) continue;
      out.add(
        SchoolTermInfo(
          id: (m['id']?.toString() ?? '').trim(),
          label: (m['term_num']?.toString() ?? '').trim(),
          yearLabel: m['year_num']?.toString(),
          startDate: start,
          endDate: end,
        ),
      );
    }
    return out;
  }

  static ({SchoolTermInfo? term, List<CalendarEvent> events}) detailFromJson(
    Object? root,
  ) {
    if (root is! Map) {
      return (term: null, events: const []);
    }
    final m = root.map((k, v) => MapEntry(k.toString(), v));
    // Some APIs wrap in {code,data}; accept both.
    final body = m['data'] is Map
        ? (m['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : m;
    final start = _date(body['start_date']);
    final end = _date(body['end_date']);
    SchoolTermInfo? term;
    if (start != null && end != null) {
      term = SchoolTermInfo(
        id: (body['id']?.toString() ?? '').trim(),
        label: (body['term_num']?.toString() ?? '').trim(),
        yearLabel: body['year_num']?.toString(),
        startDate: start,
        endDate: end,
      );
    }
    final holidays = body['holidays'];
    final events = <CalendarEvent>[];
    if (holidays is List) {
      for (final raw in holidays) {
        if (raw is! Map) continue;
        final h = raw.map((k, v) => MapEntry(k.toString(), v));
        final hs = _date(h['start_date']);
        final he = _date(h['end_date']) ?? hs;
        final name = (h['holiday_name']?.toString() ?? '').trim();
        if (hs == null || name.isEmpty) continue;
        events.add(
          CalendarEvent(
            name: name,
            startDate: hs,
            endDate: he!,
            remark: (h['holiday_remark']?.toString() ?? '').trim(),
          ),
        );
      }
    }
    events.sort((a, b) => a.startDate.compareTo(b.startDate));
    return (term: term, events: events);
  }

  /// Best-effort parse of showCalendar.htm (embedded JSON / date pairs).
  static List<SchoolTermInfo> termsFromHtml(String html) {
    final dataMatch = RegExp(
      r'"data"\s*:\s*(\[[\s\S]*?\])\s*[,}]',
      multiLine: true,
    ).firstMatch(html);
    if (dataMatch != null) {
      try {
        final slice = dataMatch.group(1)!;
        if (slice.contains('start_date') || slice.contains('term_num')) {
          final decoded = jsonDecode(slice);
          if (decoded is List) {
            final terms = termsFromJson({'code': 200, 'data': decoded});
            if (terms.isNotEmpty) return terms;
          }
        }
      } on Object {
        // fall through
      }
    }

    final dates = RegExp(r'(20\d{2}-\d{2}-\d{2})')
        .allMatches(html)
        .map((m) => DateTime.tryParse(m.group(1)!))
        .whereType<DateTime>()
        .toList();
    if (dates.length >= 2) {
      final start = dates.first;
      var end = start;
      for (final d in dates.skip(1)) {
        if (d.isAfter(start)) {
          end = d;
          break;
        }
      }
      if (!end.isAfter(start)) {
        end = start.add(const Duration(days: 120));
      }
      return [
        SchoolTermInfo(
          id: 'scraped',
          label: '${start.year}校历',
          startDate: start,
          endDate: end,
        ),
      ];
    }
    return const [];
  }

  static List<dynamic> _dataList(Object? root) {
    if (root is! Map) return const [];
    final data = root['data'];
    if (data is List) return data;
    return const [];
  }

  static DateTime? _date(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim().split(' ').first;
    return DateTime.tryParse(s);
  }
}
