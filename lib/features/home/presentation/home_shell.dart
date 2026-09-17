import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    (label: AppStrings.navHome, icon: Icons.home_outlined, selected: Icons.home_rounded),
    (label: AppStrings.navSchedule, icon: Icons.calendar_view_week_outlined, selected: Icons.calendar_view_week),
    (label: AppStrings.navClassroom, icon: Icons.meeting_room_outlined, selected: Icons.meeting_room),
    (label: AppStrings.navNotices, icon: Icons.campaign_outlined, selected: Icons.campaign),
    (label: AppStrings.navAlarms, icon: Icons.alarm_outlined, selected: Icons.alarm),
  ];

  void _select(int index) {
    // Preserve scroll and filters when the current destination is tapped again.
    if (index != navigationShell.currentIndex) navigationShell.goBranch(index);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: Row(
        children: [
          if (wide) ...[
            SafeArea(
              child: NavigationRail(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                backgroundColor: AppColors.card,
                indicatorColor: AppColors.chip,
                destinations: [
                  for (final destination in _destinations)
                    NavigationRailDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selected),
                      label: Text(destination.label),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
          ],
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: wide || keyboardOpen
          ? null
          : DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.card,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: NavigationBar(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _select,
                destinations: [
                  for (final destination in _destinations)
                    NavigationDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selected),
                      label: destination.label,
                    ),
                ],
              ),
            ),
    );
  }
}
