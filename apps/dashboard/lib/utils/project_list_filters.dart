import 'package:flutter/widgets.dart';

import '../services/api_client.dart';
import '../services/dashboard_log_service.dart';
import '../services/facets_cache.dart';
import '../widgets/page_header.dart';
import 'date_range.dart';
import 'screen_load.dart';

/// Period, search and env/version/device facets plus load state shared by Events and Issues.
mixin ProjectListFilters<T extends StatefulWidget> on State<T> {
  final api = ScoutApi();
  late PeriodFilter period;
  late String search;
  String? environment;
  String? appVersion;
  String? deviceName;
  List<String> environments = [];
  List<String> appVersions = [];
  List<String> deviceNames = [];
  bool loading = true;
  bool refreshing = false;
  bool hasData = false;
  Object? error;

  String get projectId;
  void writeCache();

  Map<String, Object> get facetCache =>
      {'environments': environments, 'appVersions': appVersions, 'deviceNames': deviceNames};

  Map<String, String> get facetQuery => {
        if (environment case final e?) 'environment': e,
        if (appVersion case final v?) 'appVersion': v,
        if (deviceName case final d?) 'device': d,
      };

  void restoreFacets(Map<String, Object> cached) {
    environments = (cached['environments'] as List?)?.cast<String>() ?? [];
    appVersions = (cached['appVersions'] as List?)?.cast<String>() ?? [];
    deviceNames = (cached['deviceNames'] as List?)?.cast<String>() ?? [];
    hasData = true;
    loading = false;
    refreshing = false;
    error = null;
  }

  Future<void> loadList<R>(Future<R> Function() fetch, void Function(R) apply) async {
    setState(() => beginScreenLoad(
          hasData: hasData,
          apply: ({required loading, required refreshing, error}) {
            this.loading = loading;
            this.refreshing = refreshing;
            this.error = error;
          },
        ));
    try {
      final result = await fetch();
      if (!mounted) return;
      setState(() {
        apply(result);
        hasData = true;
        loading = false;
        refreshing = false;
      });
      writeCache();
      _loadFacets();
    } catch (e) {
      DashboardLogService.record(projectId: projectId, message: formatLoadError(e));
      if (mounted) {
        setState(() {
          error = e;
          loading = false;
          refreshing = false;
        });
      }
    }
  }

  Future<void> _loadFacets() async {
    try {
      final facets = await FacetsCache.get(
        api,
        projectId,
        period: period,
        environment: environment,
        appVersion: appVersion,
        deviceName: deviceName,
      );
      if (!mounted) return;
      setState(() {
        environments = (facets['environments'] as List?)?.map((e) => e.toString()).toList() ?? [];
        appVersions = (facets['appVersions'] as List?)?.map((e) => e.toString()).toList() ?? [];
        deviceNames = (facets['deviceNames'] as List?)?.map((e) => e.toString()).toList() ?? [];
      });
      writeCache();
    } catch (_) {}
  }
}
