import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/snapshot_cache.dart';
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
    var active = true;
    ref.onDispose(() => active = false);
    if (kIsWeb) {
      final imported = await LocalScheduleStore.read();
      if (imported != null) return imported;
    }
    if (!auth.$1) {
      return const ScheduleSnapshot(
        courses: [],
        week: 1,
        live: false,
        banner: '正在恢复账号',
      );
    }
    if (auth.$2.isGuest || auth.$2.isDemo || kIsWeb) {
      return ref.read(mockScheduleRepositoryProvider).load();
    }
    final cache = ref.read(snapshotCacheProvider);
    final key = SnapshotCache.scoped(SnapshotCache.schedule, auth.$2.studentId);
    final cached = await cache.readEnvelope(key, ScheduleSnapshot.fromJson);
    if (cached != null && active) {
      state = AsyncData(
        cached.payload.asCached(cached.savedAt, banner: '正在更新缓存课表'),
      );
    }
    Future<ScheduleSnapshot> fetch() async {
      ScheduleSnapshot fresh;
      try {
        fresh = await ref.read(campusSessionProvider).readQueue.run(() {
          if (!active) throw StateError('Sync superseded');
          return ref.read(scheduleRepositoryProvider).load();
        });
      } catch (_) {
        fresh = ScheduleSnapshot(
          courses: const [],
          week: cached?.payload.week ?? 1,
          live: false,
          banner: '暂时无法连接校园服务',
          failure: ScheduleFailure.unavailable,
        );
      }
      if (fresh.live) {
        if (active) await cache.write(key, fresh.toJson());
        return fresh.asFresh(banner: fresh.banner);
      }
      if (cached != null) {
        return cached.payload
            .asCached(cached.savedAt, banner: fresh.banner)
            .copyWith(failure: fresh.failure ?? ScheduleFailure.unavailable);
      }
      return fresh;
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
