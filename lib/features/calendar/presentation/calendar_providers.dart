import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../schedule/presentation/schedule_providers.dart';
import '../domain/school_calendar.dart';

final calendarSnapshotProvider = FutureProvider<CalendarSnapshot>((ref) async {
  final schedule = ref.watch(scheduleSnapshotProvider);
  final scheduleWeek = schedule.asData?.value.week;
  return ref.watch(calendarRepositoryProvider).load(
        scheduleWeek: scheduleWeek,
      );
});
