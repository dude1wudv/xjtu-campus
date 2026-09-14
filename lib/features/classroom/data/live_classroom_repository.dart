import '../../../core/constants/campus_urls.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import '../domain/classroom_repository.dart';
import '../domain/classroom_slot.dart';
import 'mock_classroom_repository.dart';

/// 空闲教室：CAS 登录后走教务 kxjas（一网通办会话用于身份）。
class LiveClassroomRepository implements ClassroomRepository {
  LiveClassroomRepository({
    required this._session,
    required this._mock,
  });

  final CampusSession _session;
  final MockClassroomRepository _mock;

  @override
  Future<ClassroomPageData> findFree(ClassroomQuery query) async {
    final loggedIn = await _session.hasCasCookie();
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
        banner: '实时空闲教室 · 教务 kxjas（一网通办登录后，校外需 WebVPN）',
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

  Future<List<ClassroomSlot>> _fetchLive(ClassroomQuery query) async {
    await _switchStudentRole();
    await _loadCodes();
    final campusCode = _campuses?[query.campus ?? '兴庆校区'] ?? _campuses?.values.first;
    final buildingName = query.building ?? '主楼A';
    final buildingCode = _buildings?[buildingName] ?? _buildings?['主楼A'];
    if (campusCode == null || buildingCode == null) {
      throw StateError('missing classroom codes');
    }
    final date =
        '${DateTime.now().year.toString().padLeft(4, '0')}-'
        '${DateTime.now().month.toString().padLeft(2, '0')}-'
        '${DateTime.now().day.toString().padLeft(2, '0')}';
    final start = query.period ?? 1;
    final end = query.period ?? 11;
    final json = _session.tryJson(
      await _session.post(
        CampusUrls.jwxtEmptyRoom,
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
    _campuses = await _codeMap(CampusUrls.jwxtCampusCode);
    _buildings = await _codeMap(CampusUrls.jwxtBuildingCode);
  }

  Future<Map<String, String>> _codeMap(String url) async {
    final json = _session.tryJson(
      await _session.post(
        url,
        headers: {
          'Referer': 'https://jwxt.xjtu.edu.cn/jwapp/sys/kxjas/*default/index.do',
        },
      ),
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
      final json = _session.tryJson(
        await _session.get(
          CampusUrls.jwxtCurrentUser,
          headers: {
            'Referer':
                'https://jwxt.xjtu.edu.cn/jwapp/sys/homeapp/home/index.html?av=&contextPath=/jwapp',
          },
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
          CampusUrls.jwxtChangeRole,
          data: {'appRole': studentId},
        );
      }
    } on Object {
      // 角色切换失败时仍尝试查询。
    }
  }
}
