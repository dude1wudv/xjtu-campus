import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached_snapshot_loader.dart';
import '../../../core/cache/snapshot_cache.dart';
import '../../../core/data/data_status.dart';
import '../../../core/data/data_status_provider.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/network/campus_connection.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/local_schedule_store.dart';
import '../domain/course.dart';
import '../domain/schedule_repository.dart';

class ScheduleSnapshotNotifier extends AsyncNotifier<ScheduleSnapshot> {
  Future<ScheduleSnapshot>? pending;
  @override
  Future<ScheduleSnapshot> build() async {
    ref.watch(campusConnectionRevisionProvider);
    final auth = ref.watch(
      authControllerProvider.select((s) => (s.initialized, s.user)),
    );
    final report = statusReporter(ref, 'schedule');
    var active = true;
    ref.onDispose(() => active = false);
    report(const DataStatus.loading());
    if (kIsWeb) {
      try {
        final imported = await LocalScheduleStore.read();
        if (imported != null) {
          report(
            DataStatus(
              phase: DataPhase.ready,
              source: DataSource.local,
              updatedAt: imported.cachedAt,
            ),
          );
          return imported;
        }
      } catch (_) {
        report(
          const DataStatus(
            phase: DataPhase.failed,
            problem: DataProblem.storage,
          ),
        );
        throw const CampusDataException(DataProblem.storage);
      }
    }
    if (!auth.$1 || auth.$2.isGuest || auth.$2.isDemo || kIsWeb) {
      final demo = await ref.read(mockScheduleRepositoryProvider).load();
      if (auth.$1)
        report(
          const DataStatus(phase: DataPhase.ready, source: DataSource.demo),
        );
      return demo;
    }
    Future<ScheduleSnapshot> fetch() async {
      try {
        final result = await loadWithCache<ScheduleSnapshot>(
          cache: ref.read(snapshotCacheProvider),
          key: SnapshotCache.scoped(SnapshotCache.schedule, auth.$2.studentId),
          fromJson: ScheduleSnapshot.fromJson,
          toJson: (s) => s.toJson(),
          isCurrent: () => active,
          allowDemo: false,
          onStatus: report,
          isLive: (s) => s.live,
          markCached: (s, t) => s.asCached(t, banner: '正在更新缓存课表'),
          markRefreshFailed: (s, t) => s
              .asCached(t, banner: '课表同步失败，仍显示缓存')
              .copyWith(failure: ScheduleFailure.unavailable),
          emit: (s) {
            if (active) state = AsyncData(s);
          },
          fetch: () => ref.read(campusSessionProvider).readQueue.run(() async {
            if (!active)
              throw const CampusDataException(DataProblem.unavailable);
            final result = await ref.read(scheduleRepositoryProvider).load();
            if (result.failure != null)
              throw CampusDataException(
                result.failure == ScheduleFailure.sessionExpired
                    ? DataProblem.loginRequired
                    : DataProblem.unavailable,
              );
            return result;
          }),
        );
        return result.live && !result.fromCache
            ? result.asFresh(banner: result.banner)
            : result;
      } catch (error) {
        return ScheduleSnapshot(
          courses: const [],
          week: 1,
          live: false,
          banner: '课表未同步',
          failure: dataProblem(error) == DataProblem.loginRequired
              ? ScheduleFailure.sessionExpired
              : ScheduleFailure.unavailable,
        );
      }
    }

    return await (pending = fetch());
  }

  Future<void> refresh({bool force = true}) async {
    ref.invalidateSelf();
    await future;
    await pending;
  }
}

final scheduleSnapshotProvider =
    AsyncNotifierProvider<ScheduleSnapshotNotifier, ScheduleSnapshot>(
      ScheduleSnapshotNotifier.new,
      retry: (count, error) => null,
    );
final coursesProvider = FutureProvider<List<Course>>(
  (ref) async => (await ref.watch(scheduleSnapshotProvider.future)).courses,
);
final currentWeekProvider = FutureProvider<int>(
  (ref) async => (await ref.watch(scheduleSnapshotProvider.future)).week,
);
