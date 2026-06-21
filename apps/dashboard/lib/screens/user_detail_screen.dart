import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/nav.dart';
import '../utils/responsive.dart';
import '../widgets/event_card.dart';
import '../widgets/page_header.dart';

class UserDetailScreen extends StatefulWidget {
  const UserDetailScreen({super.key, required this.projectId, required this.userId});

  final String projectId;
  final String userId;

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  final _api = ScoutApi();
  Map<String, dynamic>? _user;
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
      final user = await _api.fetchUser(widget.projectId, widget.userId);
      if (mounted) setState(() {
        _user = user;
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

    final u = _user!;
    final events = jsonListMaps(u['recentEvents']);
    final first = DateTime.tryParse(u['firstSeenAt'] as String? ?? '');
    final last = DateTime.tryParse(u['lastSeenAt'] as String? ?? '');

    return ListView(
      padding: pageInsets(context, top: 16, bottom: pagePad(context)),
      children: [
        TextButton.icon(onPressed: () => popOrGo(context, '/p/${widget.projectId}/users'), icon: const Icon(Icons.arrow_back, size: 18), label: const Text('Back')),
        PageHeader(title: widget.userId, subtitle: 'User profile'),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _chip('Events', '${u['eventCount']}', Icons.show_chart),
          _chip('Errors', '${u['errorCount']}', Icons.error_outline),
          _chip('Crashes', '${u['crashCount']}', Icons.bolt),
          _chip('Sessions', '${u['sessionCount']}', Icons.play_circle_outline),
          if (u['topCountry'] != null) _chip('Country', '${u['topCountry']}', Icons.public),
        ]),
        if (first != null && last != null) ...[
          const SizedBox(height: 12),
          Text('First seen ${DateFormat.yMMMd().format(first.toLocal())} · Last ${DateFormat.yMMMd().add_jm().format(last.toLocal())}', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        ],
        const SizedBox(height: 20),
        const Text('Recent events', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.text)),
        const SizedBox(height: 10),
        ...events.map((e) => EventCard(event: e, onTap: () => context.push('/p/${widget.projectId}/events/${e['id']}'))),
      ],
    );
  }

  Widget _chip(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.muted, fontWeight: FontWeight.w600)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          ]),
        ]),
      );
}
