import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/event_card.dart';
import '../widgets/page_header.dart';
import '../widgets/stat_card.dart';
import '../widgets/trend_chart.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  final _api = ScoutApi();
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _recentIssues = [];
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
      final data = await _api.fetchOverview(widget.projectId);
      final issues = await _api.fetchIssues(widget.projectId);
      if (mounted) setState(() {
        _data = data;
        _recentIssues = issues.take(5).toList();
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

    final d = _data!;
    final project = jsonMap(d['project']);
    final countries = jsonListMaps(d['topCountries']);
    final releases = jsonListMaps(d['byRelease']);
    final trend = jsonListMaps(d['dailyTrend']);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          PageHeader(
            title: project['name'] as String? ?? widget.projectId,
            subtitle: 'Real-time error & crash monitoring',
            actions: [
              TextButton.icon(
                onPressed: () => context.go('/p/${widget.projectId}/analytics'),
                icon: const Icon(Icons.insights_outlined, size: 18),
                label: const Text('Analytics'),
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth > 1100 ? 6 : (c.maxWidth > 700 ? 3 : 2);
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.6,
              children: [
                StatCard(label: 'Events today', value: '${d['eventsToday']}', icon: Icons.show_chart, color: AppTheme.primary),
                StatCard(label: 'Errors today', value: '${d['errorsToday']}', icon: Icons.error_outline, color: AppTheme.error),
                StatCard(label: 'Crashes today', value: '${d['crashesToday']}', icon: Icons.bolt, color: AppTheme.warning),
                StatCard(label: 'Open issues', value: '${d['openIssues']}', icon: Icons.bug_report_outlined, color: const Color(0xFF7C3AED)),
                StatCard(label: 'Users today', value: '${d['uniqueUsersToday']}', icon: Icons.people_outline, color: AppTheme.success),
                StatCard(label: 'Open sessions', value: '${d['activeSessions'] ?? 0}', icon: Icons.sensors, color: AppTheme.info),
                StatCard(label: 'Avg session today', value: _fmtDuration(d['avgSessionDurationMs']), icon: Icons.timer_outlined, color: const Color(0xFF0EA5E9)),
                StatCard(label: 'Sessions today', value: '${d['sessionsCompletedToday'] ?? 0}', icon: Icons.play_circle_outline, color: const Color(0xFF6366F1)),
                StatCard(label: 'Users (7d)', value: '${d['uniqueUsers7d'] ?? 0}', icon: Icons.timeline, color: const Color(0xFF0EA5E9)),
              ],
            );
          }),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('14-day trend', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                Row(children: [
                  _legend(AppTheme.primary, 'Events'),
                  const SizedBox(width: 16),
                  _legend(AppTheme.error, 'Errors'),
                ]),
                const SizedBox(height: 8),
                TrendChart(points: trend),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final sideBySide = c.maxWidth > 900;
            final recent = Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('Recent issues', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const Spacer(),
                    TextButton(onPressed: () => context.go('/p/${widget.projectId}/issues'), child: const Text('View all')),
                  ]),
                  const SizedBox(height: 12),
                  if (_recentIssues.isEmpty)
                    const Text('No issues yet', style: TextStyle(color: AppTheme.muted))
                  else
                    ..._recentIssues.map((issue) => IssueCard(
                          issue: issue,
                          onTap: () => context.go('/p/${widget.projectId}/issues/${issue['id']}'),
                        )),
                ]),
              ),
            );
            final side = Column(children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Text('Top countries (7d)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const Spacer(),
                      TextButton(onPressed: () => context.go('/p/${widget.projectId}/geo'), child: const Text('Geography')),
                    ]),
                    const SizedBox(height: 12),
                    if (countries.isEmpty)
                      const Text('No geo data yet', style: TextStyle(color: AppTheme.muted))
                    else
                      ...countries.take(6).map((c) {
                        final total = countries.fold<int>(0, (s, x) => s + (x['count'] as int? ?? 0));
                        final count = c['count'] as int? ?? 0;
                        final pct = total == 0 ? 0.0 : count / total;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            SizedBox(width: 36, child: Text(c['country'] as String? ?? '??', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct, minHeight: 8, backgroundColor: AppTheme.border, color: AppTheme.primary))),
                            const SizedBox(width: 10),
                            Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ]),
                        );
                      }),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Releases', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 12),
                    if (releases.isEmpty)
                      const Text('No releases yet', style: TextStyle(color: AppTheme.muted))
                    else
                      ...releases.take(5).map((r) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${r['release']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  Text('${r['environment']} · ${r['eventCount']} events · ${r['crashCount']} crashes', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                                ]),
                              ),
                              Text(DateFormat.MMMd().format(DateTime.parse(r['lastSeenAt'] as String)), style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                            ]),
                          )),
                  ]),
                ),
              ),
            ]);
            if (!sideBySide) return Column(children: [recent, const SizedBox(height: 16), ...side.children]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: recent), const SizedBox(width: 16), Expanded(child: side)]);
          }),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
        ],
      );

  String _fmtDuration(dynamic ms) {
    if (ms == null) return '—';
    final totalSec = ((ms is num ? ms.toInt() : int.tryParse('$ms')) ?? 0) ~/ 1000;
    if (totalSec <= 0) return '—';
    if (totalSec < 60) return '${totalSec}s';
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }
}
