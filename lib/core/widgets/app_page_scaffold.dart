import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Shared page frame for root tabs and pushed pages, including landscape insets.
class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5F7F8), Color(0xFFF5F7F8), Color(0xFFF5F7F8)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        body: SafeArea(
          top: appBar == null,
          bottom: bottomNavigationBar == null,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTokens.contentWidth,
              ),
              child: SizedBox(width: double.infinity, child: body),
            ),
          ),
        ),
        bottomNavigationBar: bottomNavigationBar == null
            ? null
            : ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  top: false,
                  child: Align(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppTokens.contentWidth,
                      ),
                      child: bottomNavigationBar,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
