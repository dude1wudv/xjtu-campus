import 'exam_arrangement.dart';

abstract class ExamsRepository {
  Future<ExamsSnapshot> load({String? termCode});
}
