import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/settings/presentation/settings_provider.dart';

/// Blur is reserved for navigation and hero surfaces, not every scrolling row.
class GlassSurface extends ConsumerWidget {
  const GlassSurface({super.key, required this.child, this.radius = 28, this.blur = true, this.shadow = true});
  final Widget child;
  final double radius;
  final bool blur;
  final bool shadow;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = blur && ref.watch(settingsProvider).glass && !MediaQuery.disableAnimationsOf(context);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: enabled ? .76 : .97),
            const Color(0xFFEAF0FF).withValues(alpha: enabled ? .58 : .97)]),
        border: Border.all(color: Colors.white.withValues(alpha: .85), width: 1.2),
      ), child: child);
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), boxShadow: shadow ? [
        BoxShadow(color: const Color(0xFF344C73).withValues(alpha: .07), blurRadius: 24, offset: const Offset(0, 8)),
      ] : []),
      child: ClipRRect(borderRadius: BorderRadius.circular(radius),
        child: enabled ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: surface) : surface),
    );
  }
}
