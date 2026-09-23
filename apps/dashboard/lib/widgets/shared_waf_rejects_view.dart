import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import 'event_card.dart';
import 'page_header.dart';

/// Read-only WAF rejects list for a public share token.
class SharedWafRejectsView extends StatelessWidget {
  const SharedWafRejectsView({
    super.key,
    required this.projectName,
    required this.events,
    this.total,
    this.filters,
    this.waf,
  });

  final String projectName;
  final List<Map<String, dynamic>> events;
  final int? total;
  final Map<String, dynamic>? filters;
  final Map<String, dynamic>? waf;

  String get _subtitle {
    final bits = <String>[
      if (total != null) '$total rejects',
      if (filters?['days'] != null) '${filters!['days']}d',
      if (filters?['hours'] != null) '${filters!['hours']}h',
      if (filters?['from'] != null) 'from ${filters!['from']}',
      if (filters?['environment'] != null) 'env ${filters!['environment']}',
      if (filters?['appVersion'] != null) 'v${filters!['appVersion']}',
      if (filters?['q'] != null && '${filters!['q']}'.isNotEmpty) 'q: ${filters!['q']}',
    ];
    final codes = (waf?['statusCodes'] as List?)?.join(', ');
    final types = (waf?['contentTypes'] as List?)?.join(', ');
    if (codes != null) bits.add('status $codes');
    if (types != null) bits.add(types);
    return bits.isEmpty ? projectName : bits.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
      children: [
        PageHeader(title: 'WAF rejects', subtitle: _subtitle),
        Text(projectName, style: const TextStyle(fontSize: 13, color: AppTheme.muted)),
        const SizedBox(height: 16),
        if (events.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                'No WAF-looking responses in this shared range.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.muted),
              ),
            ),
          )
        else
          for (final e in events) EventCard(event: e),
      ],
    );
  }
}
