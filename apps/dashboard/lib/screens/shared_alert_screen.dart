import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/share_seo.dart';
import '../widgets/event_card.dart';
import '../widgets/page_header.dart';
import 'event_detail_screen.dart';

/// Read-only spike / digest view from notification share token.
class SharedAlertScreen extends StatefulWidget {
  const SharedAlertScreen({super.key, required this.token, required this.data});

  final String token;
  final Map<String, dynamic> data;

  @override
  State<SharedAlertScreen> createState() => _SharedAlertScreenState();
}

class _SharedAlertScreenState extends State<SharedAlertScreen> {
  @override
  void initState() {
    super.initState();
    final title = widget.data['title'] as String? ?? 'Scout alert';
    applyShareSeo(title: title, description: widget.data['summary'] as String? ?? title, url: _shareUrl);
  }

  @override
  void dispose() {
    clearShareSeo();
    super.dispose();
  }

  String get _shareUrl {
    final base = Uri.base;
    final path = base.path.endsWith('/') ? base.path : '${base.path}/';
    return '${base.origin}${path}share/${widget.token}';
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.data['alertKind'] as String? ?? 'spike';
    final projectName = widget.data['projectName'] as String? ?? 'Project';
    final title = widget.data['title'] as String? ?? 'Alert';
    final expiresAt = widget.data['expiresAt'] as String?;

    return Material(
      color: AppTheme.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReadOnlyBanner(title: title, projectName: projectName, expiresAt: expiresAt),
          Expanded(
            child: kind == 'digest'
                ? _DigestBody(body: widget.data['body'] as String? ?? '')
                : _SpikeBody(
                    summary: widget.data['summary'] as String?,
                    events: jsonListMaps(widget.data['events']),
                    total: jsonInt(widget.data['total']) ?? 0,
                    shareUrl: _shareUrl,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner({required this.title, required this.projectName, this.expiresAt});

  final String title;
  final String projectName;
  final String? expiresAt;

  @override
  Widget build(BuildContext context) {
    final exp = expiresAt != null ? DateTime.tryParse(expiresAt!) : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        border: Border(bottom: BorderSide(color: AppTheme.primary.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined, size: 18, color: AppTheme.primary.withValues(alpha: 0.9)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Read-only · $projectName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.muted)),
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.text)),
                if (exp != null)
                  Text('Expires ${DateFormat.yMMMd().add_jm().format(exp.toLocal())}', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.panel,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Text('View only', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.muted)),
          ),
        ],
      ),
    );
  }
}

class _DigestBody extends StatelessWidget {
  const _DigestBody({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SelectableText(body, style: const TextStyle(fontSize: 13, height: 1.55, color: AppTheme.text, fontFamily: 'monospace')),
    );
  }
}

class _SpikeBody extends StatelessWidget {
  const _SpikeBody({this.summary, required this.events, required this.total, required this.shareUrl});

  final String? summary;
  final List<Map<String, dynamic>> events;
  final int total;
  final String shareUrl;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: PageHeader(
              title: 'Recent events',
              subtitle: summary ?? '$total events in alert window',
            ),
          ),
        ),
        if (events.isEmpty)
          const SliverFillRemaining(
            child: Center(child: Text('No events in this window', style: TextStyle(color: AppTheme.muted))),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: EventCard(
                    event: events[i],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => Material(
                          child: Column(
                            children: [
                              _ReadOnlyBanner(title: 'Event detail', projectName: '', expiresAt: null),
                              Expanded(child: EventDetailScreen.viewOnly(initialEvent: events[i], shareUrl: shareUrl)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                childCount: events.length,
              ),
            ),
          ),
      ],
    );
  }
}
