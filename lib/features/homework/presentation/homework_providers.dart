import '../../../core/data/data_status.dart';
import '../../../core/data/data_status_provider.dart';

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
    final report = statusReporter(ref, 'homework');
    report(const DataStatus.loading());
    final auth = ref.watch(
      authControllerProvider.select((s) => (s.initialized, s.user)),
    );
    ref.watch(campusConnectionRevisionProvider);
    if (!auth.$1 || auth.$2.isGuest || auth.$2.isDemo) {
      if (auth.$1)
        report(
          const DataStatus(
            phase: DataPhase.failed,
            problem: DataProblem.loginRequired,
          ),
        );
      throw const HomeworkAuthRequired();
    }
    var active = true;
    final session = ref.read(campusSessionProvider);
    final store = ref.read(credentialStoreProvider);
    final repository = HomeworkRepository(session);
    ref.onDispose(() {
      active = false;
      repository.cancel();
    });
    final day = campusTime(DateTime.now());
    // Versioned, month-scoped cache prevents old unfiltered snapshots leaking
    // into the current semester, including across term boundaries.
    final key =
        'homework.v2.${auth.$2.studentId}.current.${day.year}-${day.month}';
    HomeworkSnapshot? cached;
    try {
      final raw = await store.read(key);
      if (raw != null)
        cached = HomeworkSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
    } catch (_) {
      /* An unreadable cache does not prevent a live refresh. */
    }
    if (!active) throw StateError('Homework sync superseded');
    if (cached != null) {
      state = AsyncData(cached);
      report(
        DataStatus.loading(
          source: DataSource.cache,
          updatedAt: cached.updatedAt,
        ),
      );
    }
    try {
      final result = await (pending = session.readQueue
          .run(() {
            if (!active) throw StateError('Homework sync superseded');
            return repository.load();
          })
          .timeout(
            const Duration(seconds: 120),
            onTimeout: () {
              repository.cancel();
              throw TimeoutException('作业同步超时');
            },
          ));
      if (active && result.failedCourses == 0) {
        try {
          await store.write(key: key, value: jsonEncode(result.toJson()));
        } catch (_) {
          report(
            DataStatus(
              phase: DataPhase.ready,
              source: DataSource.live,
              updatedAt: result.updatedAt,
              problem: DataProblem.storage,
            ),
          );
          return result;
        }
      }
      // Keep the last complete snapshot if some courses failed this time.
      final partial = result.failedCourses > 0;
      final shown = partial && cached != null ? cached : result;
      report(
        DataStatus(
          phase: DataPhase.ready,
          source: shown.fromCache ? DataSource.cache : DataSource.live,
          updatedAt: shown.updatedAt,
          problem: partial ? DataProblem.partial : null,
        ),
      );
      return shown;
    } catch (error) {
      report(
        DataStatus(
          phase: DataPhase.failed,
          source: cached == null ? DataSource.none : DataSource.cache,
          updatedAt: cached?.updatedAt,
          problem: error is HomeworkAuthRequired
              ? DataProblem.loginRequired
              : dataProblem(error),
        ),
      );
      if (cached != null) return cached;
      rethrow;
    }
  }

  void updateStatus(int id, HomeworkStatus status) {
    final data = state.asData?.value;
    if (data == null) return;
    state = AsyncData(
      HomeworkSnapshot(
        [
          for (final item in data.items)
            item.id == id ? item.withStatus(status) : item,
        ],
        data.updatedAt,
        fromCache: data.fromCache,
        failedCourses: data.failedCourses,
        terms: data.terms,
        termLabel: data.termLabel,
      ),
    );
  }
}

final homeworkProvider =
    AsyncNotifierProvider<HomeworkNotifier, HomeworkSnapshot>(
      HomeworkNotifier.new,
      retry: (count, error) => null,
    );

final homeworkDetailProvider = FutureProvider.autoDispose
    .family<HomeworkDetail, int>((ref, id) async {
      final auth = ref.watch(
        authControllerProvider.select((s) => (s.initialized, s.user)),
      );
      ref.watch(campusConnectionRevisionProvider);
      if (!auth.$1 || auth.$2.isGuest || auth.$2.isDemo)
        throw const HomeworkAuthRequired();
      final session = ref.read(campusSessionProvider);
      final repository = HomeworkRepository(session);
      var active = true;
      ref.onDispose(() {
        active = false;
        repository.cancel();
      });
      return session.readQueue
          .run(() {
            if (!active) throw StateError('Homework detail superseded');
            return repository.detail(id);
          })
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              repository.cancel();
              throw TimeoutException('作业详情加载超时');
            },
          );
    }, retry: (count, error) => null);

// Historical selections are isolated from home/calendar/widget preloading.
final homeworkTermProvider = FutureProvider.autoDispose
    .family<HomeworkSnapshot, String>((ref, termId) async {
      final auth = ref.watch(
        authControllerProvider.select((s) => (s.initialized, s.user)),
      );
      ref.watch(campusConnectionRevisionProvider);
      if (!auth.$1 || auth.$2.isGuest || auth.$2.isDemo)
        throw const HomeworkAuthRequired();
      final session = ref.read(campusSessionProvider);
      final repository = HomeworkRepository(session);
      var active = true;
      ref.onDispose(() {
        active = false;
        repository.cancel();
      });
      return session.readQueue
          .run(() {
            if (!active) throw StateError('Homework selection superseded');
            return repository.load(termId: termId);
          })
          .timeout(
            const Duration(seconds: 120),
            onTimeout: () {
              repository.cancel();
              throw TimeoutException('作业同步超时');
            },
          );
    }, retry: (count, error) => null);

class HomeworkStatuses extends Notifier<Map<int, HomeworkStatus>> {
  @override
  Map<int, HomeworkStatus> build() {
    ref.watch(authControllerProvider.select((s) => (s.initialized, s.user)));
    ref.watch(campusConnectionRevisionProvider);
    return {};
  }

  void update(int id, HomeworkStatus status) => state = {...state, id: status};
}

final homeworkStatusesProvider =
    NotifierProvider<HomeworkStatuses, Map<int, HomeworkStatus>>(
      HomeworkStatuses.new,
    );
