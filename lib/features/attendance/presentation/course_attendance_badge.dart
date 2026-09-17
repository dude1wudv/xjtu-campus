import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../schedule/domain/course.dart';
import '../domain/attendance_record.dart';
import 'attendance_providers.dart';

Color attendanceColor(AttendanceStatus status) => switch (status) {
  AttendanceStatus.normal => AppColors.success,
  AttendanceStatus.absent => AppColors.alert,
  AttendanceStatus.late || AttendanceStatus.earlyLeave => AppColors.gold,
  AttendanceStatus.leave => AppColors.navy,
  AttendanceStatus.unknown || AttendanceStatus.pending || AttendanceStatus.notRequired => AppColors.inkSoft,
};

class CourseAttendanceBadge extends ConsumerWidget {
  const CourseAttendanceBadge({super.key, required this.course, required this.day});
  final Course course;
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(attendanceSnapshotProvider);
    final snapshot = value.asData?.value;
    final record = snapshot?.forCourse(course, day);
    final pending = course.endAt(day).isAfter(DateTime.now());
    final label = record != null
        ? '${record.status.label}${snapshot!.fromCache ? ' · 缓存' : ''}'
        : pending ? '考勤待更新'
        : value.isLoading ? '考勤同步中'
        : value.hasError ? '考勤未同步' : '暂无匹配考勤';
    final color = record == null ? AppColors.inkSoft : attendanceColor(record.status);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ActionChip(
        avatar: Icon(Icons.fact_check_outlined, size: 16, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 12)),
        backgroundColor: color.withValues(alpha: 0.08),
        onPressed: () => context.push('/attendance'),
      ),
    );
  }
}
