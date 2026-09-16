import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// AppBar action: force network refresh (bypass SnapshotCache).
class ManualRefreshButton extends StatelessWidget {
  const ManualRefreshButton({
    super.key,
    required this.onRefresh,
    this.tooltip = AppStrings.manualRefresh,
  });

  final Future<void> Function() onRefresh;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.refresh_rounded),
      onPressed: () => runManualRefresh(context, onRefresh),
    );
  }
}

/// Shows a brief「正在刷新…」SnackBar, runs [onRefresh], then clears it.
Future<void> runManualRefresh(
  BuildContext context,
  Future<void> Function() onRefresh,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    const SnackBar(
      content: Text(AppStrings.refreshingSnack),
      duration: Duration(seconds: 90),
    ),
  );
  try {
    await onRefresh();
  } finally {
    messenger?.hideCurrentSnackBar();
  }
}
