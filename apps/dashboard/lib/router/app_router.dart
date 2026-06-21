import 'package:go_router/go_router.dart';

import '../screens/admin_users_screen.dart';
import '../screens/analytics_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/event_detail_screen.dart';
import '../screens/events_screen.dart';
import '../screens/geo_screen.dart';
import '../screens/issue_detail_screen.dart';
import '../screens/issues_screen.dart';
import '../screens/overview_screen.dart';
import '../screens/project_settings_screen.dart';
import '../screens/projects_screen.dart';
import '../screens/session_detail_screen.dart';
import '../screens/sessions_screen.dart';
import '../screens/user_detail_screen.dart';
import '../screens/users_screen.dart';
import '../services/auth_service.dart';
import '../utils/date_range.dart';
import '../widgets/shell.dart';

GoRouter createRouter() {
  final auth = AuthService.instance;
  return GoRouter(
    initialLocation: '/projects',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final public = loc.startsWith('/login') || loc.startsWith('/signup') || loc.startsWith('/verify-email');
      if (!auth.isReady) return null;
      if (!auth.isLoggedIn && !public) return '/login';
      if (auth.isLoggedIn && public) return '/projects';
      if (loc.startsWith('/admin') && !auth.isAdmin) return '/projects';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(
        path: '/verify-email',
        builder: (_, state) => VerifyEmailScreen(
          email: state.uri.queryParameters['email'],
          token: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        path: '/projects',
        builder: (_, __) => const DashboardShell(projectId: null, child: ProjectsScreen()),
      ),
      GoRoute(
        path: '/admin/users',
        builder: (_, __) => const DashboardShell(projectId: null, child: AdminUsersScreen()),
      ),
      ShellRoute(
        builder: (context, state, child) {
          final id = state.pathParameters['projectId'];
          return DashboardShell(projectId: id, child: child);
        },
        routes: [
          GoRoute(
            path: '/p/:projectId',
            builder: (_, state) => OverviewScreen(
              projectId: state.pathParameters['projectId']!,
              initialPeriod: PeriodFilter.parse(state.uri.queryParameters),
            ),
          ),
          GoRoute(
            path: '/p/:projectId/stats',
            redirect: (_, state) {
              final q = state.uri.queryParameters;
              final period = PeriodFilter.parse(q);
              return Uri(path: '/p/${state.pathParameters['projectId']}', queryParameters: period.toQuery()).toString();
            },
          ),
          GoRoute(
            path: '/p/:projectId/users',
            builder: (_, state) => UsersScreen(
              projectId: state.pathParameters['projectId']!,
              initialPeriod: PeriodFilter.parse(state.uri.queryParameters, defaultDays: 30),
            ),
            routes: [
              GoRoute(
                path: ':userId',
                builder: (_, state) => UserDetailScreen(
                  projectId: state.pathParameters['projectId']!,
                  userId: Uri.decodeComponent(state.pathParameters['userId']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/p/:projectId/sessions',
            builder: (_, state) => SessionsScreen(
              projectId: state.pathParameters['projectId']!,
              initialPeriod: PeriodFilter.parse(state.uri.queryParameters),
            ),
            routes: [
              GoRoute(
                path: ':sessionId',
                builder: (_, state) => SessionDetailScreen(
                  projectId: state.pathParameters['projectId']!,
                  sessionId: state.pathParameters['sessionId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/p/:projectId/analytics',
            builder: (_, state) => AnalyticsScreen(
              projectId: state.pathParameters['projectId']!,
              initialTab: state.uri.queryParameters['tab'],
              initialPeriod: PeriodFilter.parse(state.uri.queryParameters, defaultDays: 30),
            ),
            routes: [
              GoRoute(
                path: 'sessions/:sessionId',
                builder: (_, state) => SessionDetailScreen(
                  projectId: state.pathParameters['projectId']!,
                  sessionId: state.pathParameters['sessionId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/p/:projectId/issues',
            builder: (_, state) {
              final q = state.uri.queryParameters;
              return IssuesScreen(
                projectId: state.pathParameters['projectId']!,
                initialType: q['type'],
                initialStatus: q['status'],
                initialPeriod: PeriodFilter.parseOptional(q) ?? const PeriodFilter.days(30),
                initialQuery: q['q'],
              );
            },
            routes: [
              GoRoute(
                path: ':issueId',
                builder: (_, state) => IssueDetailScreen(
                  projectId: state.pathParameters['projectId']!,
                  issueId: state.pathParameters['issueId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/p/:projectId/events',
            builder: (_, state) {
              final q = state.uri.queryParameters;
              return EventsScreen(
                projectId: state.pathParameters['projectId']!,
                initialType: q['type'],
                initialLevel: q['level'],
                initialCategory: q['category'],
                initialPeriod: PeriodFilter.parseOptional(q) ?? const PeriodFilter.days(7),
                initialQuery: q['q'],
                initialCountry: q['country'],
              );
            },
            routes: [
              GoRoute(
                path: ':eventId',
                builder: (_, state) => EventDetailScreen(
                  projectId: state.pathParameters['projectId']!,
                  eventId: state.pathParameters['eventId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/p/:projectId/geo',
            builder: (_, state) => GeoScreen(
              projectId: state.pathParameters['projectId']!,
              initialPeriod: PeriodFilter.parse(state.uri.queryParameters),
            ),
          ),
          GoRoute(
            path: '/p/:projectId/settings',
            builder: (_, state) => ProjectSettingsScreen(projectId: state.pathParameters['projectId']!),
          ),
        ],
      ),
    ],
  );
}
