import 'package:go_router/go_router.dart';

import '../screens/admin_users_screen.dart';
import '../screens/analytics_screen.dart';
import '../screens/shared_detail_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/event_detail_screen.dart';
import '../screens/events_screen.dart';
import '../screens/geo_screen.dart';
import '../screens/issue_detail_screen.dart';
import '../screens/issues_screen.dart';
import '../screens/overview_screen.dart';
import '../screens/dashboard_logs_screen.dart';
import '../screens/project_settings_screen.dart';
import '../screens/projects_screen.dart';
import '../screens/session_detail_screen.dart';
import '../screens/sessions_screen.dart';
import '../screens/user_detail_screen.dart';
import '../screens/users_screen.dart';
import '../services/auth_service.dart';
import '../utils/date_range.dart';
import '../widgets/shell.dart';
import 'scout_page.dart';

GoRouter createRouter() {
  final auth = AuthService.instance;
  return GoRouter(
    initialLocation: '/projects',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final public = loc.startsWith('/login') ||
          loc.startsWith('/signup') ||
          loc.startsWith('/verify-email') ||
          loc.startsWith('/share/');
      if (!auth.isReady) return null;
      if (!auth.isLoggedIn && !public) return '/login';
      if (auth.isLoggedIn && (loc.startsWith('/login') || loc.startsWith('/signup') || loc.startsWith('/verify-email'))) {
        return '/projects';
      }
      if (loc.startsWith('/admin') && !auth.isAdmin) return '/projects';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (c, s) => scoutPage(s, const LoginScreen()),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (c, s) => scoutPage(s, const SignupScreen()),
      ),
      GoRoute(
        path: '/verify-email',
        pageBuilder: (c, s) => scoutPage(
          s,
          VerifyEmailScreen(
            email: s.uri.queryParameters['email'],
            token: s.uri.queryParameters['token'],
          ),
        ),
      ),
      GoRoute(
        path: '/share/:token',
        pageBuilder: (c, s) => scoutPage(s, SharedDetailScreen(token: s.pathParameters['token']!)),
      ),
      GoRoute(
        path: '/projects',
        pageBuilder: (c, s) => scoutPage(s, const DashboardShell(projectId: null, child: ProjectsScreen())),
      ),
      GoRoute(
        path: '/admin/users',
        pageBuilder: (c, s) => scoutPage(s, const DashboardShell(projectId: null, child: AdminUsersScreen())),
      ),
      ShellRoute(
        builder: (context, state, child) {
          final id = state.pathParameters['projectId'];
          return DashboardShell(projectId: id, child: child);
        },
        routes: [
          GoRoute(
            path: '/p/:projectId',
            pageBuilder: (c, s) => scoutPage(
              s,
              OverviewScreen(
                projectId: s.pathParameters['projectId']!,
                initialPeriod: PeriodFilter.parse(s.uri.queryParameters),
              ),
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
            pageBuilder: (c, s) => scoutPage(
              s,
              UsersScreen(
                projectId: s.pathParameters['projectId']!,
                initialPeriod: PeriodFilter.parse(s.uri.queryParameters, defaultDays: 30),
              ),
            ),
            routes: [
              GoRoute(
                path: ':userId',
                pageBuilder: (c, s) => scoutPage(
                  s,
                  UserDetailScreen(
                    projectId: s.pathParameters['projectId']!,
                    userId: Uri.decodeComponent(s.pathParameters['userId']!),
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/p/:projectId/sessions',
            pageBuilder: (c, s) => scoutPage(
              s,
              SessionsScreen(
                projectId: s.pathParameters['projectId']!,
                initialPeriod: PeriodFilter.parse(s.uri.queryParameters),
              ),
            ),
            routes: [
              GoRoute(
                path: ':sessionId',
                pageBuilder: (c, s) => scoutPage(
                  s,
                  SessionDetailScreen(
                    projectId: s.pathParameters['projectId']!,
                    sessionId: s.pathParameters['sessionId']!,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/p/:projectId/analytics',
            pageBuilder: (c, s) => scoutPage(
              s,
              AnalyticsScreen(
                projectId: s.pathParameters['projectId']!,
                initialTab: s.uri.queryParameters['tab'],
                initialPeriod: PeriodFilter.parse(s.uri.queryParameters, defaultDays: 30),
              ),
            ),
            routes: [
              GoRoute(
                path: 'sessions/:sessionId',
                pageBuilder: (c, s) => scoutPage(
                  s,
                  SessionDetailScreen(
                    projectId: s.pathParameters['projectId']!,
                    sessionId: s.pathParameters['sessionId']!,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/p/:projectId/issues',
            pageBuilder: (c, s) {
              final q = s.uri.queryParameters;
              return scoutPage(
                s,
                IssuesScreen(
                  projectId: s.pathParameters['projectId']!,
                  initialType: q['type'],
                  initialStatus: q['status'],
                  initialPeriod: PeriodFilter.parseOptional(q) ?? const PeriodFilter.days(30),
                  initialQuery: q['q'],
                  initialEnvironment: q['environment'],
                  initialAppVersion: q['appVersion'],
                ),
              );
            },
            routes: [
              GoRoute(
                path: ':issueId',
                pageBuilder: (c, s) => scoutPage(
                  s,
                  IssueDetailScreen(
                    projectId: s.pathParameters['projectId']!,
                    issueId: s.pathParameters['issueId']!,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/p/:projectId/events',
            pageBuilder: (c, s) {
              final q = s.uri.queryParameters;
              return scoutPage(
                s,
                EventsScreen(
                  projectId: s.pathParameters['projectId']!,
                  initialType: q['type'],
                  initialLevel: q['level'],
                  initialCategory: q['category'],
                  initialPeriod: PeriodFilter.parseOptional(q) ?? const PeriodFilter.days(30),
                  initialQuery: q['q'],
                  initialCountry: q['country'],
                  initialEnvironment: q['environment'],
                  initialAppVersion: q['appVersion'],
                ),
              );
            },
            routes: [
              GoRoute(
                path: ':eventId',
                pageBuilder: (c, s) => scoutPage(
                  s,
                  EventDetailScreen(
                    projectId: s.pathParameters['projectId']!,
                    eventId: s.pathParameters['eventId']!,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/p/:projectId/geo',
            pageBuilder: (c, s) => scoutPage(
              s,
              GeoScreen(
                projectId: s.pathParameters['projectId']!,
                initialPeriod: PeriodFilter.parse(s.uri.queryParameters),
              ),
            ),
          ),
          GoRoute(
            path: '/p/:projectId/logs',
            pageBuilder: (c, s) => scoutPage(s, DashboardLogsScreen(projectId: s.pathParameters['projectId']!)),
          ),
          GoRoute(
            path: '/p/:projectId/settings',
            pageBuilder: (c, s) => scoutPage(s, ProjectSettingsScreen(projectId: s.pathParameters['projectId']!)),
          ),
        ],
      ),
    ],
  );
}
