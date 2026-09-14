import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../domain/course.dart';

final coursesProvider = FutureProvider<List<Course>>((ref) {
  return ref.watch(scheduleRepositoryProvider).fetchCourses();
});

final currentWeekProvider = FutureProvider<int>((ref) {
  return ref.watch(scheduleRepositoryProvider).currentWeek();
});
