import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/data_status_banner.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/schedule_repository.dart';
import 'schedule_providers.dart';

class ScheduleStatus extends ConsumerWidget {
  const ScheduleStatus({super.key, required this.value});
  final AsyncValue<ScheduleSnapshot> value;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ServiceStatusBanner(
          service: 'schedule',
          onRetry: () => ref.invalidate(scheduleSnapshotProvider),
        ),
        if (!kIsWeb &&
            (ref.watch(authControllerProvider).user.isGuest ||
                ref.watch(authControllerProvider).user.isDemo))
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push('/login'),
              child: const Text('登录查看个人课表'),
            ),
          ),
      ],
    ),
  );
}

class ScheduleSkeleton extends StatelessWidget {
  const ScheduleSkeleton({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在加载课程',
    child: Column(
      children: [
        const LinearProgressIndicator(minHeight: 2),
        for (var i = 0; i < 3; i++)
          Container(
            height: 92,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8EDF1),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
      ],
    ),
  );
}
