import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/network/webvpn_url.dart';

/// In-memory protocol metadata only. Never retain response values, headers,
/// query strings, cookies, tokens, student IDs, or raw JavaScript errors.
abstract final class AttendanceDiagnostics {
  static final revision = ValueNotifier<int>(0);
  static final _events = <Map<String, Object?>>[];
  static const protocolRevision = 'attendance-v2-20260917';
  static Map<String, Object?> build = {};
  // Field names, never values. Reject dynamic IDs, emails and oversized keys.
  static bool _field(Object? key) => key is String &&
      RegExp(r'^[A-Za-z_][A-Za-z_0-9]{0,63}$').hasMatch(key) &&
      !RegExp(r'[0-9]{5,}').hasMatch(key);
  static String _method(Object? value) =>
      const ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS']
          .contains(value) ? '$value' : 'OTHER';
  static bool _knownCode(Object? value) =>
      const {'0', '200', '401', '403', '404', '405', '500'}.contains('$value');
  static Object shape(Object? value, [int depth = 0]) {
    if (value == null) return 'null';
    if (depth >= 6) return value is Map ? 'object' : value is List ? 'array' : value is num ? 'number' : 'scalar';
    if (value is Map) return {
      for (final key in value.keys.where(_field).take(80))
        '$key': shape(value[key], depth + 1),
    };
    if (value is List) return {'length': value.length, 'first': value.isEmpty ? 'empty' : shape(value.first, depth + 1)};
    return value is bool ? 'boolean' : value is num ? 'number' : 'string';
  }
  static const _newHosts = ['bk-kq.xjtu.edu.cn', 'kq.xjtu.edu.cn'];
  static String safeUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.host == 'xjtu.edu.cn' || uri.host.endsWith('.xjtu.edu.cn'))) return '[other origin]';
    // Only API/auth route segments; all unrecognized page paths are omitted.
    var path = uri.path;
    String? newHost;
    for (final host in _newHosts) {
      if (uri.host == host) newHost = host;
      for (final scheme in ['https', 'http']) {
        final prefix = Uri.parse(WebVpnUrl.convert('$scheme://$host/')).path;
        if (uri.host == 'webvpn.xjtu.edu.cn' && path.startsWith(prefix)) {
          path = '/${path.substring(prefix.length)}';
          newHost = host;
          break;
        }
      }
    }
    if (newHost != null) {
      final parts = path.split('/').where((s) => s.isNotEmpty).take(10).map((part) =>
        RegExp(r'^[A-Za-z][A-Za-z_-]{0,39}$').hasMatch(part) &&
        !RegExp(r'^[a-fA-F]{16,}$').hasMatch(part) ? part : '[id]');
      return '$newHost/${parts.join('/')}';
    }
    if (path.endsWith('/studentpc/student/entry')) return '${uri.host}/studentpc/student/entry';
    if (path.endsWith('/studentpc/workbench')) return '${uri.host}/studentpc/workbench';
    if (uri.host == 'login.xjtu.edu.cn') {
      // Keep fixed CAS route names and structural errors while stripping
      // session IDs and arbitrary path segments. Never export query values.
      const routes = {'cas', 'login', 'logout', 'authserver', 'sso', 'index',
        'index.html', 'login.html', 'loginSubmit', 'serviceValidate', 'error'};
      final segments = path.split('/').take(8).map((part) {
        if (part.isEmpty) return '';
        final base = part.split(';').first;
        final safe = routes.contains(base) ? base : '[segment]';
        return part.contains(';') ? '$safe;[session]' : safe;
      }).join('/');
      return '${uri.host}$segments';
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
      if (method != null) 'method': _method(method),
      if (status != null) 'status': status,
      if (response is Map && _knownCode(response['code']))
        'businessCode': '${response['code']}',
      if (response != null) 'schema': shape(response)});
    if (_events.length > 80) _events.removeAt(0);
    revision.value++;
  }
  static void browser(Map raw) {
    const phases = {'browser-response', 'script-ready', 'bridge-ready',
      'request-failed', 'response-unreadable'};
    if (!phases.contains(raw['phase'])) return;
    _events.add({'time': DateTime.now().toIso8601String(), 'phase': raw['phase'],
      'route': safeUrl('${raw['url'] ?? ''}'),
      'frame': raw['frame'] == 'child' ? 'child' : 'main',
      'method': _method(raw['method']),
      if (raw['status'] is int) 'status': raw['status'],
      if (_knownCode(raw['businessCode'])) 'businessCode': '${raw['businessCode']}',
      if (raw['schema'] != null) 'schema': _filterSchema(raw['schema']),
      if (raw['request'] != null) 'request': _filterSchema(raw['request']),
    });
    if (_events.length > 80) _events.removeAt(0);
    revision.value++;
  }
  static Object _filterSchema(Object? schema, [int depth = 0]) {
    if (depth > 6) return 'depth-limit';
    if (schema is Map) return {for (final key in schema.keys.where(_field).take(80))
      '$key': _filterSchema(schema[key], depth + 1)};
    return const ['null','object','array','boolean','number','string','empty',
      'non-json','unreadable','omitted'].contains(schema) ? schema! : 'omitted';
  }
  static String export() => const JsonEncoder.withIndent('  ').convert({
    'format': protocolRevision, 'build': build, 'events': _events});
  static void clear() { _events.clear(); revision.value++; }

  static String get script => '(() => { const origins = ${jsonEncode([
    for (final host in [..._newHosts, 'yjskq.xjtu.edu.cn']) ...[
      'https://$host/', 'http://$host/',
      WebVpnUrl.convert('https://$host/'), WebVpnUrl.convert('http://$host/'),
    ],
  ])};' + r'''
  function allowed(url) {
    try { return origins.some(origin => new URL(url, location.href).href.startsWith(origin)); }
    catch (_) { return false; }
  }
  if (!allowed(location.href)) return;
  if (window.__campusAttendanceTrace) {
    window.__campusAttendanceTrace(); return;
  }
  const field = k => /^[A-Za-z_][A-Za-z_0-9]{0,63}$/.test(k) && !/[0-9]{5,}/.test(k);
  function shape(v, d=0) {
    if(v === null || v === undefined) return 'null';
    if(d >= 5) return Array.isArray(v) ? 'array' : typeof v;
    if(Array.isArray(v)) return {_item: v.length ? shape(v[0],d+1) : 'empty'};
    if(typeof v === 'object') {
      const o = {}; for(const k of Object.keys(v).filter(field).slice(0,80)) o[k] = shape(v[k],d+1); return o;
    }
    return typeof v;
  }
  const pending = [];
  let flushing = false;
  async function flush() {
    if (flushing || !window.flutter_inappwebview?.callHandler) return;
    flushing = true;
    try {
      while (pending.length) {
        const next = pending[0];
        const ack = await window.flutter_inappwebview.callHandler('attendanceTrace', next);
        if (ack !== true) break;
        if (pending[0] === next) pending.shift();
      }
    } catch (_) {} finally { flushing = false; }
  }
  function emit(phase, url=location.href, method='GET', status, schema, request) {
    try {
      const u = new URL(url, location.href);
      // Observe other campus API hosts, but never authentication page bodies.
      if (!(u.hostname.endsWith('.xjtu.edu.cn')) ||
          ['login.xjtu.edu.cn','org.xjtu.edu.cn'].includes(u.hostname)) return;
      pending.push({phase, url:u.origin+u.pathname, method:String(method).toUpperCase(),
        status, schema, request, frame:window === window.top ? 'main' : 'child'});
      if (pending.length > 40) pending.shift();
      flush();
    } catch (_) {}
  }
  function headerShape(headers) {
    const result = {};
    try { new Headers(headers).forEach((_,key) => {
      const name = key.replace(/-/g,'_');
      if(field(name)) result[name]='string';
    }); } catch (_) {}
    return result;
  }
  function requestShape(url, body) {
    let query = {}, payload = 'omitted';
    try { new URL(url,location.href).searchParams.forEach((v,k) => { if(field(k)) query[k]='string'; }); } catch (_) {}
    if(typeof body === 'string' && body.length <= 2000000) {
      try { payload=shape(JSON.parse(body)); } catch (_) {
        payload={}; new URLSearchParams(body).forEach((v,k)=>{if(field(k)) payload[k]='string';});
      }
    }
    return {query, body:payload};
  }
  window.__campusAttendanceTrace = () => { emit('script-ready'); flush(); };
  window.addEventListener('flutterInAppWebViewPlatformReady', () => emit('bridge-ready'));
  // A load-stop reinjection and enabling diagnostics retry queued messages.
  window.addEventListener('load', flush);
  const fetchOriginal = window.fetch;
  if (typeof fetchOriginal === 'function') window.fetch = function(input, init) {
    const url = typeof input === 'string' ? input : input?.url;
    const method = init?.method || input?.method || 'GET';
    const request = requestShape(url,init?.body);
    request.headers=headerShape(init?.headers || input?.headers);
    return fetchOriginal.apply(this, arguments).then(response => {
      const type = response.headers.get('content-type') || '';
      if(type.includes('json')) response.clone().text().then(text => {
        try { emit('browser-response',response.url,method,response.status,
          text.length <= 2000000 ? shape(JSON.parse(text)) : 'omitted',request); }
        catch (_) { emit('response-unreadable',response.url,method,response.status); }
      }).catch(()=>emit('response-unreadable',response.url,method,response.status));
      else emit('browser-response',response.url,method,response.status,'non-json',request);
      return response;
    }, error => { emit('request-failed',url,method); throw error; });
  };
  const openOriginal = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method,url) {
    this.__attendanceRequest = {method,url,headers:{}}; return openOriginal.apply(this,arguments);
  };
  const headerOriginal = XMLHttpRequest.prototype.setRequestHeader;
  XMLHttpRequest.prototype.setRequestHeader = function(name,value) {
    const safe = String(name).replace(/-/g,'_');
    if(this.__attendanceRequest && field(safe)) this.__attendanceRequest.headers[safe]='string';
    return headerOriginal.apply(this,arguments);
  };
  const sendOriginal = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function(body) {
    const r = this.__attendanceRequest;
    const request = requestShape(r?.url,body);
    request.headers=r?.headers || {};
    this.addEventListener('loadend', () => {
      if(!r) return;
      try {
        if(this.status === 0) { emit('request-failed',r.url,r.method); return; }
        let schema = 'non-json';
        if(this.responseType === 'json') schema=shape(this.response);
        else if(!this.responseType || this.responseType === 'text') {
          if(this.responseText.length > 2000000) schema='omitted';
          else { try { schema=shape(JSON.parse(this.responseText)); } catch (_) {} }
        }
        emit('browser-response',this.responseURL || r.url,r.method,this.status,schema,request);
      } catch (_) { emit('response-unreadable',r.url,r.method,this.status); }
    }, {once:true});
    return sendOriginal.apply(this,arguments);
  };
  emit('script-ready');
})();
''';
}
