import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// Shared surface with an ink layer for both whole-card and nested actions.
class AppSurfaceCard extends StatelessWidget {
  const AppSurfaceCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.radius,
    this.softShadow = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? radius;
  final bool softShadow;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? AppTokens.radiusLg;
    final borderRadius = BorderRadius.circular(r);
    final content = Padding(
      padding: padding ?? AppTokens.cardPadding,
      child: child,
    );

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: borderRadius,
        border: Border.all(color: AppColors.line),
        boxShadow: softShadow ? AppTokens.softCardShadow : null,
      ),
      child: Material(
        color: AppColors.card,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius: borderRadius,
                child: content,
              ),
      ),
    );
  }
}
