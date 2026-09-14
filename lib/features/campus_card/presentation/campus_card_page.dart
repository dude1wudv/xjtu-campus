import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_feedback.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/mock_campus_card_repository.dart';
import '../domain/campus_card.dart';
import 'campus_card_providers.dart';

class CampusCardPage extends ConsumerStatefulWidget {
  const CampusCardPage({super.key});

  @override
  ConsumerState<CampusCardPage> createState() => _CampusCardPageState();
}

class _CampusCardPageState extends ConsumerState<CampusCardPage> {
  CampusCardSnapshot? _softDemo;

  Future<void> _reload() async {
    setState(() => _softDemo = null);
    ref.invalidate(campusCardSnapshotProvider);
    await ref.read(campusCardSnapshotProvider.future);
  }

  Future<void> _showSoftDemo() async {
    final demo = await MockCampusCardRepository().load();
    if (!mounted) return;
    setState(() {
      _softDemo = CampusCardSnapshot(
        card: demo.card,
        transactions: demo.transactions,
        live: false,
        failed: false,
        banner: AppStrings.campusCardSoftDemoBanner,
        fetchedAt: DateTime.now(),
        totalCount: demo.totalCount,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(campusCardSnapshotProvider);
    final auth = ref.watch(authControllerProvider);
    final demo = _softDemo;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.campusCardTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: AppTokens.pagePadding,
          children: [
            if (demo != null)
              DataSourceBanner(
                live: false,
                message: demo.banner,
                fetchedAt: demo.fetchedAt ?? DateTime.now(),
              )
            else
              snap.when(
                data: (data) => DataSourceBanner(
                  live: data.live,
                  message: data.banner,
                  fromCache: data.fromCache,
                  cachedAt: data.cachedAt,
                  fetchedAt: data.fetchedAt,
                ),
                loading: () => const MockDataBanner(),
                error: (_, _) => const DataSourceBanner(
                  live: false,
                  message: AppStrings.campusCardSyncFailedBanner,
                ),
              ),
            const SizedBox(height: AppTokens.spaceMd),
            if (!auth.isLoggedIn)
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(AppStrings.campusCardLoginHint),
                    const SizedBox(height: AppTokens.spaceMd),
                    FilledButton(
                      onPressed: () => context.push('/login'),
                      child: const Text(AppStrings.openLogin),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppTokens.spaceMd),
            if (demo != null)
              _SnapshotBody(
                data: demo,
                showSoftDemo: false,
                softDemoActive: true,
                onRetry: _reload,
                onSoftDemo: _showSoftDemo,
              )
            else
              AsyncBody(
                value: snap,
                onRetry: () => ref.invalidate(campusCardSnapshotProvider),
                builder: (data) => _SnapshotBody(
                  data: data,
                  showSoftDemo: data.failed && data.card == null,
                  softDemoActive: false,
                  onRetry: _reload,
                  onSoftDemo: _showSoftDemo,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SnapshotBody extends StatelessWidget {
  const _SnapshotBody({
    required this.data,
    required this.showSoftDemo,
    required this.softDemoActive,
    required this.onRetry,
    required this.onSoftDemo,
  });

  final CampusCardSnapshot data;
  final bool showSoftDemo;
  final bool softDemoActive;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSoftDemo;

  @override
  Widget build(BuildContext context) {
    if (data.failed && data.card == null) {
      return AppSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              AppStrings.campusCardErrorTitle,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            const Text(AppStrings.campusCardSyncFailedBanner),
            const SizedBox(height: AppTokens.spaceMd),
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              children: [
                FilledButton(
                  onPressed: onRetry,
                  child: const Text(AppStrings.retry),
                ),
                if (showSoftDemo)
                  OutlinedButton(
                    onPressed: onSoftDemo,
                    child: const Text(AppStrings.campusCardViewDemo),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    final card = data.card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (card != null)
          _BalanceHero(
            card: card,
            fromCache: data.fromCache,
            cachedAt: data.cachedAt,
            fetchedAt: data.fetchedAt,
            live: data.live,
            softDemo: softDemoActive,
          ),
        const SizedBox(height: AppTokens.spaceLg),
        Text(
          AppStrings.campusCardTurnoverTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppTokens.spaceSm),
        if (data.transactions.isEmpty)
          const AppSurfaceCard(
            child: Text(AppStrings.emptyCampusCardTurnover),
          )
        else
          for (final tx in data.transactions) ...[
            _TurnoverTile(tx: tx),
            const SizedBox(height: AppTokens.spaceSm),
          ],
      ],
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({
    required this.card,
    required this.fromCache,
    required this.cachedAt,
    required this.fetchedAt,
    required this.live,
    this.softDemo = false,
  });

  final CampusCardInfo card;
  final bool fromCache;
  final DateTime? cachedAt;
  final DateTime? fetchedAt;
  final bool live;
  final bool softDemo;

  String? get _updateCaption {
    if (softDemo) {
      final when = fetchedAt ?? DateTime.now();
      return '演示数据 · ${AppStrings.updatedAtLabel(when)}';
    }
    if (fromCache && cachedAt != null) {
      return '缓存 · ${AppStrings.updatedAtLabel(cachedAt!)}';
    }
    if (live) {
      return AppStrings.freshUpdatedLabel(fetchedAt);
    }
    if (fetchedAt != null) {
      return AppStrings.updatedAtLabel(fetchedAt!);
    }
    if (cachedAt != null) {
      return '缓存 · ${AppStrings.updatedAtLabel(cachedAt!)}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final caption = _updateCaption;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navyDeep, AppColors.navy, Color(0xFF2A5A8C)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.spaceXl,
          AppTokens.spaceXl,
          AppTokens.spaceXl,
          AppTokens.spaceLg + 2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                AppStrings.campusCardBalance,
                if (card.cardType.isNotEmpty) card.cardType,
              ].join(' · '),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  card.balanceLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.05,
                  ),
                ),
                const SizedBox(width: AppTokens.spaceSm),
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    AppStrings.campusCardYuan,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            if (caption != null) ...[
              const SizedBox(height: AppTokens.spaceXs),
              Text(
                caption,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.70),
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
            if (card.pendingCents != 0) ...[
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                '${AppStrings.campusCardPending} ${card.pendingLabel} ${AppStrings.campusCardYuan}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
              ),
            ],
            if (card.expireDate.isNotEmpty) ...[
              const SizedBox(height: AppTokens.spaceXs),
              Text(
                '${AppStrings.campusCardExpire} ${card.expireDate}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
              ),
            ],
            if (card.isRestricted) ...[
              const SizedBox(height: AppTokens.spaceMd),
              Wrap(
                spacing: AppTokens.spaceSm,
                children: [
                  if (card.lost) const _StatusChip(label: AppStrings.campusCardLost),
                  if (card.frozen)
                    const _StatusChip(label: AppStrings.campusCardFrozen),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSm,
        vertical: AppTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: AppTokens.borderPill,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TurnoverTile extends StatelessWidget {
  const _TurnoverTile({required this.tx});

  final CampusCardTransaction tx;

  @override
  Widget build(BuildContext context) {
    final color = tx.isIncome
        ? AppColors.success
        : (tx.isExpense ? AppColors.alert : AppColors.navy);
    return AppSurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLg,
        vertical: AppTokens.spaceMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              tx.isIncome
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.merchant.isEmpty ? tx.typeName : tx.merchant,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceXs),
                Text(
                  [
                    if (tx.timeLabel.isNotEmpty) tx.timeLabel,
                    if (tx.typeName.isNotEmpty) tx.typeName,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tx.amountLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${AppStrings.campusCardBalanceShort} ${tx.balanceLabel}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
