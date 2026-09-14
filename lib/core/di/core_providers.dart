import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/alarms/data/stub_alarm_scheduler.dart';
import '../../features/alarms/domain/alarm_planner.dart';
import '../../features/alarms/domain/alarm_scheduler.dart';
import '../../features/auth/data/mock_auth_repository.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/classroom/data/mock_classroom_repository.dart';
import '../../features/classroom/domain/classroom_repository.dart';
import '../../features/notifications/data/mock_notifications_repository.dart';
import '../../features/notifications/domain/notifications_repository.dart';
import '../../features/schedule/data/mock_schedule_repository.dart';
import '../../features/schedule/domain/schedule_repository.dart';
import '../network/api_client.dart';
import '../storage/credential_store.dart';
import '../storage/secure_credential_store.dart';

final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => SecureCredentialStore(),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.close);
  return client;
});

/// 后续替换为 CasAuthRepository（login.xjtu.edu.cn）。
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => MockAuthRepository(ref.watch(credentialStoreProvider)),
);

/// 后续替换为 EhallScheduleRepository。
final scheduleRepositoryProvider = Provider<ScheduleRepository>(
  (ref) => MockScheduleRepository(),
);

final classroomRepositoryProvider = Provider<ClassroomRepository>(
  (ref) => MockClassroomRepository(),
);

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => MockNotificationsRepository(),
);

final alarmPlannerProvider = Provider<AlarmPlanner>((ref) => const AlarmPlanner());

final alarmSchedulerProvider = Provider<AlarmScheduler>(
  (ref) => StubAlarmScheduler(),
);
