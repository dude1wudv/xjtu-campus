import 'grade_record.dart';

abstract class GradesRepository {
  Future<GradesSnapshot> load();
}
