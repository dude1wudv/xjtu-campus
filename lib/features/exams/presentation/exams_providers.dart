import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/exam_arrangement.dart';

final examsSnapshotProvider = FutureProvider<ExamsSnapshot>((ref) {
  ref.watch(
    authControllerProvider.select(
      (state) => '${state.user.sessionToken}|${state.user.isDemo}',
    ),
  );
  return ref.watch(examsRepositoryProvider).load();
});
