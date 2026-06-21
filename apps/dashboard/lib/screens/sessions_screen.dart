import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/date_range.dart';
import '../utils/responsive.dart';
import '../widgets/filter_bar.dart';
import '../widgets/page_header.dart';
import '../widgets/period_picker.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key, required this.projectId, this.initialPeriod = const PeriodFilter.days(7)});

  final String projectId;
  final PeriodFilter initialPeriod;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  final _api = ScoutApi();
  List<Map<String, dynamic>> _sessions = [];
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
      final sessions = await _api.fetchSessions(widget.projectId, period: _period, limit: 100);
      if (mounted) setState(() {
        _sessions = sessions;
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
    context.go(Uri(path: '/p/${widget.projectId}/sessions', queryParameters: p.toQuery()).toString());
    _load();
  }

  String _fmtDur(dynamic ms) {
    if (ms == null) return '—';
    final sec = ((ms is num ? ms.toInt() : int.tryParse('$ms')) ?? 0) ~/ 1000;
    if (sec < 60) return '${sec}s';
    return '${sec ~/ 60}m ${sec % 60}s';
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: _setPeriod);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: pageInsets(context, top: pagePad(context)),
        child: PageHeader(
          title: 'Sessions',
          subtitle: '${_sessions.length} sessions',
          period: _period,
          onPeriodTap: _openPeriodPicker,
          actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
        ),
      ),
      Padding(padding: pageInsets(context, top: 12), child: FilterBar(period: _period, onPeriodChanged: _setPeriod)),
      Expanded(
        child: _loading
            ? const LoadingView()
            : _error != null
                ? ErrorPanel(message: _error!, onRetry: _load)
                : _sessions.isEmpty
                    ? const EmptyState(icon: Icons.play_circle_outline, title: 'No sessions yet', subtitle: 'Sessions are recorded when your app sends session start/end events.')
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          key: PageStorageKey('sessions-${widget.projectId}'),
                          padding: pageInsets(context, top: 12, bottom: pagePad(context)),
                          itemCount: _sessions.length,
                          itemBuilder: (_, i) {
                            final s = _sessions[i];
                            final started = DateTime.tryParse(s['startedAt'] as String? ?? '');
                            final open = s['endedAt'] == null;
                            final summary = s['summary'] is Map ? Map<String, dynamic>.from(s['summary'] as Map) : null;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: open ? AppTheme.primary.withValues(alpha: 0.4) : AppTheme.border)),
                              child: ListTile(
                                onTap: () => context.push('/p/${widget.projectId}/sessions/${s['id']}'),
                                leading: Icon(open ? Icons.sensors : Icons.play_circle_outline, color: open ? AppTheme.primary : AppTheme.muted),
                                title: Text(started != null ? DateFormat('MMM d · HH:mm:ss').format(started.toLocal()) : '${s['id']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                subtitle: Text(
                                  [
                                    if (s['userId'] != null) 'User ${s['userId']}',
                                    if (s['release'] != null) '${s['release']}',
                                    _fmtDur(s['durationMs']),
                                    if (summary != null) '${summary['screensVisited'] ?? 0} screens',
                                  ].join(' · '),
                                  style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                                ),
                                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  if (open) const Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                                  const Icon(Icons.chevron_right, size: 18, color: AppTheme.muted),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    ]);
  }
}
