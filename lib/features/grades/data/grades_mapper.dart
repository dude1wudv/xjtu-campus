import '../domain/grade_record.dart';

/// Maps jwxt `xscjcx.do` JSON → domain. Never logs row payloads (PII).
abstract final class GradesMapper {
  static GradesSnapshot fromJson(Object? root) {
    final rows = _rowsOf(root);
    final records = <GradeRecord>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      final name = _str(map, 'KCM');
      if (name.isEmpty) continue;
      records.add(
        GradeRecord(
          termCode: _str(map, 'XNXQDM'),
          courseName: name,
          credit: _num(map, 'XF') ?? 0,
          gpaPoints: _num(map, 'XFJD'),
          score: _str(map, 'ZCJ'),
          usualScore: _opt(map, 'PSCJ'),
          midtermScore: _opt(map, 'QZCJ'),
          finalScore: _opt(map, 'QMCJ'),
          examType: _opt(map, 'KSLXDM_DISPLAY'),
          courseNature: _opt(map, 'KCXZDM_DISPLAY'),
          courseCode: _opt(map, 'KCH'),
        ),
      );
    }
    return GradesSnapshot(
      records: records,
      live: true,
      banner: '',
      groupedByTerm: groupByTerm(records),
    );
  }

  static Map<String, List<GradeRecord>> groupByTerm(List<GradeRecord> records) {
    final map = <String, List<GradeRecord>>{};
    for (final r in records) {
      final key = r.termCode.isEmpty ? '未知学期' : r.termCode;
      map.putIfAbsent(key, () => []).add(r);
    }
    final keys = map.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // newest term first
    return {for (final k in keys) k: map[k]!};
  }

  static List<dynamic> _rowsOf(Object? root) {
    if (root is! Map) return const [];
    final datas = root['datas'];
    if (datas is Map) {
      final block = datas['xscjcx'] ?? datas['cjcx'];
      if (block is Map && block['rows'] is List) {
        return block['rows'] as List;
      }
    }
    if (root['rows'] is List) return root['rows'] as List;
    return const [];
  }

  static String _str(Map<String, dynamic> m, String key) =>
      (m[key]?.toString() ?? '').trim();

  static String? _opt(Map<String, dynamic> m, String key) {
    final v = _str(m, key);
    return v.isEmpty ? null : v;
  }

  static double? _num(Map<String, dynamic> m, String key) {
    final raw = m[key];
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString().trim());
  }
}
