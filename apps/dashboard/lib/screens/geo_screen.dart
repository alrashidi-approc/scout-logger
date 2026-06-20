import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';

class GeoScreen extends StatefulWidget {
  const GeoScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<GeoScreen> createState() => _GeoScreenState();
}

class _GeoScreenState extends State<GeoScreen> {
  final _api = ScoutApi();
  List<Map<String, dynamic>> _geo = [];
  bool _loading = true;
  String? _error;
  int _days = 7;

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
      final geo = await _api.fetchGeo(widget.projectId, days: _days);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorPanel(message: _error!, onRetry: _load);

    final total = _geo.fold<int>(0, (s, g) => s + (g['count'] as int? ?? 0));

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        PageHeader(
          title: 'Geography',
          subtitle: 'Country breakdown from server-side IP resolution',
          actions: [
            DropdownButton<int>(
              value: _days,
              items: const [
                DropdownMenuItem(value: 1, child: Text('Today')),
                DropdownMenuItem(value: 7, child: Text('7 days')),
                DropdownMenuItem(value: 30, child: Text('30 days')),
              ],
              onChanged: (v) {
                if (v == null) return;
                _days = v;
                _load();
              },
            ),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        const SizedBox(height: 8),
        Text('$total events across ${_geo.length} countries', style: const TextStyle(color: AppTheme.muted)),
        const SizedBox(height: 24),
        if (_geo.isEmpty)
          const EmptyState(icon: Icons.public_off, title: 'No geo data yet', subtitle: 'Country comes from the device locale on each event (IP is fallback).')
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < _geo.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _countryRow(_geo[i], total, i + 1),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _countryRow(Map<String, dynamic> g, int total, int rank) {
    final count = g['count'] as int? ?? 0;
    final share = total == 0 ? 0.0 : count / total;
    final code = g['country'] as String? ?? '??';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        SizedBox(width: 28, child: Text('#$rank', style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, fontSize: 12))),
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(8)),
          child: Text(code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppTheme.primary)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(code, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('$count (${(share * 100).toStringAsFixed(1)}%)', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: share, minHeight: 8, backgroundColor: AppTheme.border, color: AppTheme.primary),
            ),
          ]),
        ),
      ]),
    );
  }
}
