import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/academics/presentation/academics_page.dart';
import '../../features/alarms/presentation/alarms_page.dart';
import '../../features/attendance/presentation/attendance_page.dart';
import '../../features/auth/presentation/cas_web_login_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/calendar/presentation/calendar_page.dart';
import '../../features/campus_card/presentation/campus_card_page.dart';
import '../../features/campus_card/presentation/ncard_sync_page.dart';
import '../../features/classroom/presentation/classroom_page.dart';
import '../../features/exams/presentation/exams_page.dart';
import '../../features/grades/presentation/grades_page.dart';
import '../../features/home/presentation/home_dashboard.dart';
import '../../features/homework/presentation/homework_page.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/library_seats/presentation/library_seats_page.dart';
import '../../features/network/presentation/webvpn_page.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/schedule/presentation/schedule_page.dart';
import '../widgets/in_app_browser_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/homework', builder: (context, state) => const HomeworkPage()),
      GoRoute(path: '/homework/:id', builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '');
        return id == null ? const HomeworkPage() : HomeworkDetailPage(id: id);
      }),
      GoRoute(path: '/attendance', builder: (context, state) => const AttendancePage()),
      GoRoute(path: '/webvpn', builder: (context, state) => const WebVpnPage()),
      GoRoute(
        path: '/login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/login/web',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final id = state.uri.queryParameters['studentId'] ?? '';
          return CasWebLoginPage(studentId: id);
        },
      ),
      GoRoute(
        path: '/browser',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra;
          String? urlFromExtra;
          String? titleFromExtra;
          if (extra is Map) {
            final rawUrl = extra['url'];
            final rawTitle = extra['title'];
            if (rawUrl != null) urlFromExtra = rawUrl.toString();
            if (rawTitle != null) titleFromExtra = rawTitle.toString();
          }
          final url = urlFromExtra ??
              (state.uri.queryParameters['url'] == null
                  ? null
                  : Uri.decodeComponent(state.uri.queryParameters['url']!));
          final title = titleFromExtra ??
              (state.uri.queryParameters['title'] == null
                  ? null
                  : Uri.decodeComponent(state.uri.queryParameters['title']!));
          return InAppBrowserPage(
            initialUrl: url ?? '',
            title: title,
          );
        },
      ),
      GoRoute(
        path: '/academics',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AcademicsPage(),
      ),
      GoRoute(
        path: '/grades',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const GradesPage(),
      ),
      GoRoute(
        path: '/exams',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ExamsPage(),
      ),
      GoRoute(
        path: '/calendar',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CalendarPage(),
      ),
      GoRoute(
        path: '/campus-card',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CampusCardPage(),
      ),
      GoRoute(
        path: '/campus-card/sync',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const NcardSyncPage(),
      ),
      GoRoute(
        path: '/library-seats',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LibrarySeatsPage(),
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
