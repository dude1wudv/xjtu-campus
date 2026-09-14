import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached_snapshot_loader.dart';
import '../../../core/cache/snapshot_cache.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/grade_record.dart';

class GradesSnapshotNotifier extends AsyncNotifier<GradesSnapshot> {
  @override
  Future<GradesSnapshot> build() async {
    ref.watch(
      authControllerProvider.select(
        (state) => '${state.user.sessionToken}|${state.user.isDemo}',
      ),
    );
    final result = await loadWithCache<GradesSnapshot>(
      cache: ref.watch(snapshotCacheProvider),
      key: SnapshotCache.grades,
      fromJson: GradesSnapshot.fromJson,
      toJson: (s) => s.toJson(),
      fetch: () => ref.read(gradesRepositoryProvider).load(),
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
}

final gradesSnapshotProvider =
    AsyncNotifierProvider<GradesSnapshotNotifier, GradesSnapshot>(
  GradesSnapshotNotifier.new,
);
