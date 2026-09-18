import 'package:go_router/go_router.dart';

import '../data/data_status.dart';
import 'data_status_banner.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

class DataSourceBanner extends StatelessWidget {
  const DataSourceBanner({
    super.key,
    this.live = false,
    this.message,
    this.fromCache = false,
    this.cachedAt,
    this.fetchedAt,
    this.service,
    this.onRetry,
    this.loginRoute = '/login',
  });

  final String? service;
  final VoidCallback? onRetry;
  final String loginRoute;
  final bool live;
  final String? message;

  /// When true, show 「缓存」chip and prefer [cachedAt] for secondary time.
  final bool fromCache;
  final DateTime? cachedAt;
  final DateTime? fetchedAt;

  String? get _timeCaption {
    if (fromCache && cachedAt != null) {
      return AppStrings.updatedAtLabel(cachedAt!);
    }
    if (live && !fromCache && fetchedAt != null) {
      return AppStrings.freshUpdatedLabel(fetchedAt!);
    }
    if (cachedAt != null) {
      return AppStrings.updatedAtLabel(cachedAt!);
    }
    if (fetchedAt != null) {
      return AppStrings.updatedAtLabel(fetchedAt!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (service != null)
      return ServiceStatusBanner(
        service: service!,
        onRetry: onRetry,
        loginRoute: loginRoute,
      );
    final text =
        message ?? (live ? AppStrings.liveBanner : AppStrings.mockBanner);
    final color = fromCache
        ? AppColors.gold
        : (live ? AppColors.success : AppColors.gold);
    final timeCaption = _timeCaption;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm + 2),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            fromCache
                ? Icons.history_rounded
                : (live ? Icons.check_circle_outline : Icons.info_outline),
            size: 16,
            color: color,
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (fromCache) ...[
                      Container(
                        margin: const EdgeInsets.only(right: 6, top: 1),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          AppStrings.cacheChip,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: color,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppColors.inkSoft,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (timeCaption != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    timeCaption,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.inkSoft,
                      fontSize: 11.5,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MockDataBanner extends StatelessWidget {
  const MockDataBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return const DataSourceBanner();
  }
}

class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      data: builder,
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(20),
        child: DataStatusBanner(
          status: DataStatus(
            phase: DataPhase.failed,
            problem: dataProblem(error),
          ),
          onRetry: onRetry,
          onLogin: () => context.push('/login'),
        ),
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return _Message(icon: icon, title: text);
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.chip,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 28, color: AppColors.navy),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.ink,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onRetry,
                child: const Text(AppStrings.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
