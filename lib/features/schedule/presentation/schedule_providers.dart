import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/course.dart';
import '../domain/schedule_repository.dart';

final scheduleSnapshotProvider = FutureProvider<ScheduleSnapshot>((ref) {
  ref.watch(
    authControllerProvider.select(
      (state) => '${state.user.sessionToken}|${state.user.isDemo}',
    ),
  );
  return ref.watch(scheduleRepositoryProvider).load();
});

final coursesProvider = FutureProvider<List<Course>>((ref) async {
  return (await ref.watch(scheduleSnapshotProvider.future)).courses;
});

final currentWeekProvider = FutureProvider<int>((ref) async {
  return (await ref.watch(scheduleSnapshotProvider.future)).week;
});
