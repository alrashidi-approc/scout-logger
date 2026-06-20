import 'package:flutter/material.dart';
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
import '../widgets/shell.dart';

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
            builder: (_, state) => OverviewScreen(projectId: state.pathParameters['projectId']!),
          ),
          GoRoute(
            path: '/p/:projectId/analytics',
            builder: (_, state) => AnalyticsScreen(projectId: state.pathParameters['projectId']!),
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
            builder: (_, state) => IssuesScreen(projectId: state.pathParameters['projectId']!),
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
            builder: (_, state) => EventsScreen(projectId: state.pathParameters['projectId']!),
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
            builder: (_, state) => GeoScreen(projectId: state.pathParameters['projectId']!),
          ),
        ],
      ),
    ],
  );
}
