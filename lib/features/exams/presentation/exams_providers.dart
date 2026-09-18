import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/campus_snapshot_loader.dart';
import '../../../core/cache/snapshot_cache.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/network/campus_connection.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/exam_arrangement.dart';

class ExamsSnapshotNotifier extends AsyncNotifier<ExamsSnapshot> {
  Future<ExamsSnapshot>? pending;
  @override
  Future<ExamsSnapshot> build() async {
    var active = true;
    ref.onDispose(() => active = false);
    ref.watch(campusConnectionRevisionProvider);
    ref.watch(
      authControllerProvider.select(
        (state) =>
            '${state.initialized}|${state.user.studentId}|${state.user.sessionToken}|${state.user.isDemo}',
      ),
    );
    final result = await (pending = loadCampusSnapshot<ExamsSnapshot>(
      ref: ref,
      service: 'exams',
      demo: () => ref.read(mockExamsRepositoryProvider).load(),
      key: SnapshotCache.scoped(
        SnapshotCache.exams,
        ref.read(authControllerProvider).user.studentId,
      ),
      fromJson: ExamsSnapshot.fromJson,
      toJson: (s) => s.toJson(),
      fetch: () => ref.read(examsRepositoryProvider).load(),
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

final examsSnapshotProvider =
    AsyncNotifierProvider<ExamsSnapshotNotifier, ExamsSnapshot>(
      ExamsSnapshotNotifier.new,
      retry: (count, error) => null,
    );
