import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local JSON snapshot cache (stale-while-revalidate).
///
/// Only persist payloads that came from a live/successful fetch — callers must
/// gate writes with `live == true`. Privacy: data stays on-device; do not log
/// full grades or other sensitive payloads.
class SnapshotCache {
  SnapshotCache([SharedPreferences? prefs]) : _prefsOverride = prefs;

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  static const schedule = 'cache.v1.schedule';
  static const grades = 'cache.v1.grades';
  static const exams = 'cache.v1.exams';
  static const notices = 'cache.v1.notices';
  static const calendar = 'cache.v1.calendar';
  static const classroom = 'cache.v1.classroom';
  static const campusCard = 'cache.v1.campus_card';

  static const allKeys = [
    schedule,
    grades,
    exams,
    notices,
    calendar,
    classroom,
    campusCard,
  ];

  static String scoped(String key, String studentId, [String variant = '']) =>
      '$key.${Uri.encodeComponent(studentId)}.${Uri.encodeComponent(variant)}';

  Future<SharedPreferences> _ensurePrefs() async {
    final override = _prefsOverride;
    if (override != null) return override;
    return _prefs ??= await SharedPreferences.getInstance();
  }

  /// Envelope: `{ "savedAt": ISO8601, "payload": { ... } }`.
  Future<CachedEnvelope<Map<String, dynamic>>?> read(String key) async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final savedAtRaw = map['savedAt'];
      final payload = map['payload'];
      if (savedAtRaw is! String || payload is! Map) return null;
      final savedAt = DateTime.tryParse(savedAtRaw);
      if (savedAt == null) return null;
      return CachedEnvelope(
        savedAt: savedAt,
        payload: Map<String, dynamic>.from(payload),
      );
    } on Object {
      return null;
    }
  }

  Future<T?> readMapped<T>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  ) async {
    final envelope = await read(key);
    if (envelope == null) return null;
    try {
      final value = fromJson(envelope.payload);
      return value;
    } on Object {
      return null;
    }
  }

  Future<CachedEnvelope<T>?> readEnvelope<T>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  ) async {
    final envelope = await read(key);
    if (envelope == null) return null;
    try {
      return CachedEnvelope(
        savedAt: envelope.savedAt,
        payload: fromJson(envelope.payload),
      );
    } on Object {
      return null;
    }
  }

  Future<void> write(String key, Map<String, dynamic> payload) async {
    final prefs = await _ensurePrefs();
    final envelope = <String, dynamic>{
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    };
    await prefs.setString(key, jsonEncode(envelope));
  }

  Future<void> remove(String key) async {
    final prefs = await _ensurePrefs();
    await prefs.remove(key);
  }

  Future<void> clearAll() async {
    final prefs = await _ensurePrefs();
    for (final key in prefs.getKeys()) {
      if (allKeys.any((prefix) => key == prefix || key.startsWith('$prefix.'))) {
        await prefs.remove(key);
      }
    }
  }
}

class CachedEnvelope<T> {
  const CachedEnvelope({required this.savedAt, required this.payload});

  final DateTime savedAt;
  final T payload;
}
