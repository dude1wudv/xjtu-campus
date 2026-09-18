import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;
  static const tabs = [
    ('今天', Icons.space_dashboard_outlined, 0),
    ('课表', Icons.calendar_month_outlined, 1),
    ('自习', Icons.menu_book_outlined, 2),
    ('通知', Icons.notifications_none, 3),
    ('设置', Icons.settings_outlined, 4),
  ];
  @override
  Widget build(BuildContext context) {
    final visible = tabs
        .where((t) => !kIsWeb || [0, 1, 4].contains(t.$3))
        .toList();
    final selected = visible.indexWhere(
      (t) => t.$3 == navigationShell.currentIndex,
    );
    void navigate(int index) => navigationShell.goBranch(visible[index].$3);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1000;
        return Scaffold(
          body: Row(
            children: [
              if (desktop)
                Container(
                  width: 220,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: Color(0xFFE3E8EE))),
                  ),
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(24, 32, 24, 36),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.school_outlined,
                                size: 34,
                                color: Color(0xFF234D60),
                              ),
                              SizedBox(height: 14),
                              Text(
                                '交大校园助手',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'CAMPUS COMPANION',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.5,
                                  color: Color(0xFF677780),
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (var i = 0; i < visible.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              selected: i == selected,
                              selectedTileColor: const Color(0xFFEAF0F3),
                              leading: Icon(visible[i].$2),
                              title: Text(visible[i].$1),
                              onTap: () => navigate(i),
                            ),
                          ),
                        const Spacer(),
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            '饮水思源\n爱国荣校',
                            style: TextStyle(
                              height: 1.8,
                              letterSpacing: 4,
                              color: Color(0xFF7B898F),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(child: navigationShell),
            ],
          ),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  selectedIndex: selected < 0 ? 0 : selected,
                  onDestinationSelected: navigate,
                  destinations: [
                    for (final t in visible)
                      NavigationDestination(icon: Icon(t.$2), label: t.$1),
                  ],
                ),
        );
      },
    );
  }
}
