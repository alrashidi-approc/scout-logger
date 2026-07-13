import 'package:flutter/material.dart';

import '../screens/analytics_screen.dart' deferred as analytics;
import '../screens/geo_screen.dart' deferred as geo;
import '../screens/reports_screen.dart' deferred as reports;
import '../utils/date_range.dart';
import 'deferred_screen.dart';

class DeferredGeoScreen extends StatelessWidget {
  const DeferredGeoScreen({super.key, required this.projectId, this.initialPeriod = const PeriodFilter.days(7)});

  final String projectId;
  final PeriodFilter initialPeriod;

  @override
  Widget build(BuildContext context) => DeferredScreen(
        loadLibrary: geo.loadLibrary,
        builder: () => geo.GeoScreen(projectId: projectId, initialPeriod: initialPeriod),
      );
}

class DeferredAnalyticsScreen extends StatelessWidget {
  const DeferredAnalyticsScreen({
    super.key,
    required this.projectId,
    this.initialTab,
    this.initialPeriod = const PeriodFilter.days(30),
  });

  final String projectId;
  final String? initialTab;
  final PeriodFilter initialPeriod;

  @override
  Widget build(BuildContext context) => DeferredScreen(
        loadLibrary: analytics.loadLibrary,
        builder: () => analytics.AnalyticsScreen(
          projectId: projectId,
          initialTab: initialTab,
          initialPeriod: initialPeriod,
        ),
      );
}

class DeferredReportsScreen extends StatelessWidget {
  const DeferredReportsScreen({super.key, required this.projectId, this.initialPeriod = const PeriodFilter.days(30)});

  final String projectId;
  final PeriodFilter initialPeriod;

  @override
  Widget build(BuildContext context) => DeferredScreen(
        loadLibrary: reports.loadLibrary,
        builder: () => reports.ReportsScreen(projectId: projectId, initialPeriod: initialPeriod),
      );
}
