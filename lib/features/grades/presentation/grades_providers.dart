import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/campus_snapshot_loader.dart';
import '../../../core/cache/snapshot_cache.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/network/campus_connection.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/grade_record.dart';

class GradesSnapshotNotifier extends AsyncNotifier<GradesSnapshot> {
  Future<GradesSnapshot>? pending;
  @override
  Future<GradesSnapshot> build() async {
    var active = true;
    ref.onDispose(() => active = false);
    ref.watch(campusConnectionRevisionProvider);
    ref.watch(
      authControllerProvider.select(
        (state) =>
            '${state.initialized}|${state.user.studentId}|${state.user.sessionToken}|${state.user.isDemo}',
      ),
    );
    final result = await (pending = loadCampusSnapshot<GradesSnapshot>(
      ref: ref,
      service: 'grades',
      demo: () => ref.read(mockGradesRepositoryProvider).load(),
      key: SnapshotCache.scoped(
        SnapshotCache.grades,
        ref.read(authControllerProvider).user.studentId,
      ),
      fromJson: GradesSnapshot.fromJson,
      toJson: (s) => s.toJson(),
      fetch: () => ref.read(gradesRepositoryProvider).load(),
      isLive: (s) => s.live,
      markCached: (s, t) => s.asCached(t, banner: AppStrings.cacheBanner(t)),
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

final gradesSnapshotProvider =
    AsyncNotifierProvider<GradesSnapshotNotifier, GradesSnapshot>(
      GradesSnapshotNotifier.new,
      retry: (count, error) => null,
    );
