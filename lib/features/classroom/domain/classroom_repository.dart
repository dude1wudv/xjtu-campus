import 'classroom_slot.dart';

abstract class ClassroomRepository {
  Future<ClassroomPageData> findFree(ClassroomQuery query);
}
