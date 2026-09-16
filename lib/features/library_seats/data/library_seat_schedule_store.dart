import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/library_seat.dart';

class LibrarySeatScheduleStore {
  LibrarySeatScheduleStore([SharedPreferences? prefs]) : _prefsOverride = prefs;

  static const _key = 'library_seats.schedule.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async {
    final o = _prefsOverride;
    if (o != null) return o;
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<LibrarySeatScheduleConfig?> load() async {
    final prefs = await _ensure();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      return LibrarySeatScheduleConfig.fromJson(
        Map<String, dynamic>.from(map),
      );
    } on Object {
      return null;
    }
  }

  Future<void> save(LibrarySeatScheduleConfig config) async {
    final prefs = await _ensure();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }

  Future<void> clear() async {
    final prefs = await _ensure();
    await prefs.remove(_key);
  }
}
