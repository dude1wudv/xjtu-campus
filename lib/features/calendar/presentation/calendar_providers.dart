import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached_snapshot_loader.dart';
import '../../../core/cache/snapshot_cache.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../schedule/presentation/schedule_providers.dart';
import '../domain/school_calendar.dart';

class CalendarSnapshotNotifier extends AsyncNotifier<CalendarSnapshot> {
  @override
  Future<CalendarSnapshot> build() async {
    final schedule = ref.watch(scheduleSnapshotProvider);
    final scheduleWeek = schedule.asData?.value.week;
    final result = await loadWithCache<CalendarSnapshot>(
      cache: ref.watch(snapshotCacheProvider),
      key: SnapshotCache.calendar,
      fromJson: CalendarSnapshot.fromJson,
      toJson: (s) => s.toJson(),
      fetch: () => ref.read(calendarRepositoryProvider).load(
            scheduleWeek: scheduleWeek,
          ),
      isLive: (s) => s.live,
      markCached: (s, t) => s.asCached(t, banner: AppStrings.cacheBanner(t)),
      markRefreshFailed: (s, t) => s.asCached(
        t,
        banner: AppStrings.cacheRefreshFailed,
      ),
      emit: (s) => state = AsyncData(s),
    );
    if (result.live && !result.fromCache) {
      return result.asFresh();
    }
    return result;
  }

  /// Clear SnapshotCache for this key then rebuild (true network path).
  Future<void> refresh({bool force = true}) async {
    if (force) {
      await ref.read(snapshotCacheProvider).remove(SnapshotCache.calendar);
    }
    ref.invalidateSelf();
    await future;
  }
}


final calendarSnapshotProvider =
    AsyncNotifierProvider<CalendarSnapshotNotifier, CalendarSnapshot>(
  CalendarSnapshotNotifier.new,
);
