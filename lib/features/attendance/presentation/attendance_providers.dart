import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/network/campus_connection.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/attendance_repository.dart';
import '../domain/attendance_record.dart';

class AttendanceSystemController extends Notifier<AttendanceSystem> {
  @override
  AttendanceSystem build() => AttendanceSystem.undergraduate;
  void select(AttendanceSystem system) => state = system;
}

final attendanceSystemProvider = NotifierProvider<AttendanceSystemController, AttendanceSystem>(
  AttendanceSystemController.new,
);

class AttendanceSnapshotNotifier extends AsyncNotifier<AttendanceSnapshot> {
  Future<AttendanceSnapshot>? pending;
  @override
  Future<AttendanceSnapshot> build() async {
    final auth = ref.watch(authControllerProvider.select((s) => (s.initialized, s.user)));
    final system = ref.watch(attendanceSystemProvider);
    ref.watch(campusConnectionRevisionProvider);
    if (!auth.$1 || auth.$2.isGuest || auth.$2.isDemo) {
      throw StateError('请先登录学校账号后查询考勤');
    }
    var active = true;
    ref.onDispose(() => active = false);
    final store = ref.read(credentialStoreProvider);
    final session = ref.read(campusSessionProvider);
    final key = 'attendance.snapshot.${auth.$2.studentId}.${system.name}';
    AttendanceSnapshot? cached;
    try {
      final raw = await store.read(key);
      if (raw != null) cached = AttendanceSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) { /* Ignore unreadable cache, then fetch the live snapshot. */ }
    if (active && cached != null) state = AsyncData(cached);
    try {
      final result = await (pending = session.readQueue.run(() {
        if (!active) throw StateError('Sync superseded');
        return AttendanceRepository(session).load(system);
      }));
      if (active) await store.write(key: key, value: jsonEncode(result.toJson()));
      return result;
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
    await pending;
  }
}

final attendanceSnapshotProvider = AsyncNotifierProvider<AttendanceSnapshotNotifier, AttendanceSnapshot>(
  AttendanceSnapshotNotifier.new,
);
