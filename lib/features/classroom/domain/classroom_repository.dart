import 'classroom_slot.dart';

abstract class ClassroomRepository {
  Future<List<ClassroomSlot>> findFree(ClassroomQuery query);
}
