import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../di/core_providers.dart';
import '../network/campus_connection.dart';
import '../routing/app_router.dart';
import '../sync/campus_preload.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/settings/presentation/settings_provider.dart';
import '../../features/schedule/presentation/schedule_providers.dart';
import '../../features/calendar/domain/calendar_day_logic.dart';
import '../../features/attendance/presentation/attendance_providers.dart';
import '../../features/homework/presentation/homework_providers.dart';
import '../../features/homework/domain/homework.dart';
import '../../features/campus_card/presentation/campus_card_providers.dart';
import '../../features/library_seats/presentation/library_seats_providers.dart';
import '../../features/library_seats/domain/library_seat.dart';

const campusPlatform = MethodChannel('campus/platform');
class BackgroundState extends Notifier<bool> {
  @override
  bool build() => false;
  void update(bool value) => state = value;
  Future<bool> toggle(bool value) async {
    if (!Platform.isAndroid) return false;
    final result = await campusPlatform.invokeMethod<bool>('background', value) ?? false;
    if (ref.mounted) state = result;
    return result;
  }
}
final backgroundRunningProvider = NotifierProvider<BackgroundState, bool>(BackgroundState.new);
final widgetBookingsProvider = FutureProvider<List<LibraryBooking>>((ref) async {
  final user = ref.watch(authControllerProvider).user;
  ref.watch(campusConnectionRevisionProvider);
  if (user.isGuest || user.isDemo) return [];
  final session = ref.read(campusSessionProvider);
  await session.restore();
  return session.readQueue.run(() => ref.read(librarySeatsRepositoryProvider).myBookings());
}, retry: (count, error) => null);

class CampusPlatformSync extends ConsumerStatefulWidget {
  const CampusPlatformSync({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<CampusPlatformSync> createState() => _CampusPlatformSyncState();
}
class _CampusPlatformSyncState extends ConsumerState<CampusPlatformSync> with WidgetsBindingObserver {
  Timer? _publishTimer;
  String? _last;
  bool _refreshing = false;
  @override
  void initState() {
    super.initState();
    if (!Platform.isAndroid) return;
    WidgetsBinding.instance.addObserver(this);
    campusPlatform.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'route') _route(call.arguments);
      if (call.method == 'serviceStopped') ref.read(backgroundRunningProvider.notifier).update(false);
      if (call.method == 'refresh') await _refresh();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try { _route(await campusPlatform.invokeMethod<String>('initialRoute')); } catch (_) {}
      await _status();
    });
  }
  void _route(Object? route) {
    const allowed = ['/home', '/calendar', '/attendance', '/homework', '/campus-card', '/library-seats', '/settings'];
    if (mounted && route is String && allowed.contains(route)) {
      final router = ref.read(appRouterProvider);
      if (route == '/home' || route == '/settings') { router.go(route); return; }
      router.go('/home');
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) router.push(route); });
    }
  }
  Future<void> _status() async {
    try {
      final running = await campusPlatform.invokeMethod<bool>('status') ?? false;
      if (mounted) ref.read(backgroundRunningProvider.notifier).update(running);
    } catch (_) {}
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _status();
  }
  Future<void> _refresh() async {
    final user = ref.read(authControllerProvider).user;
    if (_refreshing || user.isGuest || user.isDemo ||
        ref.read(campusConnectionBusyProvider) || ref.read(campusPreloadProvider).busy) return;
    _refreshing = true;
    try {
      ref.invalidate(scheduleSnapshotProvider);
      ref.invalidate(attendanceSnapshotProvider);
      ref.invalidate(homeworkProvider);
      ref.invalidate(campusCardSnapshotProvider);
      ref.invalidate(widgetBookingsProvider);
      await Future.wait([
        ref.read(scheduleSnapshotProvider.future), ref.read(attendanceSnapshotProvider.future),
        ref.read(homeworkProvider.future), ref.read(campusCardSnapshotProvider.future),
        ref.read(widgetBookingsProvider.future),
      ]).timeout(const Duration(minutes: 3));
    } catch (_) { /* Each service preserves its own cached data and failure UI. */ }
    finally { _refreshing = false; }
  }
  @override
  void dispose() {
    _publishTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isAndroid) campusPlatform.setMethodCallHandler(null);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return widget.child;
    final settings = ref.watch(settingsProvider);
    final auth = ref.watch(authControllerProvider);
    if (!settings.loaded || !auth.initialized) return widget.child;
    final data = <String, String>{};
    if (settings.widgets && settings.agreement && !auth.user.isGuest && !auth.user.isDemo) {
      final schedule = ref.watch(scheduleSnapshotProvider).asData?.value;
      final attendance = ref.watch(attendanceSnapshotProvider).asData?.value;
      final homework = ref.watch(homeworkProvider).asData?.value;
      final card = ref.watch(campusCardSnapshotProvider).asData?.value;
      final bookings = ref.watch(widgetBookingsProvider);
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      if (schedule != null && (schedule.live || schedule.fromCache)) {
        for (var i = 0; i < 7; i++) {
          final day = monday.add(Duration(days: i));
          final courses = coursesOnDay(schedule.courses, day, fallbackWeek: schedule.week);
          final due = homework?.items.where((item) {
            if (item.dueAt == null) return false;
            final d = campusTime(item.dueAt!);
            return d.year == day.year && d.month == day.month && d.day == day.day;
          }).length ?? 0;
          final row = '${['周一','周二','周三','周四','周五','周六','周日'][i]} ${day.month}/${day.day}  ${courses.isEmpty ? '无课' : courses.map((c) {
            final record = attendance?.forCourse(c, day);
            return '${c.startPeriod}节 ${c.name}${record == null ? '' : ' · ${record.status.label}'}';
          }).join(' / ')}${due == 0 ? '' : ' · 作业截止 $due'}';
          data['day$i'] = row;
        }
        data['week'] = '${monday.month}/${monday.day} 起 · ${schedule.fromCache ? '缓存课表' : '本周课程'}';
      }
      if (attendance != null) data['attendance'] = '考勤 · 本学期 ${attendance.records.length} 条${attendance.fromCache ? '（缓存）' : ''}';
      if (homework != null) {
        final upcoming = homework.items.where((a) => a.status != HomeworkStatus.submitted &&
            a.dueAt != null && a.dueAt!.isAfter(now)).toList();
        data['homework'] = '作业 · ${upcoming.isEmpty ? '暂无已知待截止作业' : '${DateFormat('M/d HH:mm').format(campusTime(upcoming.first.dueAt!))} ${upcoming.first.title}'}${homework.fromCache ? '（缓存）' : ''}';
      }
      if (card?.card != null && (card!.live || card.fromCache)) data['card'] = '校园卡 · ¥${card.card!.balanceLabel}${card.fromCache ? '（缓存）' : ''}';
      final seats = bookings.asData?.value;
      if (seats != null) data['seat'] = seats.isEmpty ? '座位 · 暂无已知预约' : '座位 · ${seats.first.areaCode} ${seats.first.seatId} ${seats.first.statusLabel ?? ''}';
      final timestamps = [schedule?.cachedAt ?? schedule?.fetchedAt, attendance?.updatedAt,
        homework?.updatedAt, card?.cachedAt ?? card?.fetchedAt].whereType<DateTime>().toList()..sort();
      data['updated'] = timestamps.isEmpty ? '数据尚未同步 · 点击打开设置'
          : '缓存快照 · 最早数据 ${DateFormat('M/d HH:mm').format(timestamps.first.toLocal())}';
    }
    final encoded = jsonEncode(data);
    if (_last != encoded) {
      _last = encoded;
      _publishTimer?.cancel();
      _publishTimer = Timer(const Duration(milliseconds: 300), () async {
        try { await campusPlatform.invokeMethod('widget', data); } catch (_) { _last = null; }
      });
    }
    if (auth.user.isGuest && ref.watch(backgroundRunningProvider)) {
      Future.microtask(() async {
        if (mounted) { try { await ref.read(backgroundRunningProvider.notifier).toggle(false); } catch (_) {} }
      });
    }
    return widget.child;
  }
}
