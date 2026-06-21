import 'dart:math' as math;

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
    this.showMarkers = true,
    this.autoFocus = true,
  });

  final List<Map<String, dynamic>> points;
  final double height;
  final void Function(String countryCode, int count)? onCountryTap;
  final bool showFooter;
  final bool interactive;
  final bool showMarkers;
  final bool autoFocus;

  static const _bg = Color(0xFFE2E8F0);
  static const _land = Color(0xFFCBD5E1);
  static const _label = Color(0xFF0F172A);
  static const _selected = Color(0xFF7C3AED);

  @override
  State<WorldMapPanel> createState() => WorldMapPanelState();
}

class WorldMapPanelState extends State<WorldMapPanel> {
  String? _hoverId;
  String? _selectedId;
  final _transform = TransformationController();
  final _viewportKey = GlobalKey();
  late final MapAttributes _attrs = MapAttributes(SMapWorld.instructionsMercator);

  @override
  void initState() {
    super.initState();
    if (widget.autoFocus) _scheduleFocus();
  }

  @override
  void didUpdateWidget(covariant WorldMapPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) {
      _selectedId = null;
      if (widget.autoFocus) _scheduleFocus();
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void focusRegion(String regionId) {
    final codes = widget.points
        .where((p) => regionForCountry((p['country'] as String? ?? '').toUpperCase()) == regionId)
        .map((p) => (p['country'] as String).toLowerCase())
        .toList();
    if (codes.isEmpty) {
      final r = regionById(regionId);
      _focusBoundsFromLatLng([(r.lat, r.lng)], tight: true);
    } else {
      _focusCountries(codes, tight: true);
    }
  }

  void _scheduleFocus() => WidgetsBinding.instance.addPostFrameCallback((_) => _focusActive());

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

  List<double>? _latLngFor(String code) {
    final c = code.toUpperCase();
    final ll = countryCentroids[c];
    if (ll != null) return ll;
    final r = regionById(regionForCountry(c));
    return [r.lat, r.lng];
  }

  Map<String, Color> _colors() {
    final max = widget.points.fold<int>(0, (m, p) {
      final c = _usersForPoint(p);
      return c > m ? c : m;
    });
    final colors = <String, Color>{};
    for (final p in widget.points) {
      final id = (p['country'] as String? ?? '').toLowerCase();
      if (id.length != 2) continue;
      final users = _usersForPoint(p);
      if (users == 0) continue;
      colors[id] = _countryColor(id, users, max);
    }
    return colors;
  }

  Color _countryColor(String id, int users, int max) {
    if (_selectedId == id) return WorldMapPanel._selected;
    if (_hoverId == id) return AppTheme.primary;
    final t = max == 0 ? 0.0 : (users / max).clamp(0.0, 1.0);
    return Color.lerp(WorldMapPanel._land, AppTheme.primary, 0.3 + t * 0.55)!;
  }

  List<SimpleMapMarker> _markers() {
    if (!widget.showMarkers) return [];
    return [for (final p in widget.points) if (_markerFor(p) case final m?) m];
  }

  SimpleMapMarker? _markerFor(Map<String, dynamic> p) {
    final code = (p['country'] as String? ?? '').toUpperCase();
    if (code.length != 2) return null;
    final users = _usersForPoint(p);
    if (users == 0) return null;
    final ll = _latLngFor(code);
    if (ll == null) return null;
    final selected = _selectedId == code.toLowerCase();
    return SimpleMapMarker(
      markerSize: Size(selected ? 58 : 52, selected ? 48 : 44),
      latLong: LatLong(latitude: ll[0], longitude: ll[1]),
      marker: IgnorePointer(
        child: _CountryMarkerBadge(code: code, users: users, selected: selected),
      ),
    );
  }

  void _onCountryTap(String id) {
    final users = _usersFor(id);
    if (users == 0) return;
    final code = id.toLowerCase();
    setState(() {
      _selectedId = _selectedId == code ? null : code;
      _hoverId = null;
    });
    _focusCountries([code], tight: true);
  }

  void _focusActive() {
    final top = _topTrafficCode();
    if (top == null) return;
    _focusCountries([top], tight: true);
  }

  String? _topTrafficCode() {
    Map<String, dynamic>? best;
    var bestUsers = 0;
    for (final p in widget.points) {
      final u = _usersForPoint(p);
      if (u > bestUsers) {
        bestUsers = u;
        best = p;
      }
    }
    final code = best?['country'] as String?;
    return code != null && code.length == 2 ? code.toLowerCase() : null;
  }

  void _focusCountries(List<String> codes, {required bool tight}) {
    final coords = <(double, double)>[];
    for (final code in codes) {
      final ll = _latLngFor(code);
      if (ll != null) coords.add((ll[0], ll[1]));
    }
    _focusBoundsFromLatLng(coords, tight: tight);
  }

  void _focusBoundsFromLatLng(List<(double, double)> coords, {required bool tight}) {
    if (coords.isEmpty) return;
    final rb = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null || !rb.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusBoundsFromLatLng(coords, tight: tight));
      return;
    }

    final vw = rb.size.width;
    final vh = rb.size.height;
    final fitScale = math.min(vw / _attrs.mapWidth, vh / _attrs.mapHeight);

    var minX = double.infinity, maxX = double.negativeInfinity;
    var minY = double.infinity, maxY = double.negativeInfinity;
    for (final (lat, lng) in coords) {
      final pos = _attrs.latLongToPixels(LatLong(latitude: lat, longitude: lng));
      minX = math.min(minX, pos.width);
      maxX = math.max(maxX, pos.width);
      minY = math.min(minY, pos.height);
      maxY = math.max(maxY, pos.height);
    }

    final single = coords.length == 1;
    final pad = tight ? (single ? 36.0 : 70.0) : 120.0;
    final bw = math.max(maxX - minX + pad, single ? 48.0 : 90.0);
    final bh = math.max(maxY - minY + pad, single ? 40.0 : 70.0);
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;

    final scaleX = vw / (bw * fitScale);
    final scaleY = vh / (bh * fitScale);
    final minScale = tight ? (single ? 5.0 : 2.5) : 1.6;
    final scale = math.min(math.min(scaleX, scaleY), 14.0).clamp(minScale, 14.0);

    final offsetX = (vw - _attrs.mapWidth * fitScale) / 2;
    final offsetY = (vh - _attrs.mapHeight * fitScale) / 2;
    final tx = vw / 2 - (offsetX + cx * fitScale) * scale;
    final ty = vh / 2 - (offsetY + cy * fitScale) * scale;

    _transform.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _zoomBy(double factor) {
    final scale = (_transform.value.getMaxScaleOnAxis() * factor).clamp(1.0, 14.0);
    _transform.value = Matrix4.identity()..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    final regions = aggregateByRegion(widget.points);
    final colors = _colors();
    final map = SimpleMap(
      instructions: SMapWorld.instructionsMercator,
      defaultColor: WorldMapPanel._land,
      countryBorder: CountryBorder(color: WorldMapPanel._bg, width: 0.6),
      colors: colors,
      markers: _markers(),
      onHover: (id, _, hovering) => setState(() => _hoverId = hovering ? id : null),
      callback: widget.interactive ? (id, _, __) => _onCountryTap(id) : null,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: WorldMapPanel._bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: _viewportKey,
              height: widget.height,
              child: Stack(
                children: [
                  if (widget.interactive)
                    InteractiveViewer(
                      transformationController: _transform,
                      minScale: 1,
                      maxScale: 14,
                      boundaryMargin: const EdgeInsets.all(80),
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: double.infinity,
                        height: widget.height,
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(width: _attrs.mapWidth, height: _attrs.mapHeight, child: map),
                          ),
                        ),
                      ),
                    )
                  else
                    Center(
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(width: _attrs.mapWidth, height: _attrs.mapHeight, child: map),
                      ),
                    ),
                  if (widget.interactive)
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: Text(
                        'Tap a country to highlight · pinch to zoom',
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
                          _ZoomBtn(icon: Icons.center_focus_strong, tooltip: 'Center top country', onPressed: _focusActive),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (widget.showFooter)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                color: WorldMapPanel._bg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.points.isEmpty
                                ? 'No country data yet'
                                : '$_totalUsers users · $_totalEvents events · ${regions.length} regions · ${widget.points.length} countries',
                            style: TextStyle(color: WorldMapPanel._label.withValues(alpha: 0.55), fontSize: 12),
                          ),
                        ),
                        if (_selectedId != null || _hoverId != null)
                          Text(
                            _labelFor(_selectedId ?? _hoverId!),
                            style: const TextStyle(color: WorldMapPanel._label, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                    if (_selectedId != null && widget.onCountryTap != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: () => widget.onCountryTap!(_selectedId!.toUpperCase(), _countFor(_selectedId!)),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: Text('View events in ${countryLabel(_selectedId!.toUpperCase())}'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _labelFor(String id) {
    final code = id.toUpperCase();
    final users = _usersFor(id);
    final events = _countFor(id);
    final share = _totalUsers == 0 ? 0.0 : users / _totalUsers * 100;
    return '${countryLabel(code)} · $users users · $events events (${share.toStringAsFixed(1)}%)';
  }
}

class _CountryMarkerBadge extends StatelessWidget {
  const _CountryMarkerBadge({required this.code, required this.users, this.selected = false});

  final String code;
  final int users;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? WorldMapPanel._selected.withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: selected ? WorldMapPanel._selected : AppTheme.primary.withValues(alpha: 0.45), width: selected ? 2 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            code,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppTheme.primary, letterSpacing: 0.6, height: 1.1),
          ),
          Text(
            formatGeoCount(users),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: selected ? Colors.white : WorldMapPanel._label, height: 1.1),
          ),
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
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(8),
      elevation: 1,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(width: 36, height: 36, child: Icon(icon, size: 18, color: WorldMapPanel._label)),
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
      showMarkers: true,
      autoFocus: true,
      onCountryTap: onCountryTap,
    );
  }
}
