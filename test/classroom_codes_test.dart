import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xjtu_campus/features/classroom/data/classroom_codes.dart';
import 'package:xjtu_campus/features/classroom/domain/classroom_slot.dart';
import 'package:xjtu_campus/features/notifications/data/dean_notice_parser.dart';
import 'package:xjtu_campus/features/notifications/data/dean_webview_notices_fetcher.dart';
import 'package:xjtu_campus/features/notifications/domain/school_notice.dart';

void main() {
  late ClassroomCodeMaps maps;

  setUpAll(() {
    final campus = jsonDecode(
      File('docs/jwxt-campus-codes.json').readAsStringSync(),
    );
    final building = jsonDecode(
      File('docs/jwxt-building-codes.json').readAsStringSync(),
    );
    maps = ClassroomCodeMaps.parse(campusJson: campus, buildingJson: building);
  });

  test('bundled jwxt codes: 6 campuses, 114 buildings, 兴庆 58 栋含主楼A', () {
    expect(maps.campuses, hasLength(6));
    expect(maps.buildings, hasLength(114));
    expect(maps.campusNames, containsAll(['兴庆校区', '雁塔校区', '创新港校区', '曲江校区']));
    expect(maps.campusNames.first, '兴庆校区');
    expect(maps.campusIdFor('兴庆校区'), '1');
    final xingqing = maps.buildingsForCampus('兴庆校区');
    expect(xingqing, hasLength(58));
    expect(xingqing.map((b) => b.name), containsAll(['主楼A', '主楼B', '主楼C', '主楼D', '中2', '中3']));
    expect(maps.buildingFor('主楼A', campusName: '兴庆校区')?.id, '1001');
    final counts = maps.buildingCountsByCampus();
    expect(counts['兴庆校区'], 58);
    expect(counts['雁塔校区'], 34);
    expect(counts['创新港校区'], 16);
  });

  test('全部楼宇 does not default to 主楼A in code lookup', () {
    expect(maps.buildingFor('', campusName: '兴庆校区'), isNull);
    final all = maps.buildingNamesFor('兴庆校区');
    expect(all.length, greaterThan(1));
    expect(all, containsAll(['主楼A', '主楼B', '仲英楼']));
  });

  test('parse JC1-JC11 occupancy fields', () {
    final json = {
      'datas': {
        'cxkxjs': {
          'totalSize': 3,
          'rows': [
            {
              'JASLXDM': '01',
              'JASMC': 'A102',
              'JXLDM_DISPLAY': '主楼A',
              'XXXQDM_DISPLAY': '兴庆校区',
              'SKZWS': 80,
              'JC1': '空闲',
              'JC2': '空闲',
              'JC3': '占用',
              'JC4': '占用',
              'JC5': '',
              'JC6': '0',
              'JC7': '线性代数',
              'JC8': '1',
              'JC9': '空闲',
              'JC10': '空闲',
              'JC11': '空闲',
            },
            {
              'JASLXDM': '01',
              'JASMC': 'A103',
              'JXLDM_DISPLAY': '主楼A',
              'XXXQDM_DISPLAY': '兴庆校区',
              'SKZWS': 40,
              'KXJC': '1,2,5-6,9-11',
            },
            {
              'JASLXDM': '01',
              'JASMC': 'A202',
              'JXLDM_DISPLAY': '主楼A',
              'XXXQDM_DISPLAY': '兴庆校区',
              'SKZWS': 90,
              'KB': '00110011000',
            },
          ],
        },
      },
    };
    final parsed = ClassroomQueryLogic.parseResult(
      json,
      query: const ClassroomQuery(campus: '兴庆校区', building: '主楼A'),
      start: 1,
      end: 11,
    );
    expect(parsed.hasPeriodFields, isTrue);
    expect(parsed.rooms, hasLength(3));
    expect(parsed.rooms.map((r) => r.room), containsAll(['A102', 'A103', 'A202']));
    expect(parsed.rooms.first.periodText, contains('空闲:'));
    expect(parsed.rooms.first.freePeriods, containsAll([1, 2, 5, 6, 9, 10, 11]));
    expect(parsed.rooms.first.freePeriods, isNot(contains(3)));
  });

  test('periodText lists free ranges, not first-last span', () {
    const room = ClassroomSlot(
      id: 'x',
      campus: '兴庆校区',
      building: '主楼A',
      room: 'A102',
      capacity: 80,
      freePeriods: [1, 2, 5, 6, 9, 10, 11],
    );
    expect(room.periodText, '空闲: 1-2,5-6,9-11');
    expect(room.occupiedPeriods, [3, 4, 7, 8]);
    const busy = ClassroomSlot(
      id: 'y',
      campus: '兴庆校区',
      building: '主楼A',
      room: 'A999',
      capacity: 10,
      freePeriods: [],
    );
    expect(busy.periodText, '全天占用');
  });

  test('merge per-period queries unions free slots for all rooms', () {
    ClassroomSlot room(String name, List<int> free) => ClassroomSlot(
          id: '兴庆校区|主楼A|$name',
          campus: '兴庆校区',
          building: '主楼A',
          room: name,
          capacity: 40,
          freePeriods: free,
        );
    final merged = ClassroomQueryLogic.mergeOccupancy({
      1: [room('A102', [1]), room('A103', [1])],
      2: [room('A102', [2])],
      5: [room('A103', [5]), room('A202', [5])],
    });
    expect(merged.map((r) => r.room), containsAll(['A102', 'A103', 'A202']));
    expect(merged, hasLength(3));
    final a102 = merged.firstWhere((r) => r.room == 'A102');
    expect(a102.freePeriods, [1, 2]);
  });

  test('period filter is applied after full-day parse', () {
    final rooms = [
      const ClassroomSlot(
        id: 'a',
        campus: '兴庆校区',
        building: '主楼A',
        room: 'A102',
        capacity: 1,
        freePeriods: [1, 2, 5],
      ),
      const ClassroomSlot(
        id: 'b',
        campus: '兴庆校区',
        building: '主楼A',
        room: 'A103',
        capacity: 1,
        freePeriods: [3, 4],
      ),
    ];
    expect(ClassroomQueryLogic.filterByPeriod(rooms, null), hasLength(2));
    expect(
      ClassroomQueryLogic.filterByPeriod(rooms, 5).map((r) => r.room),
      ['A102'],
    );
  });

  test('shouldFanOut when only one building or empty', () {
    expect(
      ClassroomQueryLogic.shouldFanOut(rooms: const [], totalSize: 0),
      isTrue,
    );
    final one = [
      const ClassroomSlot(
        id: 'a',
        campus: '兴庆校区',
        building: '主楼A',
        room: 'A102',
        capacity: 1,
        freePeriods: [1],
      ),
    ];
    expect(ClassroomQueryLogic.shouldFanOut(rooms: one, totalSize: 1), isTrue);
  });

  test('drops 考试/通知 rows; keeps digit teaching rooms like 主楼A-102', () {
    final json = {
      'datas': {
        'cxkxjs': {
          'totalSize': 5,
          'rows': [
            {
              'JASLXDM': '99',
              'JASLXDM_DISPLAY': '其他',
              'JASMC': '随堂考试',
              'JXLDM_DISPLAY': '主楼A',
              'XXXQDM_DISPLAY': '兴庆校区',
              'SKZWS': 0,
              'JC1': '0',
            },
            {
              'JASLXDM': '98',
              'JASLXDM_DISPLAY': '通知',
              'JASMC': '学院通知',
              'JXLDM_DISPLAY': '主楼A',
              'XXXQDM_DISPLAY': '兴庆校区',
              'SKZWS': 0,
            },
            {
              'JASLXDM': '01',
              'JASLXDM_DISPLAY': '普通教室',
              'JASMC': '主楼A-102',
              'JXLDM_DISPLAY': '主楼A',
              'XXXQDM_DISPLAY': '兴庆校区',
              'SKZWS': 120,
              'JC1': '0',
              'JC2': '0',
              'JC3': '1',
            },
            {
              'JASLXDM': '01',
              'JASLXDM_DISPLAY': '普通教室',
              'JASMC': '主楼A-103',
              'JXLDM_DISPLAY': '主楼A',
              'XXXQDM_DISPLAY': '兴庆校区',
              'SKZWS': 80,
              'JC1': '0',
            },
            {
              'JASLXDM': '01',
              'JASLXDM_DISPLAY': '普通教室',
              'JASMC': 'A-105',
              'JXLDM_DISPLAY': '主楼A',
              'XXXQDM_DISPLAY': '兴庆校区',
              'SKZWS': 60,
              'JC1': '0',
            },
          ],
        },
      },
    };
    final parsed = ClassroomQueryLogic.parseResult(
      json,
      query: const ClassroomQuery(campus: '兴庆校区', building: '主楼A'),
      start: 1,
      end: 11,
    );
    expect(parsed.rooms.map((r) => r.room), isNot(contains('随堂考试')));
    expect(parsed.rooms.map((r) => r.room), isNot(contains('学院通知')));
    expect(
      parsed.rooms.map((r) => r.room),
      containsAll(['主楼A-102', '主楼A-103', 'A-105']),
    );
    expect(parsed.rooms, hasLength(3));
    expect(ClassroomQueryLogic.pageSize, greaterThanOrEqualTo(200));
  });

  test('KXJC-only does not count as column occupancy fields', () {
    expect(
      ClassroomQueryLogic.rowHasPeriodFields({
        'JASMC': '主楼A-102',
        'KXJC': '1-11节',
      }),
      isFalse,
    );
    expect(
      ClassroomQueryLogic.rowHasPeriodFields({
        'JASMC': '主楼A-102',
        'JC1': '0',
        'JC2': '1',
      }),
      isTrue,
    );
  });

  test('docs zhuloua sample filters to numbered rooms only', () {
    final json = jsonDecode(
      File('docs/jwxt-cxkxjs-zhuloua-sample.json').readAsStringSync(),
    );
    final parsed = ClassroomQueryLogic.parseResult(
      json,
      query: const ClassroomQuery(campus: '兴庆校区', building: '主楼A'),
      start: 1,
      end: 11,
    );
    expect(parsed.rooms.map((r) => r.room), isNot(contains('随堂考试.')));
    expect(parsed.rooms.map((r) => r.room), isNot(contains('学院通知')));
    expect(parsed.rooms.map((r) => r.room), contains('主楼A-108'));
    expect(parsed.hasPeriodFields, isFalse);
  });

  test('appearance-only merge: free only in periods room appeared', () {
    ClassroomSlot room(String name) => ClassroomSlot(
          id: '兴庆校区|主楼A|$name',
          campus: '兴庆校区',
          building: '主楼A',
          room: name,
          capacity: 40,
          freePeriods: const [],
        );
    final merged = ClassroomQueryLogic.mergeOccupancy(
      {
        1: [room('主楼A-102'), room('主楼A-103')],
        2: [room('主楼A-102')],
        5: [room('主楼A-103'), room('主楼A-105')],
        // A-102 missing in 5 ⇒ occupied period 5
      },
      appearanceOnly: true,
    );
    expect(
      merged.map((r) => r.room),
      containsAll(['主楼A-102', '主楼A-103', '主楼A-105']),
    );
    expect(
      merged.firstWhere((r) => r.room == '主楼A-102').freePeriods,
      [1, 2],
    );
    expect(
      merged.firstWhere((r) => r.room == '主楼A-103').freePeriods,
      [1, 5],
    );
    expect(
      merged.firstWhere((r) => r.room == '主楼A-105').freePeriods,
      [5],
    );
  });

  test('single-period parseResult marks only that period free', () {
    final parsed = ClassroomQueryLogic.parseResult(
      {
        'datas': {
          'cxkxjs': {
            'rows': [
              {
                'JASLXDM': '01',
                'JASMC': '主楼A-102',
                'JXLDM_DISPLAY': '主楼A',
                'XXXQDM_DISPLAY': '兴庆校区',
                'KXJC': '1-11节',
                'SKZWS': 100,
              },
            ],
          },
        },
      },
      query: const ClassroomQuery(campus: '兴庆校区', building: '主楼A'),
      start: 3,
      end: 3,
    );
    expect(parsed.rooms, hasLength(1));
    expect(parsed.rooms.first.freePeriods, [3]);
  });

  test('per-period zhuloua p*.json samples merge to numbered rooms', () {
    final files = Directory('docs')
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'jwxt-cxkxjs-zhuloua-p\d+\.json$').hasMatch(f.path))
        .toList();
    expect(files, isNotEmpty, reason: 'expected at least one per-period sample');
    final byPeriod = <int, List<ClassroomSlot>>{};
    for (final file in files) {
      final match = RegExp(r'-p(\d+)\.json$').firstMatch(file.path);
      if (match == null) continue;
      final period = int.parse(match.group(1)!);
      Object? json;
      try {
        json = jsonDecode(file.readAsStringSync());
      } on Object {
        continue; // skip incomplete captures
      }
      final parsed = ClassroomQueryLogic.parseResult(
        json,
        query: const ClassroomQuery(campus: '兴庆校区', building: '主楼A'),
        start: period,
        end: period,
      );
      byPeriod[period] = parsed.rooms;
    }
    expect(byPeriod, isNotEmpty);
    final merged = ClassroomQueryLogic.mergeOccupancy(
      byPeriod,
      appearanceOnly: true,
    );
    expect(merged.length, greaterThanOrEqualTo(3));
    expect(
      merged.every((r) => RegExp(r'\d{2,}').hasMatch(r.room)),
      isTrue,
    );
    expect(merged.any((r) => r.room.contains('考试') || r.room.contains('通知')), isFalse);
    // p5 sample includes 主楼A-104 etc.
    if (byPeriod.containsKey(5)) {
      expect(merged.map((r) => r.room), contains('主楼A-104'));
    }
  });

  test('DeanWebView stealth script hides navigator.webdriver', () {
    expect(DeanWebViewNoticesFetcher.stealthScript, contains("navigator"));
    expect(DeanWebViewNoticesFetcher.stealthScript, contains('webdriver'));
    expect(DeanWebViewNoticesFetcher.stealthScript, contains('undefined'));
    expect(DeanWebViewNoticesFetcher.stealthScript, contains('callPhantom'));
  });

  test('live dean HTML parses all 9 notices including content.jsp', () {
    final html = File('docs/dean-notices-live.html').readAsStringSync();
    expect(DeanNoticeParser.looksLikeNoticeList(html), isTrue);
    final notices = DeanNoticeParser.parse(
      html,
      base: 'https://dean.xjtu.edu.cn/jxxx/jxtz2.htm',
    );
    expect(notices, hasLength(9));
    expect(
      notices.map((n) => n.title),
      containsAll([
        '[综合通知]关于组建中国青年志愿者西安交通大学第29届研究生支教团的通知',
        '[专业辅修]关于开展西安交通大学微专业增补报名的通知',
        '[考试安排]关于2026-2027学年第一学期补考（含缓考）有关事宜的通知',
        '[奖项申报]关于组织申报2026年度“人工智能+教育”智慧课程典型案例的通知',
        '[教改项目]关于开展首批西安交通大学“人工智能先导计划”未来教学综改项目开题工作的通知',
        '[课程安排]关于新学期新版考勤系统试运行的通知',
      ]),
    );
    expect(
      notices.any((n) => n.url!.contains('content.jsp') && n.url!.contains('wbnewsid=10453')),
      isTrue,
    );
    expect(
      notices.firstWhere((n) => n.title.contains('补考')).category,
      NoticeCategory.exam,
    );
    expect(
      notices.firstWhere((n) => n.title.contains('微专业')).category,
      NoticeCategory.course,
    );
    expect(
      notices.firstWhere((n) => n.title.contains('奖项申报')).publishedAt,
      DateTime(2026, 9, 14),
    );
  });
}
