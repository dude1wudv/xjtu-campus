import '../../../core/l10n/app_strings.dart';
import '../domain/classroom_repository.dart';
import '../domain/classroom_slot.dart';

class MockClassroomRepository implements ClassroomRepository {
  static const rooms = [
    ClassroomSlot(
      id: 'xq-main-a101',
      campus: '兴庆校区',
      building: '教学主楼',
      room: 'A-101',
      capacity: 180,
      freePeriods: [5, 6, 7, 8],
    ),
    ClassroomSlot(
      id: 'xq-main-b215',
      campus: '兴庆校区',
      building: '教学主楼',
      room: 'B-215',
      capacity: 60,
      freePeriods: [1, 2, 9, 10],
    ),
    ClassroomSlot(
      id: 'xq-zhongying-301',
      campus: '兴庆校区',
      building: '仲英楼',
      room: '3-301',
      capacity: 40,
      freePeriods: [3, 4, 5, 6],
    ),
    ClassroomSlot(
      id: 'yt-med-204',
      campus: '雁塔校区',
      building: '医学部教学楼',
      room: '204',
      capacity: 80,
      freePeriods: [1, 2, 3, 4],
    ),
    ClassroomSlot(
      id: 'ih-i19-105',
      campus: '创新港校区',
      building: '涵英楼',
      room: '1-105',
      capacity: 90,
      freePeriods: [7, 8, 9, 10],
    ),
    ClassroomSlot(
      id: 'xq-lib-s204',
      campus: '兴庆校区',
      building: '钱学森图书馆',
      room: '研讨室 204',
      capacity: 12,
      freePeriods: [1, 2, 3, 4, 5, 6],
      hasProjector: false,
    ),
  ];

  @override
  Future<ClassroomPageData> findFree(ClassroomQuery query) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final rooms = MockClassroomRepository.rooms.where((room) {
      if (query.campus != null && room.campus != query.campus) return false;
      if (query.building != null && room.building != query.building) {
        return false;
      }
      return true;
    }).toList();
    final campuses = <String>{
      for (final room in MockClassroomRepository.rooms) room.campus,
    }.toList();
    final buildings = <String>{
      for (final room in MockClassroomRepository.rooms)
        if (query.campus == null || room.campus == query.campus) room.building,
    }.toList();
    return ClassroomPageData(
      rooms: rooms,
      live: false,
      banner: AppStrings.mockBanner,
      campuses: campuses,
      buildingsForCampus: buildings,
      buildingCount: buildings.length,
    );
  }
}
