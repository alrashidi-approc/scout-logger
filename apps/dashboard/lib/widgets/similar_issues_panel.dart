import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'event_card.dart';
import 'page_header.dart';

/// Collapsed "Similar issues" card; [load] runs the first time it is expanded.
class SimilarIssuesPanel extends StatefulWidget {
  const SimilarIssuesPanel({super.key, required this.load, required this.onOpen});

  final Future<List<Map<String, dynamic>>> Function() load;
  final void Function(Map<String, dynamic> issue) onOpen;

  @override
  State<SimilarIssuesPanel> createState() => _SimilarIssuesPanelState();
}

class _SimilarIssuesPanelState extends State<SimilarIssuesPanel> {
  Future<List<Map<String, dynamic>>>? _similar;

  void _load() => setState(() {
        _similar = widget.load();
      });

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          leading: const Icon(Icons.join_inner, size: 20, color: AppTheme.muted),
          title: const Text('Similar issues', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          subtitle: const Text('Previous fingerprint versions, same culprit or route',
              style: TextStyle(fontSize: 12, color: AppTheme.muted)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          onExpansionChanged: (open) {
            if (open && _similar == null) _load();
          },
          children: [
            FutureBuilder(
              future: _similar,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorPanel(
                    message: formatLoadError(snap.error ?? ''),
                    onRetry: _load,
                  );
                }
                final similar = snap.data;
                if (similar == null) return const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator());
                if (similar.isEmpty) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No similar issues', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                  );
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final i in similar) ...[
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      if (i['fingerprintVersion'] == 1) _chip('previous version', AppTheme.warning),
                      for (final b in (i['similarBecause'] as List?)?.whereType<String>() ?? const <String>[])
                        _chip(b.replaceAll('_', ' '), AppTheme.muted),
                    ]),
                    const SizedBox(height: 6),
                    IssueCard(issue: i, onTap: () => widget.onOpen(i)),
                  ],
                ]);
              },
            ),
          ],
        ),
      );

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11)),
      );
}
