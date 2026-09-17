import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/network/campus_connection.dart';
import '../../alarms/data/local_notification_scheduler.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/library_seat_api.dart';
import '../data/library_seat_areas.dart';
import '../data/library_seat_schedule_store.dart';
import '../data/live_library_seats_repository.dart';
import '../domain/library_seat.dart';
import '../domain/library_seats_repository.dart';

final librarySeatsRepositoryProvider = Provider<LibrarySeatsRepository>(
  (ref) {
    final session = ref.watch(campusSessionProvider);
    return LiveLibrarySeatsRepository(
      api: LibrarySeatApi(session: session),
    );
  },
);

final librarySeatScheduleStoreProvider = Provider<LibrarySeatScheduleStore>(
  (ref) => LibrarySeatScheduleStore(),
);

class LibrarySeatAreaController extends Notifier<String> {
  @override
  String build() => 'west3B';

  void setArea(String code) => state = code;
}

final librarySeatAreaProvider =
    NotifierProvider<LibrarySeatAreaController, String>(
  LibrarySeatAreaController.new,
);

class LibrarySeatsNotifier extends AsyncNotifier<LibrarySeatsSnapshot> {
  @override
  Future<LibrarySeatsSnapshot> build() async {
    var active = true;
    ref.onDispose(() => active = false);
    ref.watch(campusConnectionRevisionProvider);
    ref.watch(authControllerProvider.select((s) => s.user));
    await ref.read(campusSessionProvider).restore();
    final area = ref.watch(librarySeatAreaProvider);
    return ref.read(campusSessionProvider).readQueue.run(
      () {
        if (!active) throw StateError('Sync superseded');
        return ref.read(librarySeatsRepositoryProvider).listSeats(area);
      },
    );
  }

  Future<void> refresh({bool force = true}) async {
    ref.invalidateSelf();
    await future;
  }
}

final librarySeatsSnapshotProvider =
    AsyncNotifierProvider<LibrarySeatsNotifier, LibrarySeatsSnapshot>(
  LibrarySeatsNotifier.new,
);

final librarySeatScheduleProvider =
    FutureProvider<LibrarySeatScheduleConfig?>((ref) {
  return ref.watch(librarySeatScheduleStoreProvider).load();
});

/// In-app timer when a schedule is armed and app stays alive.
class LibrarySeatScheduleRunner extends Notifier<String?> {
  Timer? _timer;

  @override
  String? build() {
    ref.onDispose(() {
      _timer?.cancel();
    });
    return null;
  }

  Future<void> arm(LibrarySeatScheduleConfig config) async {
    _timer?.cancel();
    final store = ref.read(librarySeatScheduleStoreProvider);
    await store.save(config);

    final scheduler = ref.read(alarmSchedulerProvider);
    await scheduler.scheduleOneShot(
      id: LocalNotificationScheduler.librarySeatNotifyId,
      when: config.startAt,
      title: '图书馆座位预约',
      body: '到点提醒：偏好座位 ${config.preferredSeatId}（点开 App 执行预约）',
    );

    final delay = config.startAt.difference(DateTime.now());
    if (delay.isNegative) {
      state = '开始时间已过，可手动执行预约';
      return;
    }
    // Cap in-app timer at 24h; beyond that rely on notification + next open.
    if (delay > const Duration(hours: 24)) {
      state = '已保存定时（>${24}h，将依赖本地通知提醒）';
      return;
    }
    _timer = Timer(delay, () {
      unawaited(runConfigured());
    });
    state =
        '已设置：${config.startAt.hour.toString().padLeft(2, '0')}:${config.startAt.minute.toString().padLeft(2, '0')} 预约 ${config.preferredSeatId}';
    ref.invalidate(librarySeatScheduleProvider);
  }

  Future<void> clear() async {
    _timer?.cancel();
    await ref.read(librarySeatScheduleStoreProvider).clear();
    await ref
        .read(alarmSchedulerProvider)
        .cancelOneShot(LocalNotificationScheduler.librarySeatNotifyId);
    state = '已清除定时预约';
    ref.invalidate(librarySeatScheduleProvider);
  }

  Future<BookSeatResult> runConfigured() async {
    final config = await ref.read(librarySeatScheduleStoreProvider).load();
    if (config == null || !config.enabled) {
      return const BookSeatResult(
        success: false,
        message: '没有已配置的定时预约',
      );
    }
    state = '正在按配置预约…';
    final result =
        await ref.read(librarySeatsRepositoryProvider).reserveWithFallback(
              preferredSeatId: config.preferredSeatId,
              preferredAreaCode: config.preferredAreaCode,
              fallbackAreaCodes: config.fallbackAreaCodes,
              maxAttempts: config.maxAttempts,
              delayMs: config.delayMs,
            );
    state = result.message;
    ref.invalidate(librarySeatsSnapshotProvider);
    return result;
  }
}

final librarySeatScheduleRunnerProvider =
    NotifierProvider<LibrarySeatScheduleRunner, String?>(
  LibrarySeatScheduleRunner.new,
);

List<LibraryArea> get libraryAreas => LibrarySeatAreas.all;
