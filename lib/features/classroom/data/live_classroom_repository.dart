import '../../../core/constants/campus_urls.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import '../domain/classroom_repository.dart';
import '../domain/classroom_slot.dart';
import 'mock_classroom_repository.dart';

/// 空闲教室：优先 ehall（CAS 已注册），失败再试 jwxt。
class LiveClassroomRepository implements ClassroomRepository {
  LiveClassroomRepository({
    required this._session,
    required this._mock,
  });

  final CampusSession _session;
  final MockClassroomRepository _mock;

  @override
  Future<ClassroomPageData> findFree(ClassroomQuery query) async {
    var loggedIn = false;
    try {
      loggedIn = await _session.hasCasCookie();
    } on Object {
      loggedIn = false;
    }
    if (!loggedIn) {
      final demo = await _mock.findFree(query);
      return ClassroomPageData(
        rooms: demo.rooms,
        live: false,
        banner: AppStrings.mockBanner,
      );
    }
    try {
      final rooms = await _fetchLive(query);
      return ClassroomPageData(
        rooms: rooms,
        live: true,
        banner: '实时空闲教室（优先 ehall；校外可开 WebVPN）',
      );
    } on Object {
      AppLogger.warn('实时空闲教室失败，回退演示数据');
      final demo = await _mock.findFree(query);
      return ClassroomPageData(
        rooms: demo.rooms,
        live: false,
        banner: AppStrings.liveFallbackBanner,
      );
    }
  }

  Map<String, String>? _campuses;
  Map<String, String>? _buildings;
  String _host = 'ehall';

  Future<List<ClassroomSlot>> _fetchLive(ClassroomQuery query) async {
    Object? last;
    for (final host in ['ehall', 'jwxt']) {
      try {
        _host = host;
        _campuses = null;
        _buildings = null;
        await _switchStudentRole();
        await _loadCodes();
        return await _queryRooms(query);
      } on Object catch (e) {
        last = e;
      }
    }
    throw last ?? StateError('classroom fetch failed');
  }

  Future<List<ClassroomSlot>> _queryRooms(ClassroomQuery query) async {
    final campusCode =
        _campuses?[query.campus ?? '兴庆校区'] ?? _campuses?.values.first;
    final buildingName = query.building ?? '主楼A';
    final buildingCode = _buildings?[buildingName] ?? _buildings?['主楼A'];
    if (campusCode == null || buildingCode == null) {
      throw StateError('missing classroom codes');
    }
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final start = query.period ?? 1;
    final end = query.period ?? 11;
    final emptyUrl = _host == 'ehall'
        ? CampusUrls.ehallEmptyRoom
        : CampusUrls.jwxtEmptyRoom;
    final json = _session.tryJson(
      await _session.post(
        emptyUrl,
        data: {
          'XXXQDM': campusCode,
          'JXLDM': buildingCode,
          'KXRQ': date,
          'KSJC': start,
          'JSJC': end,
          'pageSize': 200,
          'pageNumber': 1,
        },
      ),
    );
    final rows = json?['datas']?['cxkxjs']?['rows'];
    if (rows is! List) return [];
    final rooms = <ClassroomSlot>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      if (row['JASLXDM'] == null) continue;
      final name = row['JASMC']?.toString() ?? '';
      if (name.contains('测试专用')) continue;
      rooms.add(
        ClassroomSlot(
          id: name,
          campus: row['XXXQDM_DISPLAY']?.toString() ?? query.campus ?? '',
          building: row['JXLDM_DISPLAY']?.toString() ?? buildingName,
          room: name,
          capacity: int.tryParse(row['SKZWS']?.toString() ?? '') ?? 0,
          freePeriods: [for (var p = start; p <= end; p++) p],
        ),
      );
    }
    return rooms;
  }

  Future<void> _loadCodes() async {
    if (_campuses != null && _buildings != null) return;
    final campusUrl =
        _host == 'ehall' ? CampusUrls.ehallCampusCode : CampusUrls.jwxtCampusCode;
    final buildingUrl = _host == 'ehall'
        ? CampusUrls.ehallBuildingCode
        : CampusUrls.jwxtBuildingCode;
    _campuses = await _codeMap(campusUrl);
    _buildings = await _codeMap(buildingUrl);
  }

  Future<Map<String, String>> _codeMap(String url) async {
    final referer = _host == 'ehall'
        ? 'https://ehall.xjtu.edu.cn/jwapp/sys/kxjas/*default/index.do'
        : 'https://jwxt.xjtu.edu.cn/jwapp/sys/kxjas/*default/index.do';
    final json = _session.tryJson(
      await _session.post(url, headers: {'Referer': referer}),
    );
    final rows = json?['datas']?['code']?['rows'];
    final map = <String, String>{};
    if (rows is List) {
      for (final raw in rows) {
        if (raw is Map) {
          map['${raw['name']}'] = '${raw['id']}';
        }
      }
    }
    return map;
  }

  Future<void> _switchStudentRole() async {
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
        await _session.get(userUrl, headers: {'Referer': referer}),
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
        await _session.post(roleUrl, data: {'appRole': studentId});
      }
    } on Object {
      // 角色切换失败时仍尝试查询。
    }
  }
}
