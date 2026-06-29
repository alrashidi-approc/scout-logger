import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../widgets/page_header.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final _api = ScoutApi();
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;
  List<Map<String, dynamic>> _deliveries = [];
  Map<String, dynamic> _summary = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
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
      final data = await _api.fetchAllNotificationDeliveries();
      if (!mounted) return;
      setState(() {
        _deliveries = (data['deliveries'] as List).cast<Map<String, dynamic>>();
        _summary = Map<String, dynamic>.from(data['summary'] as Map? ?? {});
        _hasData = true;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  int _stat(String k) => (_summary[k] as int?) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AsyncScreenBody(
      loading: _loading,
      refreshing: _refreshing,
      error: _error,
      onRetry: _load,
      builder: (context) => ListView(
        padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
        children: [
          PageHeader(
            title: 'Alerts',
            subtitle: 'Notification deliveries across all your projects — last 24 hours',
            actions: [
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                _statChip('Sent', _stat('sent'), AppTheme.success),
                _statChip('Failed', _stat('failed'), AppTheme.error),
                _statChip('Deduped', _stat('skipped_dedup'), AppTheme.muted),
                _statChip('Rate-limited', _stat('rate_limited'), AppTheme.warning),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          if (_deliveries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.notifications_none, size: 48, color: AppTheme.muted),
                  SizedBox(height: 12),
                  Text('No alerts yet', style: TextStyle(color: AppTheme.muted)),
                ]),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(children: [for (final d in _deliveries) _AlertTile(delivery: d)]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statChip(String label, int n, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text('$label $n', style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      );
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.delivery});

  final Map<String, dynamic> delivery;

  Color _statusColor(String status) => switch (status) {
        'sent' => AppTheme.success,
        'failed' => AppTheme.error,
        'rate_limited' => AppTheme.warning,
        _ => AppTheme.muted,
      };

  IconData _channelIcon(String channel) => switch (channel) {
        'slack' => Icons.tag,
        'whatsapp' => Icons.chat,
        'email' => Icons.mail_outline,
        _ => Icons.notifications_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final status = '${delivery['status']}';
    final channel = '${delivery['channel']}';
    final projectId = delivery['projectId']?.toString();
    final color = _statusColor(status);
    final error = delivery['errorMessage'];
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(_channelIcon(channel), size: 18, color: color),
      ),
      title: Text(
        '${delivery['projectName'] ?? projectId ?? 'Project'} · ${delivery['category']}',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      subtitle: Text(
        '$channel · $status${error != null ? ' — $error' : ''}\n${delivery['createdAt'] ?? ''}',
        style: const TextStyle(fontSize: 12),
      ),
      isThreeLine: true,
      trailing: projectId == null ? null : const Icon(Icons.chevron_right, size: 18, color: AppTheme.muted),
      onTap: projectId == null ? null : () => context.go('/p/$projectId/notifications'),
    );
  }
}
