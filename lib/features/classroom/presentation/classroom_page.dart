import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/classroom_slot.dart';

class ClassroomFilter extends Notifier<ClassroomQuery> {
  @override
  ClassroomQuery build() => const ClassroomQuery();

  void setCampus(String? campus) =>
      state = ClassroomQuery(campus: campus, building: null, period: state.period);

  void setBuilding(String? building) =>
      state = ClassroomQuery(campus: state.campus, building: building, period: state.period);

  void setPeriod(int? period) =>
      state = ClassroomQuery(
        campus: state.campus,
        building: state.building,
        period: period,
      );
}

final classroomFilterProvider =
    NotifierProvider<ClassroomFilter, ClassroomQuery>(ClassroomFilter.new);

final freeClassroomsProvider = FutureProvider<ClassroomPageData>((ref) {
  ref.watch(authControllerProvider.select((state) => state.user.sessionToken));
  final query = ref.watch(classroomFilterProvider);
  return ref.watch(classroomRepositoryProvider).findFree(query);
});

class ClassroomPage extends ConsumerWidget {
  const ClassroomPage({super.key});

  static const campuses = ['兴庆校区', '雁塔校区', '创新港校区', '曲江校区'];
  static const buildings = [
    '主楼A',
    '主楼B',
    '主楼C',
    '主楼D',
    '仲英楼',
    '教学主楼',
    '钱学森图书馆',
    '医学部教学楼',
    '涵英楼',
    '1号巨构',
    '教学楼',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(classroomFilterProvider);
    final rooms = ref.watch(freeClassroomsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.classroomTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                rooms.when(
                  data: (data) =>
                      DataSourceBanner(live: data.live, message: data.banner),
                  loading: () => const MockDataBanner(),
                  error: (_, _) => const MockDataBanner(),
                ),
                const SizedBox(height: 8),
                const Text(AppStrings.classroomSubtitle),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DropdownButton<String?>(
                      value: filter.campus,
                      hint: const Text(AppStrings.allCampuses),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text(AppStrings.allCampuses),
                        ),
                        for (final campus in campuses)
                          DropdownMenuItem(value: campus, child: Text(campus)),
                      ],
                      onChanged: (value) => ref
                          .read(classroomFilterProvider.notifier)
                          .setCampus(value),
                    ),
                    DropdownButton<String?>(
                      value: filter.building,
                      hint: const Text(AppStrings.allBuildings),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text(AppStrings.allBuildings),
                        ),
                        for (final building in buildings)
                          DropdownMenuItem(
                            value: building,
                            child: Text(building),
                          ),
                      ],
                      onChanged: (value) => ref
                          .read(classroomFilterProvider.notifier)
                          .setBuilding(value),
                    ),
                    DropdownButton<int?>(
                      value: filter.period,
                      hint: const Text(AppStrings.allSlots),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text(AppStrings.allSlots),
                        ),
                        for (var period = 1; period <= 11; period++)
                          DropdownMenuItem(
                            value: period,
                            child: Text('第$period节'),
                          ),
                      ],
                      onChanged: (value) => ref
                          .read(classroomFilterProvider.notifier)
                          .setPeriod(value),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: rooms,
              onRetry: () => ref.invalidate(freeClassroomsProvider),
              builder: (data) {
                final items = data.rooms;
                if (items.isEmpty) {
                  return const EmptyHint(
                    icon: Icons.meeting_room_outlined,
                    text: AppStrings.emptyClassrooms,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final room = items[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.door_front_door_outlined),
                        title: Text('${room.building} ${room.room}'),
                        subtitle: Text(
                          '${room.campus} · ${AppStrings.seats} ${room.capacity} · ${room.periodText}',
                        ),
                        trailing: room.hasProjector
                            ? const Text(AppStrings.freeNow)
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
