import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached_snapshot_loader.dart';
import '../../../core/cache/snapshot_cache.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/campus_card.dart';

class CampusCardSnapshotNotifier extends AsyncNotifier<CampusCardSnapshot> {
  @override
  Future<CampusCardSnapshot> build() async {
    ref.watch(
      authControllerProvider.select(
        (state) => '${state.user.sessionToken}|${state.user.isDemo}',
      ),
    );
    final result = await loadWithCache<CampusCardSnapshot>(
      cache: ref.watch(snapshotCacheProvider),
      key: SnapshotCache.campusCard,
      fromJson: CampusCardSnapshot.fromJson,
      toJson: (s) => s.toJson(),
      fetch: () => ref.read(campusCardRepositoryProvider).load(),
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
      await ref.read(snapshotCacheProvider).remove(SnapshotCache.campusCard);
    }
    ref.invalidateSelf();
    await future;
  }
}


final campusCardSnapshotProvider =
    AsyncNotifierProvider<CampusCardSnapshotNotifier, CampusCardSnapshot>(
  CampusCardSnapshotNotifier.new,
);
