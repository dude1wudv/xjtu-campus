import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../cache/cached_snapshot_loader.dart';
import '../di/core_providers.dart';
import 'data_status.dart';
import 'data_status_provider.dart';

/// Shared lifecycle for personal campus snapshots. A restored account whose
/// cookies expired must never silently switch to a mock repository.
Future<T> loadCampusSnapshot<T>({
  required Ref ref,
  required String service,
  required String key,
  required T Function(Map<String, dynamic>) fromJson,
  required Map<String, dynamic> Function(T) toJson,
  required Future<T> Function() fetch,
  required Future<T> Function() demo,
  required bool Function(T) isLive,
  required T Function(T, DateTime) markCached,
  required T Function(T, DateTime) markRefreshFailed,
  required void Function(T) emit,
}) async {
  final auth = ref.read(authControllerProvider);
  final report = statusReporter(ref, service);
  var active = true;
  ref.onDispose(() => active = false);
  report(const DataStatus.loading());
  if (!auth.initialized || auth.user.isGuest || auth.user.isDemo) {
    final result = await demo();
    if (auth.initialized)
      report(const DataStatus(phase: DataPhase.ready, source: DataSource.demo));
    return result;
  }
  return loadWithCache<T>(
    cache: ref.read(snapshotCacheProvider),
    key: key,
    fromJson: fromJson,
    toJson: toJson,
    isLive: isLive,
    allowDemo: false,
    isCurrent: () => active,
    emit: emit,
    markCached: markCached,
    markRefreshFailed: markRefreshFailed,
    onStatus: report,
    fetch: () => ref.read(campusSessionProvider).readQueue.run(() async {
      if (!active) throw const CampusDataException(DataProblem.unavailable);
      if (!await ref.read(campusSessionProvider).hasCasCookie()) {
        throw const CampusDataException(DataProblem.loginRequired);
      }
      return fetch();
    }),
  );
}
