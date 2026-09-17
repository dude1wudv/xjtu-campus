import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/network/campus_connection.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/homework_repository.dart';
import '../domain/homework.dart';

class HomeworkNotifier extends AsyncNotifier<HomeworkSnapshot> {
  Future<HomeworkSnapshot>? pending;

  @override
  Future<HomeworkSnapshot> build() async {
    final auth = ref.watch(authControllerProvider.select((s) => (s.initialized, s.user)));
    ref.watch(campusConnectionRevisionProvider);
    if (!auth.$1 || auth.$2.isGuest || auth.$2.isDemo) throw const HomeworkAuthRequired();
    var active = true;
    final session = ref.read(campusSessionProvider);
    final store = ref.read(credentialStoreProvider);
    final repository = HomeworkRepository(session);
    ref.onDispose(() { active = false; repository.cancel(); });
    final key = 'homework.snapshot.${auth.$2.studentId}';
    HomeworkSnapshot? cached;
    try {
      final raw = await store.read(key);
      if (raw != null) cached = HomeworkSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) { /* An unreadable cache does not prevent a live refresh. */ }
    if (!active) throw StateError('Homework sync superseded');
    if (cached != null) state = AsyncData(cached);
    try {
      final result = await (pending = session.readQueue.run(() {
        if (!active) throw StateError('Homework sync superseded');
        return repository.load();
      }).timeout(const Duration(seconds: 120), onTimeout: () {
        repository.cancel();
        throw TimeoutException('作业同步超时');
      }));
      if (active && result.failedCourses == 0) {
        await store.write(key: key, value: jsonEncode(result.toJson()));
      }
      // Keep the last complete snapshot if some courses failed this time.
      if (result.failedCourses > 0 && cached != null) return cached;
      return result;
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  void updateStatus(int id, HomeworkStatus status) {
    final data = state.asData?.value;
    if (data == null) return;
    state = AsyncData(HomeworkSnapshot(
      [for (final item in data.items) item.id == id ? item.withStatus(status) : item],
      data.updatedAt, fromCache: data.fromCache, failedCourses: data.failedCourses));
  }
}

final homeworkProvider = AsyncNotifierProvider<HomeworkNotifier, HomeworkSnapshot>(
  HomeworkNotifier.new, retry: (count, error) => null,
);

final homeworkDetailProvider = FutureProvider.autoDispose.family<HomeworkDetail, int>((ref, id) async {
  final auth = ref.watch(authControllerProvider.select((s) => (s.initialized, s.user)));
  ref.watch(campusConnectionRevisionProvider);
  if (!auth.$1 || auth.$2.isGuest || auth.$2.isDemo) throw const HomeworkAuthRequired();
  final session = ref.read(campusSessionProvider);
  final repository = HomeworkRepository(session);
  var active = true;
  ref.onDispose(() { active = false; repository.cancel(); });
  return session.readQueue.run(() {
    if (!active) throw StateError('Homework detail superseded');
    return repository.detail(id);
  }).timeout(const Duration(seconds: 60), onTimeout: () {
    repository.cancel();
    throw TimeoutException('作业详情加载超时');
  });
}, retry: (count, error) => null);
