import 'package:go_router/go_router.dart';

import '../screens/analytics_screen.dart';
import '../screens/event_detail_screen.dart';
import '../screens/events_screen.dart';
import '../screens/geo_screen.dart';
import '../screens/issue_detail_screen.dart';
import '../screens/issues_screen.dart';
import '../screens/overview_screen.dart';
import '../screens/projects_screen.dart';
import '../screens/session_detail_screen.dart';
import '../screens/sessions_screen.dart';
import '../screens/user_detail_screen.dart';
import '../screens/users_screen.dart';
import '../widgets/shell.dart';

int? _intParam(String? v) => int.tryParse(v ?? '');

GoRouter createRouter() {
  return GoRouter(
    initialLocation: '/projects',
    routes: [
      GoRoute(
        path: '/projects',
        builder: (_, __) => const DashboardShell(projectId: null, child: ProjectsScreen()),
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
              initialDays: _intParam(state.uri.queryParameters['days']) ?? 7,
            ),
          ),
          GoRoute(
            path: '/p/:projectId/stats',
            redirect: (_, state) {
              final days = state.uri.queryParameters['days'] ?? '7';
              return '/p/${state.pathParameters['projectId']}?days=$days';
            },
          ),
          GoRoute(
            path: '/p/:projectId/users',
            builder: (_, state) => UsersScreen(
              projectId: state.pathParameters['projectId']!,
              initialDays: _intParam(state.uri.queryParameters['days']) ?? 30,
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
              initialDays: _intParam(state.uri.queryParameters['days']) ?? 7,
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
                initialDays: _intParam(q['days']),
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
                initialDays: _intParam(q['days']),
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
              initialDays: _intParam(state.uri.queryParameters['days']) ?? 7,
            ),
          ),
        ],
      ),
    ],
  );
}
