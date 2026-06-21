import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/event_detail_widgets.dart';
import '../utils/nav.dart';
import '../utils/responsive.dart';
import '../widgets/page_header.dart';

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({super.key, required this.projectId, required this.sessionId});

  final String projectId;
  final String sessionId;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final _api = ScoutApi();
  Map<String, dynamic>? _session;
  bool _loading = true;
  String? _error;

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
      final session = await _api.fetchSessionTimeline(widget.projectId, widget.sessionId);
      if (mounted) setState(() {
        _session = session;
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

    final s = _session!;
    final timeline = jsonListMaps(s['timeline']);
    final started = DateTime.tryParse(s['startedAt'] as String? ?? '');
    final ended = DateTime.tryParse(s['endedAt'] as String? ?? '');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: pageInsets(context, top: 16, bottom: pagePad(context)),
        children: [
          TextButton.icon(
            onPressed: () => popOrGo(context, '/p/${widget.projectId}/sessions'),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back'),
          ),
          PageHeader(
            title: 'Session replay',
            subtitle: started != null ? DateFormat('EEEE, MMM d · HH:mm').format(started.toLocal()) : widget.sessionId,
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _meta('Duration', _fmtDur(s['durationMs'])),
                  _meta('User', s['userId']?.toString() ?? 'anonymous'),
                  _meta('Started', started != null ? DateFormat.Hms().format(started.toLocal()) : '—'),
                  _meta('Ended', ended != null ? DateFormat.Hms().format(ended.toLocal()) : 'still open'),
                  _meta('Steps', '${timeline.length}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Breadcrumb timeline', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                const Text('Navigation, actions, network, and errors during this visit.', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                const SizedBox(height: 16),
                BreadcrumbTrail(items: timeline),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      );

  String _fmtDur(dynamic ms) {
    if (ms == null) return '—';
    final v = ms is num ? ms.toInt() : int.tryParse('$ms') ?? 0;
    if (v <= 0) return '—';
    final sec = v ~/ 1000;
    if (sec < 60) return '${sec}s';
    return '${sec ~/ 60}m ${sec % 60}s';
  }
}
