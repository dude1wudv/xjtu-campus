import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/data_status.dart';
import '../data/data_status_provider.dart';

class ServiceStatusBanner extends ConsumerWidget {
  const ServiceStatusBanner({
    super.key,
    required this.service,
    this.fallback,
    this.onRetry,
    this.loginRoute = '/login',
    this.onLogin,
  });
  final String service;
  final DataStatus? fallback;
  final VoidCallback? onRetry;
  final String loginRoute;
  final VoidCallback? onLogin;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status =
        ref.watch(dataStatusesProvider.select((s) => s[service])) ??
        fallback ??
        const DataStatus.loading();
    return DataStatusBanner(
      status: status,
      onRetry: onRetry,
      loginRoute: loginRoute,
      onLogin: onLogin,
    );
  }
}

class DataStatusBanner extends StatelessWidget {
  const DataStatusBanner({
    super.key,
    required this.status,
    this.onRetry,
    this.loginRoute = '/login',
    this.onLogin,
  });
  final DataStatus status;
  final VoidCallback? onRetry;
  final String loginRoute;
  final VoidCallback? onLogin;
  @override
  Widget build(BuildContext context) {
    final warning = status.problem != null || status.source == DataSource.cache;
    final color = warning ? const Color(0xFF986421) : const Color(0xFF234D60);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .065),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            status.needsLogin
                ? Icons.lock_clock_outlined
                : warning
                ? Icons.cloud_off_outlined
                : status.source == DataSource.local
                ? Icons.devices
                : Icons.sync,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${status.title} · ${status.sourceLabel}',
                  style: TextStyle(fontWeight: FontWeight.w600, color: color),
                ),
                if (status.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      status.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (status.updatedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '更新于 ${DateFormat('M月d日 HH:mm').format(status.updatedAt!.toUtc().add(const Duration(hours: 8)))}（北京时间）',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (status.isBusy)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
          ),
          if (status.needsLogin)
            TextButton(
              onPressed: onLogin ?? () => context.push(loginRoute),
              child: const Text('去认证'),
            )
          else if (onRetry != null &&
              !status.isBusy &&
              (status.problem != null || status.source == DataSource.cache))
            TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
