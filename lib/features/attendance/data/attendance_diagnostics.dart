import 'dart:convert';
import 'package:flutter/foundation.dart';

/// In-memory protocol metadata only. Never retain response values, headers,
/// query strings, cookies, tokens, student IDs, or raw JavaScript errors.
abstract final class AttendanceDiagnostics {
  static final revision = ValueNotifier<int>(0);
  static final _events = <Map<String, Object?>>[];
  static const _keys = {
    'success','code','data','datas','result','list','rows','records','items','total',
    'totalCount','current','pageSize','bh','name','startdate','enddate','weeks',
    'classWaterBean','accountBean','subjectBean','buildBean','roomBean',
    'calendarBean','stuClassBean','status','checkdate','startJc','endJc','week',
    'sName','subjectname','subjectSName','teachNameList','roomnum','termNo',
    'message','msg','date','startTime','endTime','sBh','termString','teacher',
  };
  static Object shape(Object? value, [int depth = 0]) {
    if (value == null) return 'null';
    if (depth >= 6) return value is Map ? 'object' : value is List ? 'array' : value is num ? 'number' : 'scalar';
    if (value is Map) return {
      for (final key in _keys) if (value.containsKey(key)) key: shape(value[key], depth + 1),
      '_otherFieldCount': value.keys.where((key) => !_keys.contains(key)).length,
    };
    if (value is List) return {'length': value.length, 'first': value.isEmpty ? 'empty' : shape(value.first, depth + 1)};
    return value is bool ? 'boolean' : value is num ? 'number' : 'string';
  }
  static String safeUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.host == 'xjtu.edu.cn' || uri.host.endsWith('.xjtu.edu.cn'))) return '[other origin]';
    // Only API/auth route segments; all unrecognized page paths are omitted.
    final path = uri.path;
    if (uri.host == 'login.xjtu.edu.cn') {
      final stage = path.endsWith('/cas/login') ? 'cas-login'
          : path.endsWith('/cas/logout') ? 'cas-logout' : 'authentication-page';
      return '${uri.host}/[$stage]';
    }
    final markers = ['/attendance-student/', '/berserker-auth/', '/api/'];
    final marker = markers.map(path.indexOf).where((index) => index >= 0).fold<int>(-1, (a, b) => a < 0 || b < a ? b : a);
    if (marker >= 0) {
      final parts = path.substring(marker).split('/').where((s) => s.isNotEmpty).take(4)
          .map((s) => RegExp(r'^[A-Za-z-]{1,48}$').hasMatch(s) ? s : '[id]');
      return '${uri.host}/${parts.join('/')}';
    }
    if (path.contains('/openplatform/oauth/authorize')) return '${uri.host}/openplatform/oauth/authorize';
    if (path.contains('/casReturn')) return '${uri.host}/[attendance callback]';
    return '${uri.host}/[page]';
  }
  static void add(String phase, {String? url, int? status, Object? response, String? method}) {
    _events.add({'time': DateTime.now().toIso8601String(), 'phase': phase,
      if (url != null) 'route': safeUrl(url),
      if (method != null) 'method': method == 'POST' ? 'POST' : 'GET',
      if (status != null) 'status': status,
      if (response != null) 'schema': shape(response)});
    if (_events.length > 80) _events.removeAt(0);
    revision.value++;
  }
  static void browser(Map raw) {
    // The script supplies only structural metadata. Sanitize it again natively.
    final schema = raw['schema'];
    _events.add({'time': DateTime.now().toIso8601String(), 'phase': 'browser-response',
      'route': safeUrl('${raw['url'] ?? ''}'),
      'method': raw['method'] == 'POST' ? 'POST' : 'GET',
      'status': raw['status'] is num ? raw['status'] : 0,
      'schema': _filterSchema(schema)});
    if (_events.length > 80) _events.removeAt(0);
    revision.value++;
  }
  static Object _filterSchema(Object? schema, [int depth = 0]) {
    if (depth > 6) return 'depth-limit';
    if (schema is Map) return {for (final key in schema.keys)
      if (_keys.contains(key) || key == '_item') '$key': _filterSchema(schema[key], depth + 1)};
    return const ['null','object','array','boolean','number','string','empty'].contains(schema) ? schema! : 'omitted';
  }
  static String export() => const JsonEncoder.withIndent('  ').convert({
    'format': 'attendance-diagnostics-v1', 'events': _events});
  static void clear() { _events.clear(); revision.value++; }

  static const script = r'''
(() => {
  if (window.__campusAttendanceTrace) return;
  window.__campusAttendanceTrace = true;
  const keys = new Set(['success','code','data','datas','result','list','rows','records','items','total','totalCount','current','pageSize','bh','name','startdate','enddate','weeks','classWaterBean','accountBean','subjectBean','buildBean','roomBean','calendarBean','stuClassBean','status','checkdate','startJc','endJc','week','sName','subjectname','subjectSName','teachNameList','roomnum','termNo','message','msg','date','startTime','endTime','sBh','termString','teacher']);
  function shape(v, d=0) {
    if(v === null || v === undefined) return 'null';
    if(d >= 5) return Array.isArray(v) ? 'array' : typeof v;
    if(Array.isArray(v)) return {_item: v.length ? shape(v[0],d+1) : 'empty'};
    if(typeof v === 'object') {
      const o = {}; for(const k of keys) if(Object.prototype.hasOwnProperty.call(v,k)) o[k] = shape(v[k],d+1); return o;
    }
    return typeof v;
  }
  function emit(url, method, status, data) {
    try {
      const u = new URL(url, location.href);
      if(!u.hostname.endsWith('.xjtu.edu.cn') || !['/attendance-student/','/berserker-auth/','/api/'].some(p => u.pathname.includes(p))) return;
      window.flutter_inappwebview?.callHandler('attendanceTrace', {
        url: u.origin+u.pathname, method: String(method).toUpperCase(), status, schema: shape(data)
      });
    } catch (_) {}
  }
  const fetchOriginal = window.fetch;
  window.fetch = function(input, init) {
    return fetchOriginal.apply(this, arguments).then(response => {
      const type = response.headers.get('content-type') || '';
      if(!type.includes('json')) emit(response.url, init?.method || input?.method || 'GET', response.status, 'non-json');
      if(type.includes('json')) response.clone().text().then(text => {
        if(text.length <= 2000000) { try { emit(response.url, init?.method || input?.method || 'GET', response.status, JSON.parse(text)); } catch (_) {} }
      }).catch(()=>{});
      return response;
    });
  };
  const openOriginal = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method,url) {
    this.__attendanceRequest = {method,url}; return openOriginal.apply(this,arguments);
  };
  const sendOriginal = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function() {
    this.addEventListener('load', () => {
      try {
        const r = this.__attendanceRequest;
        if(!r) return;
        const data = this.responseType === 'json' ? this.response :
          (this.responseText.length <= 2000000 ? (() => { try { return JSON.parse(this.responseText); } catch (_) { return 'non-json'; } })() : null);
        emit(this.responseURL || r.url, r.method, this.status, data);
      } catch (_) {}
    }, {once:true});
    return sendOriginal.apply(this,arguments);
  };
})();
''';
}
