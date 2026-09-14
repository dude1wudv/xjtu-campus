import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/alarms/presentation/alarms_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/classroom/presentation/classroom_page.dart';
import '../../features/home/presentation/home_dashboard.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/schedule/presentation/schedule_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LoginPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return HomeShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: HomeDashboard(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/schedule',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: SchedulePage(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/classroom',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: ClassroomPage(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/notices',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: NotificationsPage(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/alarms',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: AlarmsPage(),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
