import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached_snapshot_loader.dart';
import '../../../core/cache/snapshot_cache.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/course.dart';
import '../domain/schedule_repository.dart';

class ScheduleSnapshotNotifier extends AsyncNotifier<ScheduleSnapshot> {
  @override
  Future<ScheduleSnapshot> build() async {
    ref.watch(
      authControllerProvider.select(
        (state) => '${state.user.sessionToken}|${state.user.isDemo}',
      ),
    );
    final result = await loadWithCache<ScheduleSnapshot>(
      cache: ref.watch(snapshotCacheProvider),
      key: SnapshotCache.schedule,
      fromJson: ScheduleSnapshot.fromJson,
      toJson: (s) => s.toJson(),
      fetch: () => ref.read(scheduleRepositoryProvider).load(),
      isLive: (s) => s.live,
      markCached: (s, t) => s.asCached(t, banner: AppStrings.cacheBanner(t)),
      markRefreshFailed: (s, t) => s.asCached(
        t,
        banner: AppStrings.cacheRefreshFailed,
      ),
      emit: (s) => state = AsyncData(s),
    );
    if (result.live && !result.fromCache) {
      return result.asFresh(banner: result.banner);
    }
    return result;
  }

  /// Clear SnapshotCache for this key then rebuild (true network path).
  Future<void> refresh({bool force = true}) async {
    if (force) {
      await ref.read(snapshotCacheProvider).remove(SnapshotCache.schedule);
    }
    ref.invalidateSelf();
    await future;
  }
}


final scheduleSnapshotProvider =
    AsyncNotifierProvider<ScheduleSnapshotNotifier, ScheduleSnapshot>(
  ScheduleSnapshotNotifier.new,
);

final coursesProvider = FutureProvider<List<Course>>((ref) async {
  return (await ref.watch(scheduleSnapshotProvider.future)).courses;
});

final currentWeekProvider = FutureProvider<int>((ref) async {
  return (await ref.watch(scheduleSnapshotProvider.future)).week;
});
