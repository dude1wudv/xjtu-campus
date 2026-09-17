import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/network/campus_connection.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/attendance_diagnostics.dart';
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
    final connecting = ref.watch(campusConnectionBusyProvider);
    if (connecting) {
      AttendanceDiagnostics.add('sync-auth');
      throw const AttendanceAuthenticating();
    }
    if (!auth.$1 || auth.$2.isGuest || auth.$2.isDemo) {
      AttendanceDiagnostics.add('sync-auth');
      throw const AttendanceAccountRequired();
    }
    var active = true;
    ref.onDispose(() => active = false);
    final store = ref.read(credentialStoreProvider);
    final session = ref.read(campusSessionProvider);
    final repository = AttendanceRepository(session);
    ref.onDispose(repository.cancel);
    final key = 'attendance.snapshot.${auth.$2.studentId}.${system.name}.${system.host}';
    AttendanceSnapshot? cached;
    try {
      final raw = await store.read(key);
      if (raw != null) cached = AttendanceSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (error) {
      // A corrupt cache must never prevent a live refresh, but remains useful
      // diagnostic information without exporting the parser's raw message.
      AttendanceDiagnostics.add(attendanceDiagnosticPhase(error));
    }
    if (active && cached != null) state = AsyncData(cached);
    try {
      final result = await (pending = session.readQueue.run(() {
        if (!active) throw StateError('Sync superseded');
        return repository.load(system);
      }).timeout(const Duration(seconds: 120), onTimeout: () {
        // Include time waiting behind other campus services in the UI limit.
        repository.cancel();
        throw TimeoutException('考勤同步超时，请稍后重试');
      }));
      if (active) await store.write(key: key, value: jsonEncode(result.toJson()));
      return result;
    } catch (error) {
      AttendanceDiagnostics.add(attendanceDiagnosticPhase(error));
      if (cached != null) {
        return cachedAfterAttendanceFailure(
          cached,
          error,
          useWebVpn: system.usesLegacyApi && session.useWebVpn,
        );
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

/// The login WebView temporarily owns the campus connection while it is
/// authenticating. Keep this state distinguishable from a failed sync.
class AttendanceAuthenticating implements Exception {
  const AttendanceAuthenticating();

  @override
  String toString() => '正在完成网页认证';
}

class AttendanceAccountRequired implements Exception {
  const AttendanceAccountRequired();

  @override
  String toString() => '请先登录学校账号后查询考勤';
}

String attendanceDiagnosticPhase(Object error) {
  if (error is AttendanceAuthenticating ||
      error is AttendanceAccountRequired ||
      error is AttendanceAuthRequired) {
    return 'sync-auth';
  }
  if (error is TimeoutException ||
      (error is DioException &&
          const {
            DioExceptionType.connectionTimeout,
            DioExceptionType.sendTimeout,
            DioExceptionType.receiveTimeout,
          }.contains(error.type))) {
    return 'timeout';
  }
  if (error is DioException && error.type == DioExceptionType.cancel) {
    return 'cancel';
  }
  if (error is AttendanceProtocolChanged) return 'protocol';
  if (error is FormatException) return 'parse';
  if (error is AttendanceConnectionFailed || error is AttendanceRequestFailed) {
    return 'network';
  }
  if (error is DioException) return 'network';
  return 'unknown';
}

String attendanceErrorMessage(Object? error, {required bool useWebVpn}) {
  if (error is AttendanceAuthenticating) return '正在完成网页认证，请稍候。';
  if (error is AttendanceAccountRequired) return '请先登录学校账号后查询考勤。';
  if (error is AttendanceAuthRequired) {
    return useWebVpn
        ? 'WebVPN 已启用，考勤系统仍需单独认证。请打开官方考勤系统完成登录，返回后自动同步。'
        : '请打开官方考勤系统完成认证；校外访问可先连接 WebVPN。';
  }
  if (error is AttendanceConnectionFailed) return '考勤系统连接失败，请稍后重试，无需重复登录 WebVPN。';
  if (error is AttendanceRequestFailed) return '考勤请求失败，请稍后重试。';
  if (error is AttendanceProtocolChanged) return '学校考勤接口已变化，暂时无法解析，请打开接口诊断反馈。';
  if (error is FormatException) return '学校返回的数据结构无法解析，请打开接口诊断反馈。';
  if (error is TimeoutException) return '考勤同步超时，请稍后重试。';
  if (error is DioException) {
    if (error.type == DioExceptionType.cancel) return '考勤同步已取消，请稍后重试。';
    if (const {
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    }.contains(error.type)) {
      return '考勤同步超时，请稍后重试。';
    }
    return '考勤网络请求失败，请稍后重试。';
  }
  return '考勤同步失败（原因未识别），请查看接口诊断或稍后重试。';
}

AttendanceSnapshot cachedAfterAttendanceFailure(
  AttendanceSnapshot cached,
  Object error, {
  required bool useWebVpn,
}) => AttendanceSnapshot(
      records: cached.records,
      term: cached.term,
      updatedAt: cached.updatedAt,
      fromCache: true,
      message: '${attendanceErrorMessage(error, useWebVpn: useWebVpn)}'
          '仍显示上次缓存，最新状态以学校系统为准。',
    );

final attendanceSnapshotProvider = AsyncNotifierProvider<AttendanceSnapshotNotifier, AttendanceSnapshot>(
  AttendanceSnapshotNotifier.new,
  // Authentication needs user interaction; automatic retries otherwise keep
  // restarting hidden WebViews and show a loading bar over the previous error.
  retry: (retryCount, error) => null,
);
