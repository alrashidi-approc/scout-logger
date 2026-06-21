import 'package:countries_world_map/countries_world_map.dart';
import 'package:countries_world_map/data/maps/world_map.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/country_centroids.dart';
import '../utils/geo_regions.dart';

/// Choropleth world map backed by [countries_world_map].
class WorldMapPanel extends StatefulWidget {
  const WorldMapPanel({
    super.key,
    required this.points,
    this.height = 480,
    this.onCountryTap,
    this.showFooter = true,
    this.interactive = true,
    this.showMarkers = false,
  });

  final List<Map<String, dynamic>> points;
  final double height;
  final void Function(String countryCode, int count)? onCountryTap;
  final bool showFooter;
  final bool interactive;
  final bool showMarkers;

  static const _bg = Color(0xFF2E3439);
  static const _land = Color(0xFF4F5961);
  static const _label = Color(0xFFE8ECF0);

  @override
  State<WorldMapPanel> createState() => _WorldMapPanelState();
}

class _WorldMapPanelState extends State<WorldMapPanel> {
  String? _hoverId;
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  int get _totalEvents => widget.points.fold<int>(0, (s, p) => s + (p['count'] as int? ?? 0));

  int get _totalUsers => widget.points.fold<int>(0, (s, p) => s + _usersForPoint(p));

  int _countFor(String id) {
    final code = id.toUpperCase();
    for (final p in widget.points) {
      if ((p['country'] as String? ?? '').toUpperCase() == code) return p['count'] as int? ?? 0;
    }
    return 0;
  }

  int _usersFor(String id) {
    final code = id.toUpperCase();
    for (final p in widget.points) {
      if ((p['country'] as String? ?? '').toUpperCase() == code) return _usersForPoint(p);
    }
    return 0;
  }

  int _usersForPoint(Map<String, dynamic> p) => p['users'] as int? ?? p['count'] as int? ?? 0;

  Map<String, Color> _colors({String? hoverId}) {
    final max = widget.points.fold<int>(0, (m, p) {
      final c = _usersForPoint(p);
      return c > m ? c : m;
    });
    final colors = <String, Color>{};
    for (final p in widget.points) {
      final id = (p['country'] as String? ?? '').toLowerCase();
      if (id.length != 2) continue;
      colors[id] = _heatColor(_usersForPoint(p), max, hover: hoverId == id);
    }
    if (hoverId != null && !colors.containsKey(hoverId) && hoverId.length == 2) {
      colors[hoverId] = _heatColor(0, max, hover: true);
    }
    return colors;
  }

  Color _heatColor(int count, int max, {bool hover = false}) {
    if (count == 0) return hover ? WorldMapPanel._land.withValues(alpha: 0.85) : WorldMapPanel._land;
    final t = max == 0 ? 0.0 : (count / max).clamp(0.0, 1.0);
    final base = Color.lerp(WorldMapPanel._land, AppTheme.primary, 0.25 + t * 0.75)!;
    return hover ? Color.lerp(base, Colors.white, 0.12)! : base;
  }

  List<SimpleMapMarker> _markers() {
    if (!widget.showMarkers) return [];
    return [
      for (final p in widget.points)
        if (_markerFor(p) case final m?) m,
    ];
  }

  SimpleMapMarker? _markerFor(Map<String, dynamic> p) {
    final code = (p['country'] as String? ?? '').toUpperCase();
    if (code.length != 2) return null;
    final users = _usersForPoint(p);
    if (users == 0) return null;
    final ll = countryCentroids[code];
    if (ll == null) return null;
    return SimpleMapMarker(
      markerSize: const Size(52, 44),
      latLong: LatLong(latitude: ll[0], longitude: ll[1]),
      marker: IgnorePointer(
        child: _CountryMarkerBadge(code: code, users: users),
      ),
    );
  }

  void _zoomBy(double factor) {
    final scale = (_transform.value.getMaxScaleOnAxis() * factor).clamp(1.0, 12.0);
    _transform.value = Matrix4.identity()..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    final regions = aggregateByRegion(widget.points);
    final colors = _colors(hoverId: _hoverId);
    final map = SimpleMap(
      instructions: SMapWorld.instructionsMercator,
      defaultColor: WorldMapPanel._land,
      countryBorder: CountryBorder(color: WorldMapPanel._bg, width: 0.6),
      colors: colors,
      markers: _markers(),
      onHover: (id, name, hovering) => setState(() => _hoverId = hovering ? id : null),
      callback: widget.onCountryTap == null
          ? null
          : (id, name, _) {
              final count = _countFor(id);
              if (count > 0) widget.onCountryTap!(id.toUpperCase(), count);
            },
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: WorldMapPanel._bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: widget.height,
              child: Stack(
                children: [
                  if (widget.interactive)
                    InteractiveViewer(
                      transformationController: _transform,
                      minScale: 1,
                      maxScale: 12,
                      boundaryMargin: const EdgeInsets.all(64),
                      clipBehavior: Clip.hardEdge,
                      child: Center(child: map),
                    )
                  else
                    Center(child: map),
                  if (widget.interactive)
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: Text(
                        'Scroll / pinch to zoom',
                        style: TextStyle(color: WorldMapPanel._label.withValues(alpha: 0.45), fontSize: 11),
                      ),
                    ),
                  if (widget.interactive)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ZoomBtn(icon: Icons.add, tooltip: 'Zoom in', onPressed: () => _zoomBy(1.25)),
                          const SizedBox(height: 6),
                          _ZoomBtn(icon: Icons.remove, tooltip: 'Zoom out', onPressed: () => _zoomBy(0.8)),
                          const SizedBox(height: 6),
                          _ZoomBtn(
                            icon: Icons.center_focus_strong,
                            tooltip: 'Reset view',
                            onPressed: () => _transform.value = Matrix4.identity(),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (widget.showFooter)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                color: WorldMapPanel._bg,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.points.isEmpty
                            ? 'No country data yet'
                            : '$_totalUsers users · $_totalEvents events · ${regions.length} regions · ${widget.points.length} countries',
                        style: TextStyle(color: WorldMapPanel._label.withValues(alpha: 0.55), fontSize: 12),
                      ),
                    ),
                    if (_hoverId != null)
                      Text(
                        _hoverLabel(_hoverId!),
                        style: const TextStyle(color: WorldMapPanel._label, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _hoverLabel(String id) {
    final code = id.toUpperCase();
    final users = _usersFor(id);
    final events = _countFor(id);
    final share = _totalUsers == 0 ? 0.0 : users / _totalUsers * 100;
    return '${countryLabel(code)} · $users users · $events events (${share.toStringAsFixed(1)}%)';
  }
}

class _CountryMarkerBadge extends StatelessWidget {
  const _CountryMarkerBadge({required this.code, required this.users});

  final String code;
  final int users;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F24).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.55)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(code, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppTheme.primary, letterSpacing: 0.6, height: 1.1)),
          Text(formatGeoCount(users), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: WorldMapPanel._label, height: 1.1)),
        ],
      ),
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  const _ZoomBtn({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1F24).withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 18, color: WorldMapPanel._label),
          ),
        ),
      ),
    );
  }
}

class WorldMapCompact extends StatelessWidget {
  const WorldMapCompact({super.key, required this.points, this.onCountryTap});

  final List<Map<String, dynamic>> points;
  final void Function(String countryCode, int count)? onCountryTap;

  @override
  Widget build(BuildContext context) {
    return WorldMapPanel(
      points: points,
      height: 260,
      showFooter: false,
      interactive: false,
      showMarkers: false,
      onCountryTap: onCountryTap,
    );
  }
}
