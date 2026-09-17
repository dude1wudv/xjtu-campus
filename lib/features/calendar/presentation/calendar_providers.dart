import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached_snapshot_loader.dart';
import '../../../core/cache/snapshot_cache.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/network/campus_connection.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../schedule/presentation/schedule_providers.dart';
import '../domain/school_calendar.dart';

class CalendarSnapshotNotifier extends AsyncNotifier<CalendarSnapshot> {
  Future<CalendarSnapshot>? pending;
  @override
  Future<CalendarSnapshot> build() async {
    var active = true;
    ref.onDispose(() => active = false);
    ref.watch(campusConnectionRevisionProvider);
    final schedule = await ref.watch(scheduleSnapshotProvider.future);
    final scheduleWeek = schedule.live ? schedule.week : null;
    final result = await (pending = loadWithCache<CalendarSnapshot>(
      isCurrent: () => active,
      cache: ref.watch(snapshotCacheProvider),
      key: SnapshotCache.scoped(SnapshotCache.calendar, ref.read(authControllerProvider).user.studentId),
      fromJson: CalendarSnapshot.fromJson,
      toJson: (s) => s.toJson(),
      fetch: () => ref.read(campusSessionProvider).readQueue.run(() {
        if (!active) throw StateError('Sync superseded');
        return ref.read(calendarRepositoryProvider).load(scheduleWeek: scheduleWeek);
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


final calendarSnapshotProvider =
    AsyncNotifierProvider<CalendarSnapshotNotifier, CalendarSnapshot>(
  CalendarSnapshotNotifier.new,
);
