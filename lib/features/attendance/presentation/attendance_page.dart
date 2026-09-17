import 'attendance_diagnostics_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/network/campus_connection.dart';
import '../../../core/widgets/app_page_scaffold.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../../core/widgets/manual_refresh_button.dart';
import '../data/attendance_repository.dart';
import '../domain/attendance_record.dart';
import 'attendance_providers.dart';
import 'course_attendance_badge.dart';

class AttendancePage extends ConsumerStatefulWidget {
  const AttendancePage({super.key});
  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  String _keyword = '';
  AttendanceStatus? _status;
  DateTimeRange? _range;
  Object? _refreshFailure;

  Future<void> _openOfficial() async {
    if (mounted) setState(() => _refreshFailure = null);
    await context.push('/attendance/login');
    if (mounted) ref.invalidate(attendanceSnapshotProvider);
  }

  Future<void> _openSchoolLogin() async {
    if (mounted) setState(() => _refreshFailure = null);
    await context.push('/login');
    if (mounted) ref.invalidate(attendanceSnapshotProvider);
  }

  /// Keep refresh errors in this page so ManualRefreshButton cannot replace
  /// the attendance-specific reason with the app-wide generic SnackBar.
  Future<void> _refreshAttendance() async {
    if (mounted) setState(() => _refreshFailure = null);
    try {
      await ref.read(attendanceSnapshotProvider.notifier).refresh();
    } catch (error) {
      if (mounted) setState(() => _refreshFailure = error);
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(context: context,
      firstDate: DateTime(now.year - 1), lastDate: now, initialDateRange: _range);
    if (mounted && range != null) setState(() => _range = range);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AttendanceSnapshot>>(attendanceSnapshotProvider,
        (_, next) {
      final snapshot = next.asData?.value;
      if (snapshot != null && !snapshot.fromCache && mounted &&
          _refreshFailure != null) {
        setState(() => _refreshFailure = null);
      }
    });
    final system = ref.watch(attendanceSystemProvider);
    final value = ref.watch(attendanceSnapshotProvider);
    ref.watch(campusConnectionRevisionProvider);
    final useWebVpn = system.usesLegacyApi &&
        ref.read(campusSessionProvider).useWebVpn;
    final data = value.asData?.value;
    final error = _refreshFailure ?? (value.hasError ? value.error : null);
    final records = (data?.records ?? const <AttendanceRecord>[]).where((record) {
      final matchDate = _range == null ||
          (!record.date.isBefore(_range!.start) && !record.date.isAfter(_range!.end));
      return matchDate && (_status == null || record.status == _status) &&
          '${record.courseName} ${record.location} ${record.teacher}'.toLowerCase().contains(_keyword.toLowerCase());
    }).toList();
    return AppPageScaffold(
      appBar: AppBar(title: const Text('考勤查询'), actions: [
        IconButton(tooltip: '接口诊断', onPressed: () => showAttendanceDiagnostics(context), icon: const Icon(Icons.bug_report_outlined)),
        IconButton(tooltip: '官方考勤系统', onPressed: _openOfficial, icon: const Icon(Icons.open_in_browser)),
        ManualRefreshButton(onRefresh: _refreshAttendance),
      ]),
      body: RefreshIndicator(
        onRefresh: _refreshAttendance,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: AppTokens.pagePadding,
          itemCount: records.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<AttendanceSystem>(
                segments: [for (final item in AttendanceSystem.values)
                  ButtonSegment(value: item, label: Text(item.label))],
                selected: {system},
                onSelectionChanged: (selection) {
                  setState(() { _range = null; _status = null; _refreshFailure = null; });
                  ref.read(attendanceSystemProvider.notifier).select(selection.single);
                },
              ),
              const SizedBox(height: 16),
              AppSurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(data == null ? '本学期考勤' : '${data.term} · ${data.records.length} 条记录',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(data == null ? '同步学校考勤记录，不将未返回的记录推断为缺勤。'
                    : '${data.fromCache ? '缓存 · ' : '更新于 '}${DateFormat('M月d日 HH:mm').format(data.updatedAt)}'),
                if (data?.message != null) Text(data!.message!),
                if (data != null) Wrap(spacing: 8, children: [
                  for (final status in AttendanceStatus.values)
                    Chip(label: Text('${status.label} ${data.records.where((r) => r.status == status).length}')),
                ]),
              ])),
              const SizedBox(height: 12),
              TextField(onChanged: (value) => setState(() => _keyword = value.trim()),
                decoration: const InputDecoration(hintText: '搜索课程、教师或教室', prefixIcon: Icon(Icons.search))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                FilterChip(label: const Text('全部状态'), selected: _status == null,
                    onSelected: (_) => setState(() => _status = null)),
                for (final status in AttendanceStatus.values)
                  FilterChip(label: Text(status.label), selected: _status == status,
                      onSelected: (_) => setState(() => _status = status)),
                ActionChip(label: Text(_range == null ? '筛选日期' : '${DateFormat('M/d').format(_range!.start)}–${DateFormat('M/d').format(_range!.end)}'),
                    onPressed: _pickRange),
                if (_range != null) ActionChip(label: const Text('清除日期'), onPressed: () => setState(() => _range = null)),
              ]),
              const SizedBox(height: 12),
              if (value.isLoading) ...[
                const LinearProgressIndicator(),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('正在同步考勤，请稍候…'),
                ),
              ],
              if (error != null && !value.isLoading) AppSurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(attendanceErrorMessage(error, useWebVpn: useWebVpn)),
                const SizedBox(height: 12),
                if (error is AttendanceAccountRequired)
                  FilledButton(onPressed: _openSchoolLogin,
                      child: const Text('登录学校账号'))
                else if (error is AttendanceAuthRequired)
                  FilledButton(onPressed: _openOfficial, child: const Text('打开官方考勤系统'))
                else
                  FilledButton(onPressed: error is AttendanceAuthenticating
                      ? null : _refreshAttendance,
                      child: const Text('重新同步考勤')),
                if (system.usesLegacyApi && !useWebVpn)
                  TextButton(onPressed: () => context.push('/webvpn'), child: const Text('连接 WebVPN')),
                if (error is! AttendanceAccountRequired &&
                    error is! AttendanceAuthRequired &&
                    error is! AttendanceAuthenticating)
                  TextButton(onPressed: _openOfficial, child: const Text('打开官方考勤系统')),
              ])),
              if (data != null && records.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Text('当前筛选范围暂无记录', textAlign: TextAlign.center)),
            ]);
            final record = records[index - 1];
            return AppSurfaceCard(
              margin: const EdgeInsets.only(top: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(record.courseName.isEmpty ? '课程考勤' : record.courseName,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('${DateFormat('M月d日').format(record.date)} · '
                    '${record.startPeriod > 0 && record.endPeriod >= record.startPeriod
                        ? '第${record.startPeriod}–${record.endPeriod}节' : '节次未知'}'),
                Text([record.location, record.teacher].where((v) => v.isNotEmpty).join(' · ')),
                const SizedBox(height: 8),
                Text(record.status.label, style: TextStyle(color: attendanceColor(record.status), fontWeight: FontWeight.w700)),
              ]),
            );
          },
        ),
      ),
    );
  }
}
