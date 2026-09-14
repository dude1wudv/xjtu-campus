import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/calendar/data/live_calendar_repository.dart';
import '../../features/calendar/data/mock_calendar_repository.dart';
import '../../features/calendar/domain/calendar_repository.dart';
import '../../features/exams/data/live_exams_repository.dart';
import '../../features/exams/data/mock_exams_repository.dart';
import '../../features/exams/domain/exams_repository.dart';
import '../../features/grades/data/live_grades_repository.dart';
import '../../features/grades/data/mock_grades_repository.dart';
import '../../features/grades/domain/grades_repository.dart';
import '../../features/alarms/data/local_notification_scheduler.dart';
import '../../features/alarms/domain/alarm_planner.dart';
import '../../features/alarms/domain/alarm_scheduler.dart';
import '../../features/auth/data/cas_auth_repository.dart';
import '../../features/auth/data/mock_auth_repository.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/classroom/data/live_classroom_repository.dart';
import '../../features/classroom/data/mock_classroom_repository.dart';
import '../../features/classroom/domain/classroom_repository.dart';
import '../../features/notifications/data/live_notifications_repository.dart';
import '../../features/notifications/data/mock_notifications_repository.dart';
import '../../features/notifications/domain/notifications_repository.dart';
import '../../features/schedule/data/live_schedule_repository.dart';
import '../../features/schedule/data/mock_schedule_repository.dart';
import '../../features/schedule/domain/schedule_repository.dart';
import '../network/api_client.dart';
import '../network/campus_session.dart';
import '../storage/credential_store.dart';
import '../cache/snapshot_cache.dart';
import '../storage/secure_credential_store.dart';

final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => SecureCredentialStore(),
);

final snapshotCacheProvider = Provider<SnapshotCache>(
  (ref) => SnapshotCache(),
);

final campusSessionProvider = Provider<CampusSession>((ref) {
  return CampusSession(ref.watch(credentialStoreProvider));
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.close);
  return client;
});

final mockAuthRepositoryProvider = Provider<MockAuthRepository>(
  (ref) => MockAuthRepository(ref.watch(credentialStoreProvider)),
);

/// 默认 CAS；演示登录通过 login(demo: true) 走 Mock。
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => CasAuthRepository(
    session: ref.watch(campusSessionProvider),
    store: ref.watch(credentialStoreProvider),
    mock: ref.watch(mockAuthRepositoryProvider),
  ),
);

final mockScheduleRepositoryProvider = Provider<MockScheduleRepository>(
  (ref) => MockScheduleRepository(),
);

final scheduleRepositoryProvider = Provider<ScheduleRepository>(
  (ref) => LiveScheduleRepository(
    session: ref.watch(campusSessionProvider),
    mock: ref.watch(mockScheduleRepositoryProvider),
  ),
);

final mockClassroomRepositoryProvider = Provider<MockClassroomRepository>(
  (ref) => MockClassroomRepository(),
);

final classroomRepositoryProvider = Provider<ClassroomRepository>(
  (ref) => LiveClassroomRepository(
    session: ref.watch(campusSessionProvider),
    mock: ref.watch(mockClassroomRepositoryProvider),
  ),
);

final mockNotificationsRepositoryProvider = Provider<MockNotificationsRepository>(
  (ref) => MockNotificationsRepository(),
);

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => LiveNotificationsRepository(
    session: ref.watch(campusSessionProvider),
    mock: ref.watch(mockNotificationsRepositoryProvider),
  ),
);


final mockGradesRepositoryProvider = Provider<MockGradesRepository>(
  (ref) => MockGradesRepository(),
);

final gradesRepositoryProvider = Provider<GradesRepository>(
  (ref) => LiveGradesRepository(
    session: ref.watch(campusSessionProvider),
    mock: ref.watch(mockGradesRepositoryProvider),
  ),
);

final mockExamsRepositoryProvider = Provider<MockExamsRepository>(
  (ref) => MockExamsRepository(),
);

final examsRepositoryProvider = Provider<ExamsRepository>(
  (ref) => LiveExamsRepository(
    session: ref.watch(campusSessionProvider),
    mock: ref.watch(mockExamsRepositoryProvider),
  ),
);

final mockCalendarRepositoryProvider = Provider<MockCalendarRepository>(
  (ref) => MockCalendarRepository(),
);

final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => LiveCalendarRepository(
    session: ref.watch(campusSessionProvider),
    mock: ref.watch(mockCalendarRepositoryProvider),
  ),
);

final alarmPlannerProvider = Provider<AlarmPlanner>(
  (ref) => const AlarmPlanner(),
);

final alarmSchedulerProvider = Provider<AlarmScheduler>(
  (ref) => LocalNotificationScheduler(),
);
