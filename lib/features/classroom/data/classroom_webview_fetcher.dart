import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/constants/campus_urls.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/classroom_slot.dart';
import 'classroom_codes.dart';

class ClassroomWebViewResult {
  const ClassroomWebViewResult({required this.rooms, this.maps});

  final List<ClassroomSlot> rooms;
  final ClassroomCodeMaps? maps;
}

/// Fetches kxjas empty-room JSON inside [HeadlessInAppWebView] so requests share
/// the CAS web-login cookie jar (same pattern as schedule workflow).
class ClassroomWebViewFetcher {
  ClassroomWebViewFetcher({this.timeout = const Duration(seconds: 50)});

  final Duration timeout;

  Future<ClassroomWebViewResult?> fetchFreeRooms(ClassroomQuery query) async {
    final completer = Completer<ClassroomWebViewResult?>();
    HeadlessInAppWebView? headless;
    Timer? timer;
    var finished = false;

    Future<void> complete(ClassroomWebViewResult? value) async {
      if (finished) return;
      finished = true;
      timer?.cancel();
      try {
        await headless?.dispose();
      } on Object catch (error) {
        AppLogger.warn('Classroom HeadlessInAppWebView dispose failed: $error');
      }
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    }

    timer = Timer(timeout, () {
      AppLogger.warn('WebView 空闲教室拉取超时 (${timeout.inSeconds}s)');
      unawaited(complete(null));
    });

    try {
      var fetchStarted = false;
      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(CampusUrls.jwxtKxjasIndex),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          thirdPartyCookiesEnabled: true,
          userAgent: CampusUrls.userAgent,
          cacheEnabled: true,
        ),
        onLoadStop: (controller, url) async {
          if (fetchStarted || finished) return;
          final uri = url == null ? null : Uri.tryParse(url.toString());
          if (uri != null && uri.host.contains('login')) {
            AppLogger.warn(
              'WebView kxjas 落到登录: ${uri.host}${uri.path}',
            );
            await complete(null);
            return;
          }
          fetchStarted = true;
          try {
            final result = await _runFetch(controller, query);
            await complete(result);
          } on Object catch (error) {
            AppLogger.warn('WebView evaluate/fetch 空闲教室失败: $error');
            await complete(null);
          }
        },
        onReceivedError: (controller, request, error) {
          AppLogger.warn('WebView kxjas 加载错误: ${error.description}');
        },
      );

      AppLogger.info('WebView 开始拉取空闲教室');
      await headless.run();
    } on Object catch (error) {
      AppLogger.warn('Classroom HeadlessInAppWebView 启动失败: $error');
      await complete(null);
    }

    return completer.future;
  }

  Future<ClassroomWebViewResult?> _runFetch(
    InAppWebViewController controller,
    ClassroomQuery query,
  ) async {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final campusName = query.campus ?? '';
    final buildingName = query.building ?? '';

    try {
      final asyncResult = await controller.callAsyncJavaScript(
        functionBody: r'''
          const getHeaders = {
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'X-Requested-With': 'XMLHttpRequest',
          };
          const postHeaders = {
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'X-Requested-With': 'XMLHttpRequest',
          };
          async function getText(url) {
            const response = await fetch(url, {
              method: 'GET',
              credentials: 'include',
              headers: getHeaders,
            });
            return await response.text();
          }
          async function postForm(url, body) {
            const response = await fetch(url, {
              method: 'POST',
              credentials: 'include',
              headers: postHeaders,
              body: body || '',
            });
            return await response.text();
          }
          function parseCode(text) {
            try {
              const json = JSON.parse(text);
              const rows = (json.datas && json.datas.code && json.datas.code.rows) || [];
              return rows.map(function(row) {
                const other = row.otherFields || {};
                return {
                  id: String(row.id),
                  name: String(row.name || ''),
                  campusCode: String(other.XXXQDM || other.xxxqdm || row.XXXQDM || ''),
                };
              });
            } catch (e) { return []; }
          }
          function occupancyFromRow(row) {
            const free = [];
            let saw = false;
            for (let p = 1; p <= 13; p++) {
              const occupy = row['ZY' + p];
              const kx = row['KX' + p];
              const jc = row['JC' + p] != null ? row['JC' + p] : (row['JCS' + p] != null ? row['JCS' + p] : row['J' + p]);
              const freeTokens = { '0':1, '':1, '空':1, '空闲':1, 'false':1, 'n':1, 'N':1, '-':1, '无':1 };
              function isOcc(v) {
                if (v === null || v === undefined) return false;
                const s = String(v).trim();
                return !freeTokens[s];
              }
              if (occupy !== undefined && occupy !== null) {
                saw = true;
                if (!isOcc(occupy)) free.push(p);
              } else if (kx !== undefined && kx !== null) {
                saw = true;
                const s = String(kx).trim();
                if (s === '1' || s === '空闲' || s === '空' || s === 'true' || s === 'Y') free.push(p);
              } else if (jc !== undefined && jc !== null) {
                saw = true;
                if (!isOcc(jc)) free.push(p);
              }
            }
            if (saw) return free;
            const list = row.KXJC || row.KXJCS || row.kxjc;
            if (list) {
              const text = Array.isArray(list) ? list.join(',') : String(list);
              const nums = text.match(/\d+/g) || [];
              return nums.map(function(n){ return parseInt(n, 10); }).filter(function(n){ return n >= 1 && n <= 13; });
            }
            const mask = row.KB || row.ZYQK || row.KXQK;
            if (mask && /^[01]+$/.test(String(mask)) && String(mask).length >= 11) {
              const s = String(mask);
              const out = [];
              for (let i = 0; i < Math.min(s.length, 13); i++) {
                if (s.charAt(i) === '0') out.push(i + 1);
              }
              return out;
            }
            return null;
          }
          function roomNameFromRow(row) {
            const keys = ['JASMC','jasmc','JASH','jash','JASDM_DISPLAY','jasdm_display'];
            for (const key of keys) {
              const v = row[key] != null ? String(row[key]).trim() : '';
              if (v) return v;
            }
            return '';
          }
          function isNormalTeachingRoom(row) {
            const name = roomNameFromRow(row);
            if (!name) return false;
            const reject = ['考试','通知','测试专用','非教室','仓库','厕所','卫生间','走廊','电梯'];
            for (const needle of reject) {
              if (name.indexOf(needle) >= 0) return false;
            }
            const typeLabel = String(row.JASLXDM_DISPLAY || row.jaslxdm_display || row.JASLXMC || row.jaslxmc || '');
            for (const needle of reject) {
              if (typeLabel.indexOf(needle) >= 0) return false;
            }
            if (typeLabel.indexOf('办公室') >= 0 || typeLabel.indexOf('值班室') >= 0) return false;
            if (!/\d{2,}/.test(name)) return false;
            return true;
          }
          function parseRooms(text, start, end) {
            const json = JSON.parse(text);
            const rows = (json.datas && json.datas.cxkxjs && json.datas.cxkxjs.rows) || [];
            const rooms = [];
            let hasOcc = false;
            for (const row of rows) {
              if (!isNormalTeachingRoom(row)) continue;
              const name = roomNameFromRow(row);
              let free;
              if (start === end) {
                free = [start];
              } else {
                const occ = occupancyFromRow(row);
                if (occ) hasOcc = true;
                free = occ || (function() {
                  const list = [];
                  for (let p = start; p <= end; p++) list.push(p);
                  return list;
                })();
              }
              rooms.push({
                campus: String(row.XXXQDM_DISPLAY || campusName || ''),
                building: String(row.JXLDM_DISPLAY || buildingName || ''),
                room: name,
                capacity: parseInt(row.SKZWS, 10) || 0,
                freePeriods: free,
              });
            }
            return { rooms: rooms, hasOcc: hasOcc };
          }
          async function queryRange(campusCode, buildingCode, start, end) {
            let body = 'XXXQDM=' + encodeURIComponent(campusCode) +
              '&KXRQ=' + encodeURIComponent(date) +
              '&KSJC=' + encodeURIComponent(String(start)) +
              '&JSJC=' + encodeURIComponent(String(end)) +
              '&pageSize=500&pageNumber=1';
            if (buildingCode) {
              body += '&JXLDM=' + encodeURIComponent(buildingCode);
            }
            const text = await postForm(emptyRoomUrl, body);
            return parseRooms(text, start, end);
          }
          async function occupancy(campusCode, buildingCode) {
            // KSJC=1&JSJC=11 only returns rooms free the entire day.
            // Always fan out per period; free = periods where room appeared.
            const full = await queryRange(campusCode, buildingCode, 1, 11);
            const byId = {};
            function consider(room, periods) {
              const id = room.campus + '|' + room.building + '|' + room.room;
              if (!byId[id]) {
                byId[id] = {
                  campus: room.campus,
                  building: room.building,
                  room: room.room,
                  capacity: room.capacity,
                  free: {},
                };
              }
              if (room.capacity && !byId[id].capacity) byId[id].capacity = room.capacity;
              for (const p of periods) byId[id].free[p] = true;
            }
            for (const room of full.rooms) {
              consider(room, [1,2,3,4,5,6,7,8,9,10,11]);
            }
            async function pool(items, limit, fn) {
              let i = 0;
              async function worker() {
                while (i < items.length) {
                  const idx = i++;
                  await fn(items[idx]);
                }
              }
              const n = Math.min(limit, items.length);
              await Promise.all(Array.from({length: n}, function() { return worker(); }));
            }
            const periods = [1,2,3,4,5,6,7,8,9,10,11];
            await pool(periods, 5, async function(p) {
              const slice = await queryRange(campusCode, buildingCode, p, p);
              for (const room of slice.rooms) consider(room, [p]);
            });
            return Object.keys(byId).map(function(id) {
              const item = byId[id];
              const freePeriods = Object.keys(item.free).map(function(k){ return parseInt(k, 10); }).sort(function(a,b){ return a-b; });
              return {
                campus: item.campus,
                building: item.building,
                room: item.room,
                capacity: item.capacity,
                freePeriods: freePeriods,
              };
            });
          }

          const campusText = await getText(campusCodeUrl);
          const buildingText = await getText(buildingCodeUrl);
          const campuses = parseCode(campusText);
          const buildings = parseCode(buildingText);
          if (!campuses.length || !buildings.length) {
            return JSON.stringify({ ok: false, reason: 'missing_codes' });
          }
          function campusIdOf(name) {
            if (!name) return null;
            for (const row of campuses) { if (row.name === name) return row.id; }
            for (const row of campuses) {
              if (row.name.indexOf(name) >= 0 || name.indexOf(row.name.replace('校区','')) >= 0) return row.id;
            }
            return null;
          }
          function buildingsFor(name) {
            const cid = campusIdOf(name);
            if (!cid) return buildings;
            const filtered = buildings.filter(function(b) { return b.campusCode === cid; });
            return filtered.length ? filtered : buildings;
          }
          function buildingOf(name, campus) {
            if (!name) return null;
            const cid = campusIdOf(campus);
            const exact = buildings.filter(function(b) { return b.name === name; });
            if (cid) {
              for (const b of exact) { if (b.campusCode === cid) return b; }
            }
            return exact[0] || null;
          }

          let rooms = [];
          if (buildingName) {
            const b = buildingOf(buildingName, campusName);
            const campusCode = (b && b.campusCode) || campusIdOf(campusName) || campuses[0].id;
            if (!b) {
              return JSON.stringify({ ok: false, reason: 'unknown_building', campuses: campuses, buildings: buildings });
            }
            rooms = await occupancy(campusCode, b.id);
          } else {
            const campusCodes = campusName ? [campusIdOf(campusName) || campuses[0].id] : campuses.map(function(c){ return c.id; });
            const seen = {};
            for (const campusCode of campusCodes) {
              if (!campusCode) continue;
              let batch = await occupancy(campusCode, '');
              const bset = {};
              for (const room of batch) { if (room.building) bset[room.building] = true; }
              if (Object.keys(bset).length < 2) {
                const campusObj = campuses.filter(function(c){ return c.id === campusCode; })[0];
                const targets = buildingsFor(campusObj ? campusObj.name : campusName);
                batch = [];
                await (async function() {
                  let i = 0;
                  async function worker() {
                    while (i < targets.length) {
                      const idx = i++;
                      const extra = await occupancy(targets[idx].campusCode || campusCode, targets[idx].id);
                      batch = batch.concat(extra);
                    }
                  }
                  const n = Math.min(5, targets.length);
                  await Promise.all(Array.from({length: n}, function() { return worker(); }));
                })();
              }
              for (const room of batch) {
                const id = room.campus + '|' + room.building + '|' + room.room;
                if (!seen[id]) { seen[id] = true; rooms.push(room); }
              }
            }
          }
          return JSON.stringify({
            ok: true,
            campuses: campuses,
            buildings: buildings,
            rooms: rooms,
          });
        ''',
        arguments: {
          'campusCodeUrl': CampusUrls.jwxtCampusCode,
          'buildingCodeUrl': CampusUrls.jwxtBuildingCode,
          'emptyRoomUrl': CampusUrls.jwxtEmptyRoom,
          'campusName': campusName,
          'buildingName': buildingName,
          'date': date,
        },
      );
      if (asyncResult?.error != null &&
          asyncResult!.error.toString().trim().isNotEmpty) {
        AppLogger.warn(
          'classroom callAsyncJavaScript error: ${asyncResult.error}',
        );
        return null;
      }
      final value = asyncResult?.value;
      final raw = value is String ? value : value?.toString();
      if (raw == null || raw.trim().isEmpty || raw == 'null') {
        return null;
      }
      return _parseBundle(raw, query: query);
    } on Object catch (error) {
      AppLogger.warn('classroom callAsyncJavaScript 不可用: $error');
      return null;
    }
  }

  ClassroomWebViewResult? _parseBundle(
    String raw, {
    required ClassroomQuery query,
  }) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object {
      AppLogger.warn('WebView 空闲教室 bundle 非 JSON');
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['ok'] != true) {
      AppLogger.warn('WebView 空闲教室失败: ${decoded['reason']}');
      return null;
    }
    ClassroomCodeMaps? maps;
    final campusRows = decoded['campuses'];
    final buildingRows = decoded['buildings'];
    if (campusRows is List && buildingRows is List) {
      maps = ClassroomCodeMaps(
        campuses: [
          for (final row in campusRows)
            if (row is Map)
              ClassroomCode(
                id: '${row['id']}',
                name: '${row['name']}',
                campusCode: null,
              ),
        ],
        buildings: [
          for (final row in buildingRows)
            if (row is Map)
              ClassroomCode(
                id: '${row['id']}',
                name: '${row['name']}',
                campusCode: '${row['campusCode'] ?? ''}'.isEmpty
                    ? null
                    : '${row['campusCode']}',
              ),
        ],
      );
    }

    final roomsRaw = decoded['rooms'];
    final rooms = <ClassroomSlot>[];
    if (roomsRaw is List) {
      for (final item in roomsRaw) {
        if (item is! Map) continue;
        final name = item['room']?.toString() ?? '';
        if (name.isEmpty ||
            name.contains('测试专用') ||
            name.contains('考试') ||
            name.contains('通知') ||
            !RegExp(r'\d{2,}').hasMatch(name)) {
          continue;
        }
        final campus = item['campus']?.toString() ?? query.campus ?? '';
        final building = item['building']?.toString() ?? query.building ?? '';
        final freeRaw = item['freePeriods'];
        final free = <int>[];
        if (freeRaw is List) {
          for (final value in freeRaw) {
            final period = value is int ? value : int.tryParse('$value');
            if (period != null) free.add(period);
          }
        }
        rooms.add(
          ClassroomSlot(
            id: '$campus|$building|$name',
            campus: campus,
            building: building,
            room: name,
            capacity: int.tryParse(item['capacity']?.toString() ?? '') ?? 0,
            freePeriods: free,
          ),
        );
      }
    }
    AppLogger.info('WebView 空闲教室解析 ${rooms.length} 间');
    return ClassroomWebViewResult(rooms: rooms, maps: maps);
  }
}
