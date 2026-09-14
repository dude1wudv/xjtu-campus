import '../domain/exam_arrangement.dart';

/// Maps jwxt `wdksap.do` JSON → domain.
abstract final class ExamsMapper {
  static List<ExamArrangement> fromJson(Object? root) {
    final rows = _rowsOf(root);
    final out = <ExamArrangement>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      final name = _str(map, 'KCM');
      if (name.isEmpty) continue;
      out.add(
        ExamArrangement(
          termCode: _str(map, 'XNXQDM'),
          courseName: name,
          date: _str(map, 'KSRQ'),
          timeLabel: _str(map, 'KSSJMS'),
          location: _firstNonEmpty(map, const ['JASMC', 'KSMC', 'KSDD']),
          campus: _opt(map, 'XXXQMC'),
          courseCode: _opt(map, 'KCH'),
          seat: _opt(map, 'ZWH'),
        ),
      );
    }
    out.sort((a, b) {
      final d = a.date.compareTo(b.date);
      if (d != 0) return d;
      return a.timeLabel.compareTo(b.timeLabel);
    });
    return out;
  }

  static List<dynamic> _rowsOf(Object? root) {
    if (root is! Map) return const [];
    final datas = root['datas'];
    if (datas is Map) {
      final block = datas['wdksap'];
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

  static String _firstNonEmpty(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = _str(m, k);
      if (v.isNotEmpty) return v;
    }
    return '地点待定';
  }
}
