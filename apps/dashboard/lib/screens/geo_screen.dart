import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/dashboard_log_service.dart';
import '../services/api_client.dart';
import '../services/screen_cache.dart';
import '../theme/app_theme.dart';
import '../utils/country_centroids.dart';
import '../utils/date_range.dart';
import '../utils/geo_regions.dart';
import '../utils/geo_source.dart';
import '../widgets/filter_bar.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../widgets/page_header.dart';
import '../widgets/period_picker.dart';
import '../widgets/world_map.dart';

class GeoScreen extends StatefulWidget {
  const GeoScreen({super.key, required this.projectId, this.initialPeriod = const PeriodFilter.days(7)});

  final String projectId;
  final PeriodFilter initialPeriod;

  @override
  State<GeoScreen> createState() => _GeoScreenState();
}

class _GeoScreenState extends State<GeoScreen> {
  final _api = ScoutApi();
  final _mapKey = GlobalKey<WorldMapPanelState>();
  final _mapAnchorKey = GlobalKey();
  List<Map<String, dynamic>> _geo = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;
  late PeriodFilter _period = widget.initialPeriod;

  String get _cacheKey => screenCacheKey('geo', projectId: widget.projectId, period: _period);

  @override
  void initState() {
    super.initState();
    if (!_restore()) _load();
  }

  bool _restore() {
    final cached = ScreenCache.instance.read<List<Map<String, dynamic>>>(_cacheKey);
    if (cached == null) return false;
    _geo = cached;
    _hasData = true;
    _loading = false;
    _refreshing = false;
    _error = null;
    return true;
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      beginScreenLoad(
        hasData: _hasData,
        apply: ({required loading, required refreshing, error}) {
          _loading = loading;
          _refreshing = refreshing;
          _error = error;
        },
      );
    });
    try {
      final geo = await _api.fetchGeo(widget.projectId, period: _period);
      ScreenCache.instance.write(_cacheKey, geo);
      if (mounted) setState(() {
        _geo = geo;
        _hasData = true;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      DashboardLogService.record(projectId: widget.projectId, message: formatLoadError(e));
      if (mounted) setState(() {
        _error = e;
        _loading = false;

        _refreshing = false;
      });
    }
  }

  void _setPeriod(PeriodFilter p) {
    _period = p;
    context.go(Uri(path: '/p/${widget.projectId}/geo', queryParameters: p.toQuery()).toString());
    if (_restore()) {
      setState(() {});
    } else {
      _load();
    }
  }

  void _focusCountryOnMap(String code) {
    final ctx = _mapAnchorKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic, alignment: 0.2);
    }
    _mapKey.currentState?.focusCountry(code);
  }

  void _onCountryTap(String code, int count) {
    context.go(Uri(path: '/p/${widget.projectId}/events', queryParameters: _period.mergeQuery({'country': code.toUpperCase()})).toString());
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: _setPeriod);

  @override
  Widget build(BuildContext context) {
    return AsyncScreenBody(
      loading: _loading,
            refreshing: _refreshing,
      error: _error,
      onRetry: _load,
      placeholderLayout: PlaceholderLayout.geo,
      builder: _buildContent,
    );
  }

  Widget _buildContent(BuildContext context) {
    final totalEvents = _geo.fold<int>(0, (s, g) => s + (g['count'] as int? ?? 0));
    final totalUsers = _geo.fold<int>(0, (s, g) => s + (g['users'] as int? ?? g['count'] as int? ?? 0));
    final regions = aggregateByRegion(_geo);

    return ListView(
      padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
      children: [
        PageHeader(
          title: 'Geography',
          subtitle: 'Logged-in users by connection country (IP) · profile and locale shown when different',
          period: _period,
          onPeriodTap: _openPeriodPicker,
          actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
        ),
        const SizedBox(height: 16),
        FilterBar(period: _period, onPeriodChanged: _setPeriod),
        const SizedBox(height: 20),
        if (_geo.isEmpty)
          const EmptyState(
            icon: Icons.public_off,
            title: 'No geo data yet',
            subtitle: 'Country comes from connection IP. Device locale is shown separately when it differs.',
          )
        else ...[
          if (regions.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final r in regions)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text('${r['label']} · ${r['users']} logged-in'),
                        onPressed: () => _mapKey.currentState?.focusRegion(r['id'] as String),
                      ),
                    ),
                ],
              ),
            ),
          if (regions.isNotEmpty) const SizedBox(height: 12),
          KeyedSubtree(
            key: _mapAnchorKey,
            child: WorldMapPanel(
              key: _mapKey,
              points: _geo,
              height: 520,
              showMarkers: true,
              autoFocus: true,
              onCountryTap: _onCountryTap,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '$totalUsers logged-in · $totalEvents events · ${regions.length} active regions · ${_geo.length} countries',
            style: const TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    children: [
                      SizedBox(width: 28, child: Text('#', style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, fontSize: 11))),
                      const SizedBox(width: 56),
                      const Expanded(child: Text('Country', style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, fontSize: 11))),
                      SizedBox(
                        width: isMobile(context) ? 64 : 88,
                        child: Text('Source', style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, fontSize: 11), textAlign: TextAlign.center),
                      ),
                      const SizedBox(width: 8),
                      Text('Logged-in / events', style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, fontSize: 11)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                for (var i = 0; i < _geo.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _countryRow(_geo[i], totalUsers, totalEvents, i + 1),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _countryRow(Map<String, dynamic> g, int totalUsers, int totalEvents, int rank) {
    final events = g['count'] as int? ?? 0;
    final users = g['users'] as int? ?? events;
    final share = totalUsers == 0 ? 0.0 : users / totalUsers;
    final code = (g['country'] as String? ?? '??').toUpperCase();
    final name = countryLabel(code);
    final region = regionById(regionForCountry(code)).label;
    final source = g['countrySource'] as String?;

    return InkWell(
      onTap: () => _focusCountryOnMap(code),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          SizedBox(width: 28, child: Text('#$rank', style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, fontSize: 12))),
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppTheme.panelElevated, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.border)),
            child: Text(code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: AppTheme.text)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(region, style: const TextStyle(color: AppTheme.muted, fontSize: 11, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: share, minHeight: 6, backgroundColor: AppTheme.border, color: AppTheme.primary),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: geoSourceDetail(g),
            child: GeoSourceChip(source: source, compact: isMobile(context)),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: isMobile(context) ? 72 : 96,
            child: Text(
              '$users / $events',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'View events',
            visualDensity: VisualDensity.compact,
            onPressed: () => context.go(Uri(path: '/p/${widget.projectId}/events', queryParameters: _period.mergeQuery({'country': code})).toString()),
            icon: const Icon(Icons.open_in_new, color: AppTheme.muted, size: 18),
          ),
        ]),
      ),
    );
  }
}
