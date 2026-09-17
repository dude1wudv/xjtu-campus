import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached_snapshot_loader.dart';
import '../../../core/cache/snapshot_cache.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/network/campus_connection.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/course.dart';
import '../domain/schedule_repository.dart';

class ScheduleSnapshotNotifier extends AsyncNotifier<ScheduleSnapshot> {
  Future<ScheduleSnapshot>? pending;
  @override
  Future<ScheduleSnapshot> build() async {
    var active = true;
    ref.onDispose(() => active = false);
    ref.watch(campusConnectionRevisionProvider);
    ref.watch(
      authControllerProvider.select(
        (state) => '${state.user.studentId}|${state.user.sessionToken}|${state.user.isDemo}',
      ),
    );
    final result = await (pending = loadWithCache<ScheduleSnapshot>(
      isCurrent: () => active,
      cache: ref.watch(snapshotCacheProvider),
      key: SnapshotCache.scoped(SnapshotCache.schedule, ref.read(authControllerProvider).user.studentId),
      fromJson: ScheduleSnapshot.fromJson,
      toJson: (s) => s.toJson(),
      fetch: () => ref.read(campusSessionProvider).readQueue.run(() {
        if (!active) throw StateError('Sync superseded');
        return ref.read(scheduleRepositoryProvider).load();
      }),
      isLive: (s) => s.live,
      markCached: (s, t) => s.asCached(t, banner: AppStrings.cacheBanner(t)),
      markRefreshFailed: (s, t) => s.asCached(
        t,
        banner: AppStrings.cacheRefreshFailed,
      ),
      emit: (s) { if (active) state = AsyncData(s); },
    ));
    if (result.live && !result.fromCache) {
      return result.asFresh(banner: result.banner);
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
