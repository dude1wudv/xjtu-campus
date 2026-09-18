import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/campus_snapshot_loader.dart';
import '../../../core/cache/snapshot_cache.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/network/campus_connection.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/app_page_scaffold.dart';
import '../../../core/widgets/manual_refresh_button.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/classroom_codes.dart';
import '../domain/classroom_slot.dart';

class ClassroomFilter extends Notifier<ClassroomQuery> {
  @override
  ClassroomQuery build() => const ClassroomQuery();

  void setCampus(String? campus) => state = ClassroomQuery(
    campus: campus,
    building: null,
    period: state.period,
  );

  void setBuilding(String? building) => state = ClassroomQuery(
    campus: state.campus,
    building: building,
    period: state.period,
  );

  void setPeriod(int? period) => state = ClassroomQuery(
    campus: state.campus,
    building: state.building,
    period: period,
  );
}

final classroomFilterProvider =
    NotifierProvider<ClassroomFilter, ClassroomQuery>(ClassroomFilter.new);

class FreeClassroomsNotifier extends AsyncNotifier<ClassroomPageData> {
  Future<ClassroomPageData>? pending;
  @override
  Future<ClassroomPageData> build() async {
    var active = true;
    ref.onDispose(() => active = false);
    ref.watch(campusConnectionRevisionProvider);
    ref.watch(
      authControllerProvider.select(
        (state) =>
            '${state.initialized}|${state.user.studentId}|${state.user.sessionToken}|${state.user.isDemo}',
      ),
    );
    final campus = ref.watch(
      classroomFilterProvider.select((query) => query.campus),
    );
    final building = ref.watch(
      classroomFilterProvider.select((query) => query.building),
    );
    final result = await (pending = loadCampusSnapshot<ClassroomPageData>(
      ref: ref,
      service: 'classroom',
      demo: () => ref
          .read(mockClassroomRepositoryProvider)
          .findFree(ClassroomQuery(campus: campus, building: building)),
      key: SnapshotCache.scoped(
        SnapshotCache.classroom,
        ref.read(authControllerProvider).user.studentId,
        '${campus ?? ''}|${building ?? ''}',
      ),
      fromJson: ClassroomPageData.fromJson,
      toJson: (s) =>
          s.copyWith(queryCampus: campus, queryBuilding: building).toJson(),
      fetch: () async {
        if (!active) throw StateError('Sync superseded');
        final data = await ref
            .read(classroomRepositoryProvider)
            .findFree(ClassroomQuery(campus: campus, building: building));
        return data.copyWith(queryCampus: campus, queryBuilding: building);
      },
      isLive: (s) => s.live,
      markCached: (s, t) => s.asCached(
        t,
        banner:
            '${AppStrings.classroomCacheBanner} · ${AppStrings.updatedAtLabel(t)}',
      ),
      markRefreshFailed: (s, t) =>
          s.asCached(t, banner: AppStrings.cacheRefreshFailed),
      emit: (s) {
        if (active) state = AsyncData(s);
      },
    ));
    if (result.live && !result.fromCache) {
      return result.asFresh();
    }
    return result;
  }

  /// Revalidate from the network while retaining the last successful cache.
  Future<void> refresh({bool force = true}) async {
    ref.invalidateSelf();
    await future;
    await pending;
  }
}

/// Campus/building changes refetch; period is applied locally after a full-day parse.
final freeClassroomsProvider =
    AsyncNotifierProvider<FreeClassroomsNotifier, ClassroomPageData>(
      FreeClassroomsNotifier.new,
    );

class ClassroomPage extends ConsumerWidget {
  const ClassroomPage({super.key});

  static const fallbackCampuses = [
    '兴庆校区',
    '雁塔校区',
    '创新港校区',
    '曲江校区',
    '苏州校区',
    '海南创新中心',
  ];
  static const fallbackBuildings = [
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
    final liveCampuses = rooms.asData?.value.campuses ?? const <String>[];
    final liveBuildings =
        rooms.asData?.value.buildingsForCampus ?? const <String>[];
    final campusItems = liveCampuses.isNotEmpty
        ? liveCampuses
        : fallbackCampuses;
    final buildingItems = liveBuildings.isNotEmpty
        ? liveBuildings
        : fallbackBuildings;
    final campusValue = campusItems.contains(filter.campus)
        ? filter.campus
        : null;
    final buildingValue = buildingItems.contains(filter.building)
        ? filter.building
        : null;

    return AppPageScaffold(
      appBar: AppBar(
        title: const Text(AppStrings.classroomTitle),
        actions: [
          ManualRefreshButton(
            onRefresh: () =>
                ref.read(freeClassroomsProvider.notifier).refresh(force: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                rooms.when(
                  data: (data) => DataSourceBanner(
                    service: 'classroom',
                    onRetry: () => ref.invalidate(freeClassroomsProvider),
                    live: data.live,
                    message: data.banner,
                    fromCache: data.fromCache,
                    cachedAt: data.cachedAt,
                    fetchedAt: data.fetchedAt,
                  ),
                  loading: () => DataSourceBanner(
                    service: 'classroom',
                    onRetry: () => ref.invalidate(freeClassroomsProvider),
                  ),
                  error: (_, _) => DataSourceBanner(
                    service: 'classroom',
                    onRetry: () => ref.invalidate(freeClassroomsProvider),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(AppStrings.classroomSubtitle),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DropdownButton<String?>(
                      value: campusValue,
                      hint: const Text(AppStrings.allCampuses),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text(AppStrings.allCampuses),
                        ),
                        for (final campus in campusItems)
                          DropdownMenuItem(value: campus, child: Text(campus)),
                      ],
                      onChanged: (value) => ref
                          .read(classroomFilterProvider.notifier)
                          .setCampus(value),
                    ),
                    DropdownButton<String?>(
                      value: buildingValue,
                      hint: const Text(AppStrings.allBuildings),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text(AppStrings.allBuildings),
                        ),
                        for (final building in buildingItems)
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
            child: RefreshIndicator(
              onRefresh: () => ref
                  .read(freeClassroomsProvider.notifier)
                  .refresh(force: true),
              child: AsyncBody(
                value: rooms,
                onRetry: () => ref
                    .read(freeClassroomsProvider.notifier)
                    .refresh(force: true),
                builder: (data) {
                  final items = ClassroomQueryLogic.filterByPeriod(
                    data.rooms,
                    filter.period,
                  );
                  if (items.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        EmptyHint(
                          icon: Icons.meeting_room_outlined,
                          text: AppStrings.emptyClassrooms,
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: AppTokens.pagePadding,
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final room = items[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 8, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                leading: const Icon(
                                  Icons.door_front_door_outlined,
                                ),
                                title: Text('${room.building} ${room.room}'),
                                subtitle: Text(
                                  '${room.campus} · ${AppStrings.seats} ${room.capacity} · ${room.periodText}',
                                ),
                                trailing: room.freePeriods.isNotEmpty
                                    ? const Text(AppStrings.freeNow)
                                    : const Text('占用'),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  12,
                                  4,
                                ),
                                child: _PeriodStrip(room: room),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodStrip extends StatelessWidget {
  const _PeriodStrip({required this.room});

  final ClassroomSlot room;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var period = 1; period <= ClassroomSlot.dayLastPeriod; period++)
          _PeriodChip(period: period, free: room.freePeriods.contains(period)),
      ],
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.period, required this.free});

  final int period;
  final bool free;

  @override
  Widget build(BuildContext context) {
    final bg = free ? const Color(0xFFDDF4E4) : const Color(0xFFEDEDED);
    final fg = free ? AppColors.success : AppColors.inkSoft;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$period',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
