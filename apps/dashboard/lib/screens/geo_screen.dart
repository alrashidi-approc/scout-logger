import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/country_centroids.dart';
import '../utils/date_range.dart';
import '../utils/geo_regions.dart';
import '../widgets/filter_bar.dart';
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
  List<Map<String, dynamic>> _geo = [];
  bool _loading = true;
  String? _error;
  late PeriodFilter _period = widget.initialPeriod;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final geo = await _api.fetchGeo(widget.projectId, period: _period);
      if (mounted) setState(() {
        _geo = geo;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _setPeriod(PeriodFilter p) {
    _period = p;
    context.go(Uri(path: '/p/${widget.projectId}/geo', queryParameters: p.toQuery()).toString());
    _load();
  }

  void _onCountryTap(String code, int count) {
    context.go(Uri(path: '/p/${widget.projectId}/events', queryParameters: _period.mergeQuery({'country': code.toUpperCase()})).toString());
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: _setPeriod);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorPanel(message: _error!, onRetry: _load);

    final totalEvents = _geo.fold<int>(0, (s, g) => s + (g['count'] as int? ?? 0));
    final totalUsers = _geo.fold<int>(0, (s, g) => s + (g['users'] as int? ?? g['count'] as int? ?? 0));
    final regions = aggregateByRegion(_geo);

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        PageHeader(
          title: 'Geography',
          subtitle: 'Users by country',
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
            subtitle: 'Country comes from device locale on each event (IP is fallback).',
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
                        label: Text('${r['label']} · ${r['users']} users'),
                        onPressed: () => _mapKey.currentState?.focusRegion(r['id'] as String),
                      ),
                    ),
                ],
              ),
            ),
          if (regions.isNotEmpty) const SizedBox(height: 12),
          WorldMapPanel(
            key: _mapKey,
            points: _geo,
            height: 520,
            showMarkers: true,
            autoFocus: true,
            onCountryTap: _onCountryTap,
          ),
          const SizedBox(height: 20),
          Text(
            '$totalUsers users · $totalEvents events · ${regions.length} active regions · ${_geo.length} countries',
            style: const TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
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

    return InkWell(
      onTap: () => context.go(Uri(path: '/p/${widget.projectId}/events', queryParameters: _period.mergeQuery({'country': code})).toString()),
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
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('$users users · $events ev (${(share * 100).toStringAsFixed(1)}%)', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
              const SizedBox(height: 4),
              Text(region, style: const TextStyle(color: AppTheme.muted, fontSize: 11, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: share, minHeight: 6, backgroundColor: AppTheme.border, color: AppTheme.primary),
              ),
            ]),
          ),
          const Icon(Icons.chevron_right, color: AppTheme.muted, size: 18),
        ]),
      ),
    );
  }
}
