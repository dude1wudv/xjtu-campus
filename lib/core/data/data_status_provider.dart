import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import 'data_status.dart';

class DataStatuses extends Notifier<Map<String, DataStatus>> {
  @override
  Map<String, DataStatus> build() {
    ref.watch(authControllerProvider.select((s) => (s.initialized, s.user)));
    return {};
  }

  void report(String service, DataStatus status) =>
      state = {...state, service: status};
}

final dataStatusesProvider =
    NotifierProvider<DataStatuses, Map<String, DataStatus>>(DataStatuses.new);

/// Async delivery avoids changing a different provider during build. The
/// disposal guard prevents an old account/filter request publishing late state.
void Function(DataStatus) statusReporter(Ref ref, String service) {
  var active = true;
  ref.onDispose(() => active = false);
  return (status) => scheduleMicrotask(() {
    if (active && ref.mounted)
      ref.read(dataStatusesProvider.notifier).report(service, status);
  });
}
