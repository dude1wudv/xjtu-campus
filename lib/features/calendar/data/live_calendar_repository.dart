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

/// Prefer jwxt term dates when logged in; try one2020 public calendar;
/// synthesize live teaching-week snapshot without fake holiday demos.
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

    // a) PRIMARY: jwxt term start when logged in (not only after one2020 fails).
    try {
      final fromJwxt = await _fromJwxtTerm(day, scheduleWeek);
      if (fromJwxt != null) {
        // Still enrich events from one2020 if available.
        final enriched = await _tryEnrichEvents(fromJwxt, day);
        return enriched;
      }
    } on Object catch (error) {
      AppLogger.warn('jwxt 学期起止失败: $error');
    }

    // b/c) one2020 public (HTTP + HTTPS + scrape); empty terms ≠ fatal.
    try {
      final live = await _fetchOne2020(day, scheduleWeek);
      if (live != null) return live;
    } on Object catch (error) {
      AppLogger.warn('one2020 校历失败: $error');
    }

    // d) scheduleWeek known → show real teaching week as live (no fake events).
    if (scheduleWeek != null && scheduleWeek > 0) {
      AppLogger.info('校历：使用课表教学周 $scheduleWeek（无官方学期明细）');
      return CalendarSnapshot(
        terms: const [],
        currentTerm: null,
        events: const [],
        teachingWeek: scheduleWeek,
        live: true,
        banner: AppStrings.calendarWeekOnlyBanner,
        syncedWithScheduleWeek: scheduleWeek,
      );
    }

    // Completely offline / no live signal → labeled demo only.
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

  Future<CalendarSnapshot> _tryEnrichEvents(
    CalendarSnapshot jwxt,
    DateTime day,
  ) async {
    try {
      final one = await _fetchOne2020(day, jwxt.syncedWithScheduleWeek);
      if (one != null && one.events.isNotEmpty) {
        return CalendarSnapshot(
          terms: one.terms.isNotEmpty ? one.terms : jwxt.terms,
          currentTerm: one.currentTerm ?? jwxt.currentTerm,
          events: one.events,
          teachingWeek: jwxt.teachingWeek,
          live: true,
          banner: AppStrings.calendarLiveBanner,
          syncedWithScheduleWeek: jwxt.syncedWithScheduleWeek,
        );
      }
    } on Object catch (error) {
      AppLogger.warn('one2020 事件补充失败（保留 jwxt 教学周）: $error');
    }
    return jwxt;
  }

  Future<CalendarSnapshot?> _fetchOne2020(
    DateTime day,
    int? scheduleWeek,
  ) async {
    final bases = <(String page, String terms, String byId)>[
      (
        CampusUrls.one2020CalendarPage,
        CampusUrls.one2020Terms,
        CampusUrls.one2020TermById,
      ),
      (
        CampusUrls.one2020CalendarPageHttps,
        CampusUrls.one2020TermsHttps,
        CampusUrls.one2020TermByIdHttps,
      ),
    ];

    for (final base in bases) {
      try {
        final snap = await _fetchOne2020At(
          day,
          scheduleWeek,
          page: base.$1,
          termsUrl: base.$2,
          byIdUrl: base.$3,
        );
        if (snap != null) return snap;
      } on Object catch (error) {
        AppLogger.warn('one2020 请求失败: $error');
      }
    }

    // Scrape showCalendar.htm for embedded dates if AJAX terms empty.
    try {
      final scraped = await _scrapeShowCalendar(day, scheduleWeek);
      if (scraped != null) return scraped;
    } on Object catch (error) {
      AppLogger.warn('showCalendar.htm 解析失败: $error');
    }

    return null;
  }

  Future<CalendarSnapshot?> _fetchOne2020At(
    DateTime day,
    int? scheduleWeek, {
    required String page,
    required String termsUrl,
    required String byIdUrl,
  }) async {
    try {
      await _dio.get(page);
    } on Object {
      // ignore warm failure
    }

    // Try empty body + a few alternate form params.
    final paramVariants = <Object?>[
      '',
      <String, dynamic>{},
      <String, dynamic>{'year': '${day.year}'},
      <String, dynamic>{'t': '${day.millisecondsSinceEpoch}'},
    ];

    List<SchoolTermInfo> terms = const [];
    for (final params in paramVariants) {
      final termsResp = await _dio.post(
        termsUrl,
        data: params,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': page,
          },
        ),
      );
      final termsJson = _asMap(termsResp.data);
      if (termsJson == null) continue;
      terms = One2020CalendarMapper.termsFromJson(termsJson);
      if (terms.isNotEmpty) break;
      // Official empty list is success-but-empty — do not treat as hard failure.
      final code = termsJson['code']?.toString();
      if (code == '200' || code == '0') {
        AppLogger.info('one2020 terms 返回空列表 code=$code');
        break;
      }
    }

    if (terms.isEmpty) return null;

    SchoolTermInfo? current;
    for (final t in terms) {
      if (t.contains(day)) {
        current = t;
        break;
      }
    }
    current ??= terms.first;

    var events = <CalendarEvent>[];
    if (current.id.isNotEmpty) {
      try {
        final detailResp = await _dio.post(
          byIdUrl,
          data: {'id': current.id},
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {
              'X-Requested-With': 'XMLHttpRequest',
              'Referer': page,
            },
          ),
        );
        final detail = One2020CalendarMapper.detailFromJson(
          _asMap(detailResp.data) ?? detailResp.data,
        );
        if (detail.term != null) current = detail.term!;
        events = detail.events;
      } on Object catch (error) {
        AppLogger.warn('one2020 queryTermById 失败: $error');
      }
    }

    final week = scheduleWeek ?? current!.teachingWeekOf(day);
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

  Future<CalendarSnapshot?> _scrapeShowCalendar(
    DateTime day,
    int? scheduleWeek,
  ) async {
    for (final url in [
      CampusUrls.one2020CalendarPage,
      CampusUrls.one2020CalendarPageHttps,
    ]) {
      try {
        final resp = await _dio.get<String>(
          url,
          options: Options(
            responseType: ResponseType.plain,
            headers: {'Accept': 'text/html,application/xhtml+xml'},
          ),
        );
        final html = resp.data;
        if (html == null || html.isEmpty) continue;
        final parsed = One2020CalendarMapper.termsFromHtml(html);
        if (parsed.isEmpty) continue;
        SchoolTermInfo? current;
        for (final t in parsed) {
          if (t.contains(day)) {
            current = t;
            break;
          }
        }
        current ??= parsed.first;
        final week = scheduleWeek ?? current.teachingWeekOf(day);
        AppLogger.info('校历路径成功: showCalendar.htm scrape');
        return CalendarSnapshot(
          terms: parsed,
          currentTerm: current,
          events: const [],
          teachingWeek: week,
          live: true,
          banner: AppStrings.calendarLiveBanner,
          syncedWithScheduleWeek: scheduleWeek,
        );
      } on Object catch (error) {
        AppLogger.warn('scrape $url 失败: $error');
      }
    }
    return null;
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

    // Soft-warm home like grades/schedule so dqxnxq/cxjcs succeed.
    await _softWarmJwxt();

    final termCode = await _resolveJwxtTermCode();
    if (termCode == null || termCode.isEmpty) return null;

    final parts = termCode.split('-');
    if (parts.length < 3) return null;

    DateTime? start;
    DateTime? end;
    for (final startUrl in [
      CampusUrls.jwxtTermStart,
      CampusUrls.ehallTermStart,
    ]) {
      try {
        final startJson = _session.tryJson(
          await _session.post(
            startUrl,
            rewrite: false,
            data: {'XN': '${parts[0]}-${parts[1]}', 'XQ': parts[2]},
            headers: {
              'Accept': 'application/json, text/javascript, */*; q=0.01',
              'X-Requested-With': 'XMLHttpRequest',
            },
          ),
        );
        final row = startJson?['datas']?['cxjcs']?['rows'];
        if (row is! List || row.isEmpty) continue;
        final first = row.first;
        if (first is! Map) continue;
        final startText =
            first['XQKSRQ']?.toString().split(' ').first;
        final endText = first['XQJSRQ']?.toString().split(' ').first;
        start = startText == null ? null : DateTime.tryParse(startText);
        end = endText == null ? null : DateTime.tryParse(endText);
        if (start != null) break;
      } on Object catch (error) {
        AppLogger.warn('cxjcs 失败 ($startUrl): $error');
      }
    }
    if (start == null) return null;

    // Approximate 18 teaching weeks if end unknown — no fake 国庆/期末 events.
    end ??= start.add(const Duration(days: 18 * 7 - 1));
    final term = SchoolTermInfo(
      id: termCode,
      label: termCode,
      startDate: start,
      endDate: end,
      yearLabel: '${parts[0]}-${parts[1]}',
    );
    final week = scheduleWeek ?? term.teachingWeekOf(day);
    AppLogger.info('校历路径成功: jwxt term=$termCode week=$week');
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

  Future<void> _softWarmJwxt() async {
    for (final url in [
      CampusUrls.jwxtHome,
      CampusUrls.jwxtWdkbIndex,
    ]) {
      try {
        await _session.get(
          url,
          rewrite: false,
          headers: {
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Referer': CampusUrls.ywtbMain,
          },
        );
      } on Object catch (error) {
        AppLogger.warn('calendar jwxt soft-warm 失败: $error');
      }
    }
  }

  Future<String?> _resolveJwxtTermCode() async {
    for (final url in [
      CampusUrls.jwxtCurrentTerm,
      CampusUrls.ehallCurrentTerm,
    ]) {
      try {
        final json = _session.tryJson(
          await _session.post(
            url,
            rewrite: false,
            headers: {
              'Accept': 'application/json, text/javascript, */*; q=0.01',
              'X-Requested-With': 'XMLHttpRequest',
            },
          ),
        );
        final term =
            json?['datas']?['dqxnxq']?['rows']?[0]?['DM']?.toString();
        if (term != null && term.isNotEmpty) return term;
      } on Object catch (error) {
        AppLogger.warn('解析当前学期失败 ($url): $error');
      }
    }
    return null;
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
