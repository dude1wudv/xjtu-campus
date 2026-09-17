import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// Refresh is single-flight per button to avoid duplicate network/WebView work.
class ManualRefreshButton extends StatefulWidget {
  const ManualRefreshButton({
    super.key,
    required this.onRefresh,
    this.tooltip = AppStrings.manualRefresh,
  });

  final Future<void> Function() onRefresh;
  final String tooltip;

  @override
  State<ManualRefreshButton> createState() => _ManualRefreshButtonState();
}

class _ManualRefreshButtonState extends State<ManualRefreshButton> {
  bool _busy = false;

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await runManualRefresh(context, widget.onRefresh);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _busy ? AppStrings.refreshingSnack : widget.tooltip,
      onPressed: _busy ? null : _refresh,
      icon: _busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded),
    );
  }
}

Future<void> runManualRefresh(
  BuildContext context,
  Future<void> Function() onRefresh,
) async {
  try {
    await onRefresh();
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text(AppStrings.errorGeneric)),
    );
  }
}
