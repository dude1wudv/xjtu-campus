import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import '../domain/classroom_repository.dart';
import '../domain/classroom_slot.dart';
import 'classroom_codes.dart';
import 'classroom_webview_fetcher.dart';
import 'mock_classroom_repository.dart';

/// 空闲教室：WebView（共享网页登录 Cookie）优先，再 soft-warm + Dio jwxt/ehall。
class LiveClassroomRepository implements ClassroomRepository {
  LiveClassroomRepository({
    required this._session,
    required this._mock,
    ClassroomWebViewFetcher? webViewFetcher,
  }) : _webViewFetcher = webViewFetcher ?? ClassroomWebViewFetcher();

  final CampusSession _session;
  final MockClassroomRepository _mock;
  final ClassroomWebViewFetcher _webViewFetcher;

  ClassroomCodeMaps? _codeMaps;
  String _host = 'jwxt';

  @override
  Future<ClassroomPageData> findFree(ClassroomQuery query) async {
    _codeMaps ??= await _bundledMaps();
    var loggedIn = false;
    try {
      loggedIn = await _session.hasCasCookie();
    } on Object {
      loggedIn = false;
    }
    if (!loggedIn) {
      return _withMaps(await _mock.findFree(query), live: false, query: query);
    }
    try {
      final rooms = await _fetchLive(query);
      final maps = _codeMaps;
      final buildings = maps?.buildingNamesFor(query.campus) ?? const <String>[];
      return ClassroomPageData(
        rooms: rooms,
        live: true,
        banner: ClassroomQueryLogic.liveBanner(
          campus: query.campus,
          buildingCount: buildings.length,
          roomCount: rooms.length,
        ),
        campuses: maps?.campusNames ?? const [],
        buildingsForCampus: buildings,
        buildingCount: buildings.length,
      );
    } on Object catch (error) {
      AppLogger.warn('实时空闲教室失败，回退演示数据: $error');
      return _withMaps(
        await _demo(query, AppStrings.classroomSyncFailedBanner),
        live: false,
        query: query,
      );
    }
  }

  ClassroomPageData _withMaps(
    ClassroomPageData data, {
    required bool live,
    ClassroomQuery? query,
  }) {
    final maps = _codeMaps;
    if (maps == null || maps.isEmpty) return data;
    final names = maps.buildingNamesFor(query?.campus);
    return ClassroomPageData(
      rooms: data.rooms,
      live: live,
      banner: data.banner,
      campuses: maps.campusNames,
      buildingsForCampus: names.isNotEmpty ? names : data.buildingsForCampus,
      buildingCount: names.length,
    );
  }

  Future<ClassroomPageData> _demo(ClassroomQuery query, String banner) async {
    final demo = await _mock.findFree(query);
    return ClassroomPageData(
      rooms: demo.rooms,
      live: false,
      banner: banner,
      campuses: demo.campuses,
      buildingsForCampus: demo.buildingsForCampus,
      buildingCount: demo.buildingCount,
    );
  }

  Future<List<ClassroomSlot>> _fetchLive(ClassroomQuery query) async {
    // 1) Headless WebView shares CAS login cookie jar — try first on phone.
    try {
      final viaWebView = await _webViewFetcher.fetchFreeRooms(query);
      if (viaWebView != null) {
        if (viaWebView.maps != null && !viaWebView.maps!.isEmpty) {
          _codeMaps = viaWebView.maps;
          _logCodeSummary('WebView');
        }
        AppLogger.info(
          '空闲教室路径成功: HeadlessInAppWebView（${viaWebView.rooms.length} 间）',
        );
        return viaWebView.rooms;
      }
    } on Object catch (error) {
      AppLogger.warn('WebView 空闲教室失败，回退 Dio: $error');
    }

    // 2) Soft-warm + Dio: direct first, then WebVPN rewrite if enabled.
    Object? last;
    for (final rewrite in _rewriteModes()) {
      for (final host in ['jwxt', 'ehall']) {
        try {
          _host = host;
          _codeMaps = null;
          await _softWarm(rewrite: rewrite);
          await _switchStudentRole(rewrite: rewrite);
          await _loadCodes(rewrite: rewrite);
          final rooms = await _queryRooms(query, rewrite: rewrite);
          AppLogger.info(
            '空闲教室路径成功: Dio $_host rewrite=$rewrite（${rooms.length} 间）',
          );
          return rooms;
        } on Object catch (e) {
          last = e;
          AppLogger.warn('Dio 空闲教室失败 ($_host rewrite=$rewrite): $e');
        }
      }
    }
    throw last ?? StateError('classroom fetch failed');
  }

  List<bool> _rewriteModes() {
    if (_session.useWebVpn) {
      return const [false, true];
    }
    return const [false];
  }

  Future<void> _softWarm({required bool rewrite}) async {
    final pathLabel = rewrite ? 'webvpn' : 'direct';
    if (rewrite) {
      await _session.ensureWebVpnSession();
    }
    final loginUrl =
        _host == 'ehall' ? CampusUrls.ehallLogin : CampusUrls.jwxtHome;
    final homeUrl =
        _host == 'ehall' ? CampusUrls.ehallHome : CampusUrls.jwxtHome;
    final kxjasIndex = _host == 'ehall'
        ? CampusUrls.ehallKxjasIndex
        : CampusUrls.jwxtKxjasIndex;

    for (final entry in [
      (loginUrl, 'login/home'),
      (homeUrl, 'home'),
      (kxjasIndex, 'kxjas'),
    ]) {
      try {
        final warm = await _session.get(
          entry.$1,
          rewrite: rewrite,
          headers: {
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Referer': CampusUrls.ywtbMain,
          },
        );
        final text = _session.responseText(warm);
        final uri = warm.realUri.toString();
        if (_looksLikeLoginHtml(text) || uri.contains('/cas/login')) {
          AppLogger.warn(
            'soft-warm ${entry.$2}($_host/$pathLabel)落到登录页（$uri）',
          );
        } else {
          AppLogger.info('soft-warm ${entry.$2}($_host/$pathLabel)完成: $uri');
        }
      } on Object catch (error) {
        AppLogger.warn('soft-warm ${entry.$2}($_host/$pathLabel)失败: $error');
      }
    }
  }

  Future<List<ClassroomSlot>> _queryRooms(
    ClassroomQuery query, {
    required bool rewrite,
  }) async {
    final maps = _codeMaps;
    if (maps == null || maps.isEmpty) {
      throw StateError('missing classroom codes');
    }
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final emptyUrl = _host == 'ehall'
        ? CampusUrls.ehallEmptyRoom
        : CampusUrls.jwxtEmptyRoom;
    final referer = _host == 'ehall'
        ? CampusUrls.ehallKxjasIndex
        : CampusUrls.jwxtKxjasIndex;

    // Period filter is applied in the UI. Always query the full teaching day.
    if (query.building != null && query.building!.trim().isNotEmpty) {
      final building = maps.buildingFor(
        query.building!,
        campusName: query.campus,
      );
      final campusCode = building?.campusCode ??
          maps.campusIdFor(query.campus) ??
          maps.campuses.first.id;
      final buildingCode = building?.id;
      if (buildingCode == null) {
        throw StateError('unknown building ${query.building}');
      }
      return _queryOccupancy(
        emptyUrl: emptyUrl,
        referer: referer,
        rewrite: rewrite,
        campusCode: campusCode,
        buildingCode: buildingCode,
        date: date,
        query: query,
        fallbackBuilding: building?.name ?? query.building,
        mergePerPeriod: true,
      );
    }

    // 全部楼宇：先试校园级空 JXLDM，不行再按楼并发查询。
    final campusCodes = _campusCodesFor(query, maps);
    final batches = <List<ClassroomSlot>>[];
    for (final campusCode in campusCodes) {
      final campusWide = await _queryOccupancy(
        emptyUrl: emptyUrl,
        referer: referer,
        rewrite: rewrite,
        campusCode: campusCode,
        buildingCode: null,
        date: date,
        query: query,
        mergePerPeriod: true,
      );
      final uniqueBuildings = campusWide
          .map((room) => room.building.trim())
          .where((name) => name.isNotEmpty)
          .toSet();
      final fanOut = uniqueBuildings.length < 2;
      AppLogger.info(
        'cxkxjs 校区 $campusCode 空 JXLDM: ${campusWide.length} 间'
        ' buildings=${uniqueBuildings.length} fanOut=$fanOut',
      );
      if (!fanOut) {
        batches.add(campusWide);
        continue;
      }
      final campusName = maps.campuses
          .where((campus) => campus.id == campusCode)
          .map((campus) => campus.name)
          .cast<String>()
          .toList();
      final name = campusName.isEmpty ? query.campus : campusName.first;
      var targets = maps.buildingsForCampus(name);
      if (targets.isEmpty) targets = maps.buildings;
      AppLogger.info(
        'cxkxjs 按楼并发 ${targets.length} 栋（concurrency=${ClassroomQueryLogic.concurrency}）',
      );
      batches.add(
        await _queryBuildingsParallel(
          targets,
          emptyUrl: emptyUrl,
          referer: referer,
          rewrite: rewrite,
          campusCode: campusCode,
          date: date,
          query: query,
        ),
      );
    }
    return ClassroomQueryLogic.mergeRooms(batches);
  }

  List<String> _campusCodesFor(ClassroomQuery query, ClassroomCodeMaps maps) {
    final selected = maps.campusIdFor(query.campus);
    if (selected != null) return [selected];
    return [for (final campus in maps.campuses) campus.id];
  }

  Future<List<ClassroomSlot>> _queryBuildingsParallel(
    List<ClassroomCode> buildings, {
    required String emptyUrl,
    required String referer,
    required bool rewrite,
    required String campusCode,
    required String date,
    required ClassroomQuery query,
  }) async {
    const concurrency = ClassroomQueryLogic.concurrency;
    final batches = List<List<ClassroomSlot>?>.filled(buildings.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next;
        next += 1;
        if (index >= buildings.length) return;
        final building = buildings[index];
        try {
          batches[index] = await _queryOccupancy(
            emptyUrl: emptyUrl,
            referer: referer,
            rewrite: rewrite,
            campusCode: building.campusCode ?? campusCode,
            buildingCode: building.id,
            date: date,
            query: query,
            fallbackBuilding: building.name,
            mergePerPeriod: true,
          );
        } on Object catch (error) {
          AppLogger.warn('cxkxjs 楼宇 ${building.name} 失败: $error');
          batches[index] = const [];
        }
      }
    }

    final workers = List.generate(
      buildings.isEmpty ? 0 : concurrency.clamp(1, buildings.length),
      (_) => worker(),
    );
    await Future.wait(workers);
    return ClassroomQueryLogic.mergeRooms(
      [for (final batch in batches) batch ?? const <ClassroomSlot>[]],
    );
  }

  /// Occupancy for one campus/building.
  ///
  /// cxkxjs with KSJC=1&JSJC=11 only returns rooms free for the *entire* range.
  /// To list A-102 etc., query each period (KSJC=JSJC=p) and merge: a room is
  /// free in periods where it appeared; missing ⇒ occupied.
  Future<List<ClassroomSlot>> _queryOccupancy({
    required String emptyUrl,
    required String referer,
    required bool rewrite,
    required String campusCode,
    required String? buildingCode,
    required String date,
    required ClassroomQuery query,
    String? fallbackBuilding,
    required bool mergePerPeriod,
  }) async {
    const start = ClassroomQueryLogic.firstPeriod;
    const end = ClassroomQueryLogic.lastPeriod;

    if (!mergePerPeriod) {
      final single = await _postCxkxjs(
        emptyUrl: emptyUrl,
        referer: referer,
        rewrite: rewrite,
        campusCode: campusCode,
        buildingCode: buildingCode,
        date: date,
        start: start,
        end: end,
        query: query,
        fallbackBuilding: fallbackBuilding,
      );
      return single.rooms;
    }

    // Optional full-range probe: those rows are free all day (after filters).
    final full = await _postCxkxjs(
      emptyUrl: emptyUrl,
      referer: referer,
      rewrite: rewrite,
      campusCode: campusCode,
      buildingCode: buildingCode,
      date: date,
      start: start,
      end: end,
      query: query,
      fallbackBuilding: fallbackBuilding,
    );

    final byPeriod = <int, List<ClassroomSlot>>{};
    const concurrency = ClassroomQueryLogic.concurrency;
    var next = start;
    Future<void> worker() async {
      while (true) {
        final period = next;
        next += 1;
        if (period > end) return;
        try {
          final slice = await _postCxkxjs(
            emptyUrl: emptyUrl,
            referer: referer,
            rewrite: rewrite,
            campusCode: campusCode,
            buildingCode: buildingCode,
            date: date,
            start: period,
            end: period,
            query: query,
            fallbackBuilding: fallbackBuilding,
          );
          byPeriod[period] = slice.rooms;
        } on Object catch (error) {
          AppLogger.warn('cxkxjs 节次 $period 失败: $error');
          byPeriod[period] = const [];
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));

    // Full-range hits are free 1..11; per-period appearance adds the rest.
    final seeds = [
      for (final room in full.rooms)
        ClassroomSlot(
          id: room.id,
          campus: room.campus,
          building: room.building,
          room: room.room,
          capacity: room.capacity,
          freePeriods: [
            for (var period = start; period <= end; period++) period,
          ],
          hasProjector: room.hasProjector,
        ),
    ];
    final merged = ClassroomQueryLogic.mergeOccupancy(
      byPeriod,
      seeds: seeds,
      appearanceOnly: true,
    );
    AppLogger.info(
      'cxkxjs 按节次合并 ${merged.length} 间（全日自由 ${full.rooms.length}）',
    );
    return merged;
  }

  Future<ClassroomParseResult> _postCxkxjs({
    required String emptyUrl,
    required String referer,
    required bool rewrite,
    required String campusCode,
    required String? buildingCode,
    required String date,
    required int start,
    required int end,
    required ClassroomQuery query,
    String? fallbackBuilding,
  }) async {
    final data = <String, dynamic>{
      'XXXQDM': campusCode,
      'KXRQ': date,
      'KSJC': start,
      'JSJC': end,
      'pageSize': ClassroomQueryLogic.pageSize,
      'pageNumber': 1,
    };
    if (buildingCode != null && buildingCode.isNotEmpty) {
      data['JXLDM'] = buildingCode;
    }
    final response = await _session.post(
      emptyUrl,
      data: data,
      headers: {
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'Referer': referer,
        'X-Requested-With': 'XMLHttpRequest',
      },
      rewrite: rewrite,
    );
    final raw = _session.responseText(response);
    if (_looksLikeLoginHtml(raw)) {
      throw StateError('cxkxjs returned login html');
    }
    final json = _session.tryJson(response);
    if (json == null) {
      throw StateError('cxkxjs not json');
    }
    return ClassroomQueryLogic.parseResult(
      json,
      query: query,
      fallbackBuilding: fallbackBuilding,
      start: start,
      end: end,
    );
  }

  static const _campusAsset = 'docs/jwxt-campus-codes.json';
  static const _buildingAsset = 'docs/jwxt-building-codes.json';

  Future<ClassroomCodeMaps?> _bundledMaps() async {
    try {
      final campusRaw = await rootBundle.loadString(_campusAsset);
      final buildingRaw = await rootBundle.loadString(_buildingAsset);
      final maps = ClassroomCodeMaps.parse(
        campusJson: jsonDecode(campusRaw),
        buildingJson: jsonDecode(buildingRaw),
      );
      if (maps.isEmpty) return null;
      _logCodeSummaryFor(maps, 'bundled');
      return maps;
    } on Object catch (error) {
      AppLogger.warn('内置教室代码表读取失败: $error');
      return null;
    }
  }

  Future<void> _loadCodes({required bool rewrite}) async {
    if (_codeMaps != null && !_codeMaps!.isEmpty) return;
    final campusUrl =
        _host == 'ehall' ? CampusUrls.ehallCampusCode : CampusUrls.jwxtCampusCode;
    final buildingUrl = _host == 'ehall'
        ? CampusUrls.ehallBuildingCode
        : CampusUrls.jwxtBuildingCode;
    final campusJson = await _codeJson(campusUrl, rewrite: rewrite);
    final buildingJson = await _codeJson(buildingUrl, rewrite: rewrite);
    _codeMaps = ClassroomCodeMaps.parse(
      campusJson: campusJson,
      buildingJson: buildingJson,
    );
    if (_codeMaps!.isEmpty) {
      throw StateError('empty classroom code maps');
    }
    _logCodeSummary('Dio $_host');
  }

  void _logCodeSummary(String source) {
    final maps = _codeMaps;
    if (maps == null) return;
    _logCodeSummaryFor(maps, source);
  }

  void _logCodeSummaryFor(ClassroomCodeMaps maps, String source) {
    final counts = maps.buildingCountsByCampus().entries
        .map((e) => '${e.key} ${e.value}栋')
        .join('、');
    AppLogger.info(
      '教室代码表($source): 校区 ${maps.campuses.length} 个，'
      '教学楼 ${maps.buildings.length} 栋（$counts）',
    );
  }

  Future<Map<String, dynamic>> _codeJson(
    String url, {
    required bool rewrite,
  }) async {
    final referer = _host == 'ehall'
        ? CampusUrls.ehallKxjasIndex
        : CampusUrls.jwxtKxjasIndex;
    final headers = {
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'Referer': referer,
      'X-Requested-With': 'XMLHttpRequest',
    };
    var response = await _session.get(
      url,
      headers: headers,
      rewrite: rewrite,
    );
    var raw = _session.responseText(response);
    var json = _session.tryJson(response);
    var rows = json?['datas']?['code']?['rows'];
    if (_looksLikeLoginHtml(raw) || rows is! List) {
      response = await _session.post(
        url,
        headers: headers,
        rewrite: rewrite,
      );
      raw = _session.responseText(response);
      json = _session.tryJson(response);
      rows = json?['datas']?['code']?['rows'];
    }
    if (_looksLikeLoginHtml(raw)) {
      throw StateError('code endpoint returned login html');
    }
    if (json == null) {
      throw StateError('code endpoint not json');
    }
    return json;
  }

  Future<void> _switchStudentRole({required bool rewrite}) async {
    try {
      final userUrl = _host == 'ehall'
          ? CampusUrls.ehallCurrentUser
          : CampusUrls.jwxtCurrentUser;
      final roleUrl = _host == 'ehall'
          ? CampusUrls.ehallChangeRole
          : CampusUrls.jwxtChangeRole;
      final referer = _host == 'ehall'
          ? 'https://ehall.xjtu.edu.cn/jwapp/sys/homeapp/home/index.html?av=&contextPath=/jwapp'
          : 'https://jwxt.xjtu.edu.cn/jwapp/sys/homeapp/home/index.html?av=&contextPath=/jwapp';
      final json = _session.tryJson(
        await _session.get(
          userUrl,
          headers: {'Referer': referer},
          rewrite: rewrite,
        ),
      );
      final groups = json?['datas']?['userGroups'];
      if (groups is! List) return;
      String? studentId;
      var currentIsStudent = false;
      for (final raw in groups) {
        if (raw is! Map) continue;
        if (raw['roleName'] == '学生') {
          studentId = raw['roleId']?.toString();
          currentIsStudent = raw['currentRole'] == true;
        }
      }
      if (!currentIsStudent && studentId != null) {
        await _session.post(
          roleUrl,
          data: {'appRole': studentId},
          rewrite: rewrite,
        );
      }
    } on Object {
      // 角色切换失败时仍尝试查询。
    }
  }

  bool _looksLikeLoginHtml(String raw) {
    final trimmed = raw.trimLeft();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (!(lower.startsWith('<!doctype') ||
        lower.startsWith('<html') ||
        lower.contains('<body'))) {
      return false;
    }
    return lower.contains('cas/login') ||
        lower.contains('统一身份认证') ||
        lower.contains('login.xjtu.edu.cn') ||
        lower.contains('name="execution"') ||
        lower.contains('请输入密码');
  }
}
