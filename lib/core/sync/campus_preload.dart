import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/attendance/presentation/attendance_providers.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/calendar/presentation/calendar_providers.dart';
import '../../features/campus_card/presentation/campus_card_providers.dart';
import '../../features/classroom/presentation/classroom_page.dart';
import '../../features/exams/presentation/exams_providers.dart';
import '../../features/grades/presentation/grades_providers.dart';
import '../../features/homework/presentation/homework_providers.dart';
import '../../features/library_seats/presentation/library_seats_providers.dart';
import '../../features/notifications/presentation/dean_notices_webview_loader.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/schedule/presentation/schedule_providers.dart';
import '../network/campus_connection.dart';

enum PreloadStatus { waiting, loading, ready, cached, failed }

class CampusPreloadState {
  const CampusPreloadState(this.services);
  final Map<String, PreloadStatus> services;

  bool get busy => services.values.any(
      (value) => value == PreloadStatus.waiting || value == PreloadStatus.loading);
  int get completed => services.values.where(
      (value) => value != PreloadStatus.waiting && value != PreloadStatus.loading).length;
}

class CampusPreload extends Notifier<CampusPreloadState> {
  @override
  CampusPreloadState build() {
    final identity = ref.watch(authControllerProvider.select(
      (auth) => (auth.initialized, auth.user.studentId, auth.user.isDemo),
    ));
    ref.watch(campusConnectionRevisionProvider);
    final connecting = ref.watch(campusConnectionBusyProvider);
    var active = true;
    ref.onDispose(() => active = false);
    if (!identity.$1 || identity.$2.isEmpty || identity.$3 || connecting) {
      return const CampusPreloadState({});
    }
    final jobs = <String, Future<PreloadStatus> Function()>{
      '课表': () async {
        var data = await ref.read(scheduleSnapshotProvider.future);
        data = await ref.read(scheduleSnapshotProvider.notifier).pending ?? data;
        return _status(data.live, data.fromCache);
      },
      '考勤': () async {
        var data = await ref.read(attendanceSnapshotProvider.future);
        data = await ref.read(attendanceSnapshotProvider.notifier).pending ?? data;
        return _status(true, data.fromCache);
      },
      '作业': () async {
        var data = await ref.read(homeworkProvider.future);
        data = await ref.read(homeworkProvider.notifier).pending ?? data;
        return data.failedCourses > 0 ? PreloadStatus.failed : _status(true, data.fromCache);
      },
      '成绩': () async {
        var data = await ref.read(gradesSnapshotProvider.future);
        data = await ref.read(gradesSnapshotProvider.notifier).pending ?? data;
        return _status(data.live, data.fromCache);
      },
      '考试': () async {
        var data = await ref.read(examsSnapshotProvider.future);
        data = await ref.read(examsSnapshotProvider.notifier).pending ?? data;
        return _status(data.live, data.fromCache);
      },
      '校园卡': () async {
        var data = await ref.read(campusCardSnapshotProvider.future);
        data = await ref.read(campusCardSnapshotProvider.notifier).pending ?? data;
        return _status(data.live, data.fromCache);
      },
      '校历': () async {
        var data = await ref.read(calendarSnapshotProvider.future);
        data = await ref.read(calendarSnapshotProvider.notifier).pending ?? data;
        return _status(data.live, data.fromCache);
      },
      '图书馆': () async {
        final data = await ref.read(librarySeatsSnapshotProvider.future);
        return _status(data.live, false);
      },
      // Campus-wide room queries can fan out to many buildings. Start these
      // after the personal snapshots so they do not delay course/grade loading.
      '教室': () async {
        var data = await ref.read(freeClassroomsProvider.future);
        data = await ref.read(freeClassroomsProvider.notifier).pending ?? data;
        return _status(data.live, data.fromCache);
      },
    };
    Future.microtask(() => _run(jobs, () => active));
    return CampusPreloadState({for (final name in jobs.keys) name: PreloadStatus.waiting});
  }

  PreloadStatus _status(bool live, bool cached) => cached
      ? PreloadStatus.cached : live ? PreloadStatus.ready : PreloadStatus.failed;

  Future<void> _run(Map<String, Future<PreloadStatus> Function()> jobs,
      bool Function() active) async {
    final entries = jobs.entries.toList();
    var cursor = 0;
    void update(String name, PreloadStatus status) {
      if (active()) state = CampusPreloadState({...state.services, name: status});
    }
    Future<void> worker() async {
      while (active() && cursor < entries.length) {
        final job = entries[cursor++];
        update(job.key, PreloadStatus.loading);
        try {
          final result = await job.value();
          update(job.key, result);
        } catch (_) {
          update(job.key, PreloadStatus.failed);
        }
      }
    }
    await Future.wait([worker(), worker()]);
  }

  void retry() {
    // Only restart failed items; successful snapshots remain in provider memory.
    final failed = state.services.entries
        .where((entry) => entry.value == PreloadStatus.failed)
        .map((entry) => entry.key).toSet();
    if (failed.contains('课表')) ref.invalidate(scheduleSnapshotProvider);
    if (failed.contains('考勤')) ref.invalidate(attendanceSnapshotProvider);
    if (failed.contains('作业')) ref.invalidate(homeworkProvider);
    if (failed.contains('成绩')) ref.invalidate(gradesSnapshotProvider);
    if (failed.contains('考试')) ref.invalidate(examsSnapshotProvider);
    if (failed.contains('校园卡')) ref.invalidate(campusCardSnapshotProvider);
    if (failed.contains('校历')) ref.invalidate(calendarSnapshotProvider);
    if (failed.contains('图书馆')) ref.invalidate(librarySeatsSnapshotProvider);
    if (failed.contains('教室')) ref.invalidate(freeClassroomsProvider);
    ref.invalidateSelf();
  }
}

final campusPreloadProvider =
    NotifierProvider<CampusPreload, CampusPreloadState>(CampusPreload.new);

/// One notification WebView per app, shared by home and the notification tab.
/// It starts after session restoration and is not recreated on tab changes.
class CampusBackgroundSync extends ConsumerWidget {
  const CampusBackgroundSync({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(campusPreloadProvider);
    final initialized = ref.watch(authControllerProvider.select((s) => s.initialized));
    final connecting = ref.watch(campusConnectionBusyProvider);
    final revision = ref.watch(campusConnectionRevisionProvider);
    final notices = ref.watch(liveDeanNoticesProvider);
    // Warm the same fallback the notification tab consumes, without waiting
    // for the user to open that tab after an embedded-WebView failure.
    if (initialized && !connecting && notices.isFailed) {
      ref.watch(noticesFallbackProvider);
    }
    // flutter_inappwebview has no test platform implementation.
    final inTests = WidgetsBinding.instance.runtimeType
        .toString()
        .contains('Test');
    return Stack(fit: StackFit.expand, children: [
      if (initialized && !connecting && !inTests)
        Positioned(
          left: 0, top: 0,
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0,
                child: DeanNoticesWebViewLoader(key: ValueKey(revision)),
              ),
            ),
          ),
        ),
      child,
    ]);
  }
}
