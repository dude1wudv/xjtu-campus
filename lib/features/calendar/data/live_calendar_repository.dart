import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import '../domain/calendar_repository.dart';
import '../domain/school_calendar.dart';
import 'mock_calendar_repository.dart';
import 'one2020_calendar_mapper.dart';

/// Prefer public one2020 校历 JSON; fall back to bundled sample + schedule week.
class LiveCalendarRepository implements CalendarRepository {
  LiveCalendarRepository({
    required this._session,
    required this._mock,
    Dio? dio,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 25),
                headers: {
                  'User-Agent': CampusUrls.userAgent,
                  'Accept': 'application/json, text/javascript, */*; q=0.01',
                },
                validateStatus: (s) => s != null && s < 500,
              ),
            );

  final CampusSession _session;
  final MockCalendarRepository _mock;
  final Dio _dio;

  @override
  Future<CalendarSnapshot> load({
    DateTime? now,
    int? scheduleWeek,
  }) async {
    final day = now ?? DateTime.now();
    try {
      final live = await _fetchOne2020(day, scheduleWeek);
      if (live != null) return live;
    } on Object catch (error) {
      AppLogger.warn('one2020 校历失败，回退本地样例: $error');
    }

    // Optional: derive term start from jwxt when logged in.
    try {
      final fromJwxt = await _fromJwxtTerm(day, scheduleWeek);
      if (fromJwxt != null) return fromJwxt;
    } on Object catch (error) {
      AppLogger.warn('jwxt 学期起止回退失败: $error');
    }

    final demo = await _mock.load(now: day, scheduleWeek: scheduleWeek);
    return CalendarSnapshot(
      terms: demo.terms,
      currentTerm: demo.currentTerm,
      events: demo.events,
      teachingWeek: scheduleWeek ?? demo.teachingWeek,
      live: false,
      banner: AppStrings.calendarPublicFallbackBanner,
      syncedWithScheduleWeek: scheduleWeek,
    );
  }

  Future<CalendarSnapshot?> _fetchOne2020(
    DateTime day,
    int? scheduleWeek,
  ) async {
    // Warm session cookie (optional).
    try {
      await _dio.get(CampusUrls.one2020CalendarPage);
    } on Object {
      // ignore
    }

    final termsResp = await _dio.post(
      CampusUrls.one2020Terms,
      data: '',
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': CampusUrls.one2020CalendarPage,
        },
      ),
    );
    final termsJson = _asMap(termsResp.data);
    if (termsJson == null) return null;
    final terms = One2020CalendarMapper.termsFromJson(termsJson);
    if (terms.isEmpty) {
      AppLogger.info('one2020 terms.htm 返回空列表');
      return null;
    }

    SchoolTermInfo? current;
    for (final t in terms) {
      if (t.contains(day)) {
        current = t;
        break;
      }
    }
    current ??= terms.isEmpty ? null : terms.first;

    var events = <CalendarEvent>[];
    if (current != null && current.id.isNotEmpty) {
      try {
        final detailResp = await _dio.post(
          CampusUrls.one2020TermById,
          data: {'id': current.id},
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {
              'X-Requested-With': 'XMLHttpRequest',
              'Referer': CampusUrls.one2020CalendarPage,
            },
          ),
        );
        final detail = One2020CalendarMapper.detailFromJson(
          _asMap(detailResp.data) ?? detailResp.data,
        );
        if (detail.term != null) current = detail.term;
        events = detail.events;
      } on Object catch (error) {
        AppLogger.warn('one2020 queryTermById 失败: $error');
      }
    }

    final week = scheduleWeek ?? current?.teachingWeekOf(day) ?? 1;
    AppLogger.info(
      '校历路径成功: one2020（${terms.length} 学期, ${events.length} 事件）',
    );
    return CalendarSnapshot(
      terms: terms,
      currentTerm: current,
      events: events,
      teachingWeek: week,
      live: true,
      banner: AppStrings.calendarLiveBanner,
      syncedWithScheduleWeek: scheduleWeek,
    );
  }

  Future<CalendarSnapshot?> _fromJwxtTerm(
    DateTime day,
    int? scheduleWeek,
  ) async {
    var loggedIn = false;
    try {
      loggedIn = await _session.hasCasCookie();
    } on Object {
      loggedIn = false;
    }
    if (!loggedIn) return null;

    final termJson = _session.tryJson(
      await _session.post(
        CampusUrls.jwxtCurrentTerm,
        rewrite: false,
        headers: {
          'Accept': 'application/json, text/javascript, */*; q=0.01',
        },
      ),
    );
    final termCode =
        termJson?['datas']?['dqxnxq']?['rows']?[0]?['DM']?.toString();
    if (termCode == null || termCode.isEmpty) return null;

    final parts = termCode.split('-');
    if (parts.length < 3) return null;
    final startJson = _session.tryJson(
      await _session.post(
        CampusUrls.jwxtTermStart,
        rewrite: false,
        data: {'XN': '${parts[0]}-${parts[1]}', 'XQ': parts[2]},
        headers: {
          'Accept': 'application/json, text/javascript, */*; q=0.01',
        },
      ),
    );
    final startText = startJson?['datas']?['cxjcs']?['rows']?[0]?['XQKSRQ']
        ?.toString()
        .split(' ')
        .first;
    final start = startText == null ? null : DateTime.tryParse(startText);
    if (start == null) return null;

    // Approximate 18 teaching weeks if end unknown.
    final end = start.add(const Duration(days: 18 * 7 - 1));
    final term = SchoolTermInfo(
      id: termCode,
      label: termCode,
      startDate: start,
      endDate: end,
      yearLabel: '${parts[0]}-${parts[1]}',
    );
    final week = scheduleWeek ?? term.teachingWeekOf(day);
    return CalendarSnapshot(
      terms: [term],
      currentTerm: term,
      events: const [],
      teachingWeek: week,
      live: true,
      banner: AppStrings.calendarJwxtBanner,
      syncedWithScheduleWeek: scheduleWeek,
    );
  }

  Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } on Object {
        return null;
      }
    }
    return null;
  }
}
