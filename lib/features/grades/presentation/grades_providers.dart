import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/grade_record.dart';

final gradesSnapshotProvider = FutureProvider<GradesSnapshot>((ref) {
  ref.watch(
    authControllerProvider.select(
      (state) => '${state.user.sessionToken}|${state.user.isDemo}',
    ),
  );
  return ref.watch(gradesRepositoryProvider).load();
});
