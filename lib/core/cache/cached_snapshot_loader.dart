import '../data/data_status.dart';
import 'snapshot_cache.dart';

/// Preserve the last successful snapshot on refresh failure; never discard it
/// merely because a refresh was forced. Demo data is an explicit caller choice.
Future<T> loadWithCache<T>({
  required SnapshotCache cache,
  required String key,
  required T Function(Map<String, dynamic> json) fromJson,
  required Map<String, dynamic> Function(T value) toJson,
  required Future<T> Function() fetch,
  required bool Function(T value) isLive,
  required T Function(T cached, DateTime savedAt) markCached,
  required T Function(T cached, DateTime savedAt) markRefreshFailed,
  void Function(T value)? emit,
  void Function(DataStatus status)? onStatus,
  bool allowDemo = true,
  bool forceRefresh = false,
  bool Function()? isCurrent,
}) async {
  void report(DataStatus status) {
    if (isCurrent?.call() ?? true) onStatus?.call(status);
  }

  report(const DataStatus.loading());
  CachedEnvelope<T>? cached;
  try {
    cached = await cache.readEnvelope(key, fromJson);
  } catch (_) {
    /* Fetch still works if storage is unavailable. */
  }
  if (cached != null && !forceRefresh && (isCurrent?.call() ?? true)) {
    emit?.call(markCached(cached.payload, cached.savedAt));
    report(
      DataStatus.loading(source: DataSource.cache, updatedAt: cached.savedAt),
    );
  }
  try {
    final fresh = await fetch();
    if (isLive(fresh)) {
      DataProblem? warning;
      if (isCurrent?.call() ?? true) {
        try {
          await cache.write(key, toJson(fresh));
        } catch (_) {
          warning = DataProblem.storage;
        }
      }
      report(
        DataStatus(
          phase: DataPhase.ready,
          source: DataSource.live,
          updatedAt: DateTime.now(),
          problem: warning,
        ),
      );
      return fresh;
    }
    if (!allowDemo) throw const CampusDataException(DataProblem.unavailable);
    if (cached != null) {
      report(
        DataStatus(
          phase: DataPhase.failed,
          source: DataSource.cache,
          updatedAt: cached.savedAt,
          problem: DataProblem.unavailable,
        ),
      );
      return markRefreshFailed(cached.payload, cached.savedAt);
    }
    report(const DataStatus(phase: DataPhase.ready, source: DataSource.demo));
    return fresh;
  } catch (error) {
    report(
      DataStatus(
        phase: DataPhase.failed,
        source: cached == null ? DataSource.none : DataSource.cache,
        updatedAt: cached?.savedAt,
        problem: dataProblem(error),
      ),
    );
    if (cached != null)
      return markRefreshFailed(cached.payload, cached.savedAt);
    if (error is CampusDataException) rethrow;
    throw CampusDataException(dataProblem(error));
  }
}
