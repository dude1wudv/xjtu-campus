import 'snapshot_cache.dart';

/// Stale-while-revalidate helper for AsyncNotifier.build().
///
/// 1. If [forceRefresh] is false and [emit] is provided and cache hits, emit
///    cached value immediately.
/// 2. Await [fetch].
/// 3. On live success → write cache and return fresh.
/// 4. On non-live / failure → keep cache with soft-fail banner when present.
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
  bool forceRefresh = false,
}) async {
  final CachedEnvelope<T>? cached;
  if (forceRefresh) {
    await cache.remove(key);
    cached = null;
  } else {
    cached = await cache.readEnvelope(key, fromJson);
    if (cached != null && emit != null) {
      emit(markCached(cached.payload, cached.savedAt));
    }
  }

  try {
    final fresh = await fetch();
    if (isLive(fresh)) {
      await cache.write(key, toJson(fresh));
      return fresh;
    }
    if (cached != null) {
      return markRefreshFailed(cached.payload, cached.savedAt);
    }
    return fresh;
  } on Object {
    if (cached != null) {
      return markRefreshFailed(cached.payload, cached.savedAt);
    }
    rethrow;
  }
}
