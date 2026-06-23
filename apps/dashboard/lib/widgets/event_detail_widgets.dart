import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:scout_models/scout_models.dart';

import '../theme/app_theme.dart';
import '../utils/event_view.dart';
import 'level_badge.dart';

class EventErrorHeader extends StatelessWidget {
  const EventErrorHeader({super.key, required this.view, this.timeLabel});

  final EventView view;
  final String? timeLabel;

  @override
  Widget build(BuildContext context) {
    final accent = _accent(view.type);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.08), accent.withValues(alpha: 0.02)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, decoration: BoxDecoration(color: accent, borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)))),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  LevelBadge(type: view.type, level: view.level),
                  if (view.category.isNotEmpty) _chip(view.category.toUpperCase(), accent),
                  if (view.environment != '—') _chip(view.environment.toUpperCase(), AppTheme.success),
                  if (view.platform != '—') _chip(view.platform, AppTheme.muted),
                  if (view.release != '—') _chip(view.release, AppTheme.muted),
                ]),
                const SizedBox(height: 14),
                Text(view.message, style: TextStyle(fontSize: MediaQuery.sizeOf(context).width < 600 ? 16 : 18, fontWeight: FontWeight.w800, height: 1.35)),
                if (timeLabel != null) ...[
                  const SizedBox(height: 10),
                  Text(timeLabel!, style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  static Color _accent(String type) => switch (type) {
        'crash' => AppTheme.error,
        'network' => AppTheme.warning,
        _ => AppTheme.primary,
      };

  static Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );
}

class EventQuickFacts extends StatelessWidget {
  const EventQuickFacts({super.key, required this.view, this.onSessionTap, this.onUserTap, this.onCountryTap});

  final EventView view;
  final VoidCallback? onSessionTap;
  final VoidCallback? onUserTap;
  final VoidCallback? onCountryTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        if (view.userId != '—') _fact(Icons.person_outline, 'User', view.userId, onUserTap),
        if (view.sessionId != '—') _fact(Icons.play_circle_outline, 'Session', view.sessionId.length > 12 ? '${view.sessionId.substring(0, 12)}…' : view.sessionId, onSessionTap),
        if (view.country != '—') _fact(Icons.public, 'Location', view.locationLabel, onCountryTap),
        if (view.route != '—') _fact(Icons.route_outlined, 'Screen', view.route, null),
        if (view.statusCode.isNotEmpty) _fact(Icons.http, 'Status', view.statusCode, null),
        if (view.network.isNotEmpty && view.network['durationMs'] != null)
          _fact(Icons.timer_outlined, 'Duration', '${view.network['durationMs']} ms', null),
      ],
    );
  }

  Widget _fact(IconData icon, String label, String value, VoidCallback? onTap) {
    final card = Container(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 200),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.panelElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: card),
    );
  }
}

class EventFlowDiagram extends StatelessWidget {
  const EventFlowDiagram({super.key, required this.view});

  final EventView view;

  @override
  Widget build(BuildContext context) {
    final nodes = [
      _Node(Icons.phone_android_outlined, 'Device', _deviceLabel(view)),
      _Node(Icons.verified_outlined, 'Release', view.release),
      _Node(Icons.route_outlined, 'Screen', view.route),
      _Node(Icons.lan_outlined, 'Network', view.url.isEmpty ? '—' : '${view.method.isEmpty ? '' : '${view.method} '}${view.url}'),
      _Node(Icons.public, 'Location', view.locationLabel),
      _Node(Icons.person_outline, 'User', view.userId),
    ].where((n) => n.value != '—' && !n.value.endsWith('· —')).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 700) {
          return Column(
            children: [
              for (var i = 0; i < nodes.length; i++) ...[
                if (i > 0) const Icon(Icons.arrow_downward, size: 14, color: AppTheme.muted),
                _nodeBox(nodes[i]),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < nodes.length; i++) ...[
              if (i > 0) const Padding(padding: EdgeInsets.only(top: 20, left: 4, right: 4), child: Icon(Icons.arrow_forward, size: 14, color: AppTheme.muted)),
              Expanded(child: _nodeBox(nodes[i])),
            ],
          ],
        );
      }),
    );
  }

  static String _deviceLabel(EventView view) {
    final name = str(view.device['deviceName']);
    if (name != null && name != 'unknown') return '$name · ${view.platform}';
    return '${view.platform} · ${view.appVersion}';
  }

  Widget _nodeBox(_Node n) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppTheme.panelElevated, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(n.icon, size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(n.title, style: const TextStyle(fontSize: 10, color: AppTheme.muted, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          Text(n.value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.text)),
        ]),
      );
}

class _Node {
  _Node(this.icon, this.title, this.value);
  final IconData icon;
  final String title;
  final String value;
}

class InfoSection extends StatelessWidget {
  const InfoSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.initiallyExpanded = true,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      color: AppTheme.panel,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          backgroundColor: AppTheme.panel,
          collapsedBackgroundColor: AppTheme.panel,
          iconColor: AppTheme.muted,
          collapsedIconColor: AppTheme.muted,
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: AppTheme.primary),
          ),
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          subtitle: subtitle != null
              ? Text(subtitle!,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12))
              : null,
          children: [child],
        ),
      ),
    );
  }
}

/// Top-level accordion group (replaces tab panels).
class EventDetailGroup extends StatefulWidget {
  const EventDetailGroup({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
    this.initiallyExpanded = false,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  State<EventDetailGroup> createState() => _EventDetailGroupState();
}

class _EventDetailGroupState extends State<EventDetailGroup> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      color: AppTheme.panelElevated,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(widget.icon, size: 20, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16)),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(widget.subtitle!,
                                style: const TextStyle(
                                    color: AppTheme.muted, fontSize: 12)),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      color: AppTheme.muted,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.children,
                ),
              ),
              crossFadeState:
                  _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              sizeCurve: Curves.easeOut,
            ),
          ],
        ),
      ),
    );
  }
}

class FieldGrid extends StatelessWidget {
  const FieldGrid({super.key, required this.fields});

  final List<DetailField> fields;

  @override
  Widget build(BuildContext context) {
    final visible = fields.where((f) => f.value.isNotEmpty && f.value != '—').toList();
    if (visible.isEmpty) return const Text('No data', style: TextStyle(color: AppTheme.muted));
    return Column(
      children: visible
          .map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: f.block ? _blockField(f) : _rowField(f),
              ))
          .toList(),
    );
  }

  Widget _rowField(DetailField f) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(f.label, style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
          Expanded(child: _valueText(f)),
        ],
      );

  Widget _blockField(DetailField f) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(f.label, style: const TextStyle(color: AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.codeBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: _valueText(f),
          ),
        ],
      );

  Widget _valueText(DetailField f) => SelectableText(
        f.value,
        style: TextStyle(
          fontSize: 13,
          fontFamily: f.mono ? 'monospace' : null,
          color: f.highlight ? AppTheme.primary : AppTheme.text,
          fontWeight: f.highlight ? FontWeight.w600 : FontWeight.normal,
          height: f.mono ? 1.45 : null,
        ),
      );
}

class SummaryList extends StatelessWidget {
  const SummaryList({super.key, required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: lines
          .map((line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check_circle_outline, size: 16, color: AppTheme.success),
                  const SizedBox(width: 8),
                  Expanded(child: Text(line, style: const TextStyle(fontSize: 13, height: 1.45))),
                ]),
              ))
          .toList(),
    );
  }
}

class StackTracePanel extends StatelessWidget {
  const StackTracePanel({super.key, required this.stack});

  final String stack;

  @override
  Widget build(BuildContext context) {
    if (stack.trim().isEmpty) return const SizedBox.shrink();
    final lines = stack.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.codeBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: AppTheme.codeHeader, borderRadius: const BorderRadius.vertical(top: Radius.circular(9))),
          child: Row(children: [
            Icon(Icons.terminal, size: 16, color: AppTheme.muted),
            const SizedBox(width: 8),
            Text('${lines.length} frame${lines.length == 1 ? '' : 's'}', style: TextStyle(color: AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: stack));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stack trace copied')));
              },
              icon: Icon(Icons.copy, size: 14, color: AppTheme.muted),
              label: Text('Copy', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            ),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(14),
          child: SelectableText(
            lines.asMap().entries.map((e) => '#${e.key}  ${e.value}').join('\n'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppTheme.text, height: 1.55),
          ),
        ),
      ]),
    );
  }
}

class JsonPanel extends StatelessWidget {
  const JsonPanel({super.key, required this.data});

  final dynamic data;

  @override
  Widget build(BuildContext context) {
    final text = prettyJson(data);
    if (text.isEmpty) return const Text('—', style: TextStyle(color: AppTheme.muted));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.panelElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppTheme.text, height: 1.5)),
    );
  }
}

class BreadcrumbTrail extends StatelessWidget {
  const BreadcrumbTrail({super.key, required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('No screen trail recorded', style: TextStyle(color: AppTheme.muted));
    }
    final missingNav = items.any((s) => s['hasNavigationType'] != true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (missingNav)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
            ),
            child: const Text(
              'Navigation type (push / pop / replace) is missing on some steps. '
              'Update scout_logger_plus to send navigationType on each screenTrail item '
              '(see packages/scout_models navigation.dart).',
              style: TextStyle(color: AppTheme.warning, fontSize: 12, height: 1.4),
            ),
          ),
        ...items.asMap().entries.map((entry) {
          final i = entry.key;
          final step = entry.value;
          final label = str(step['label']) ??
              str(step['name']) ??
              str(step['screenName']) ??
              str(step['route']) ??
              str(step['message']) ??
              'step';
          final route = str(step['route']);
          final time = str(step['timestamp']) ?? str(step['at']) ?? str(step['time']);
          final nav = parseNavTransition(step);
          final duration = step['durationMs'];
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 28,
                child: Column(children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.primary),
                    ),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.w700)),
                  ),
                  if (i < items.length - 1)
                    Expanded(child: Container(width: 2, color: AppTheme.border)),
                ]),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.panelElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (route != null && route != label)
                              Text(route,
                                  style: const TextStyle(
                                      color: AppTheme.muted, fontSize: 11, fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                      _NavBadge(nav: nav),
                    ]),
                    if (time != null || duration != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (time != null) _fmtTime(time),
                          if (duration != null) '${duration}ms on screen',
                        ].join(' · '),
                        style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                      ),
                    ],
                  ]),
                ),
              ),
            ]),
          );
        }),
      ],
    );
  }

  static String _fmtTime(String iso) {
    try {
      return DateFormat('MMM d · HH:mm:ss').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }
}

class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.nav});

  final NavTransition nav;

  @override
  Widget build(BuildContext context) {
    final known = nav.isKnown;
    final color = known ? AppTheme.primary : AppTheme.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: known ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon(nav), size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            known ? nav.label.toUpperCase() : 'NO NAV',
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  static IconData _icon(NavTransition nav) => switch (nav) {
        NavTransition.push => Icons.arrow_forward,
        NavTransition.pop => Icons.arrow_back,
        NavTransition.replace => Icons.swap_horiz,
        NavTransition.remove => Icons.close,
        NavTransition.go => Icons.route,
        NavTransition.unknown => Icons.help_outline,
      };
}

class NetworkReadablePanel extends StatelessWidget {
  const NetworkReadablePanel({super.key, required this.view});

  final EventView view;

  @override
  Widget build(BuildContext context) {
    final readable = view.networkReadable;
    if (readable.isEmpty) return const SizedBox.shrink();

    final outcome = str(readable['outcome']) ?? 'failed';
    final accent = switch (outcome) {
      'success' => AppTheme.success,
      'no_response' => AppTheme.error,
      'http_error' => AppTheme.warning,
      _ => AppTheme.warning,
    };
    final request = asMap(readable['request']);
    final response = asMap(readable['response']);
    final lines = readable['lines'];
    final curl = str(view.network['curl']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Icon(_outcomeIcon(outcome), color: accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                  child: Text(str(readable['outcomeLabel']) ?? outcome, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: accent)),
                ),
                const SizedBox(height: 8),
                Text(str(readable['title']) ?? view.message, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.35)),
                if (str(readable['duration']) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Duration: ${readable['duration']}', style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                  ),
                if (readable['slow'] == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Slow request (≥ ${readable['slowThresholdMs'] ?? '—'} ms)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.warning),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _flowBox(Icons.upload_outlined, 'Request', str(request['summary']) ?? '—', str(request['url']))),
          const Padding(padding: EdgeInsets.only(top: 28, left: 8, right: 8), child: Icon(Icons.arrow_forward, size: 16, color: AppTheme.muted)),
          Expanded(child: _flowBox(Icons.download_outlined, 'Response', str(response['summary']) ?? '—', response['hasResponse'] == true ? 'HTTP ${response['statusCode'] ?? '—'}' : null)),
        ]),
        if (lines is List && lines.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('What happened', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.muted)),
          const SizedBox(height: 8),
          ...lines.whereType<String>().map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('• ', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
                    Expanded(child: Text(line, style: const TextStyle(fontSize: 13, height: 1.45))),
                  ]),
                ),
              ),
        ],
        if (curl != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: curl));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('cURL copied')));
              },
              icon: const Icon(Icons.terminal, size: 16),
              label: const Text('Copy cURL'),
            ),
          ),
        ],
      ],
    );
  }

  static IconData _outcomeIcon(String outcome) => switch (outcome) {
        'success' => Icons.check_circle_outline,
        'no_response' => Icons.cloud_off_outlined,
        _ => Icons.error_outline,
      };

  static Widget _flowBox(IconData icon, String title, String summary, String? sub) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.panelElevated, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(fontSize: 10, color: AppTheme.muted, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Text(summary, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.text), maxLines: 3, overflow: TextOverflow.ellipsis),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub, style: const TextStyle(fontSize: 11, color: AppTheme.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ]),
      );
}

class RelatedEventTile extends StatelessWidget {
  const RelatedEventTile({super.key, required this.event, this.onTap, this.highlight = false});

  final Map<String, dynamic> event;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final level = str(event['level']);
    final route = str(event['route']);
    final url = str(event['networkUrl']);
    final status = str(event['statusCode']);
    final detail = url != null
        ? '${status != null ? '$status · ' : ''}$url'
        : route ?? '${event['type']} · ${event['country'] ?? '—'}';

    return Material(
      color: highlight ? AppTheme.primary.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        onTap: onTap,
        title: Text(
          str(event['message']) ?? str(event['type']) ?? 'Event',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: highlight ? FontWeight.w800 : FontWeight.w600, fontSize: 13),
        ),
        subtitle: Text('${_fmtTime(str(event['occurredAt']))} · ${level ?? event['type']} · $detail', style: const TextStyle(fontSize: 12)),
        trailing: onTap != null ? const Icon(Icons.chevron_right, size: 18, color: AppTheme.muted) : null,
      ),
    );
  }

  static String _fmtTime(String? iso) {
    if (iso == null) return '—';
    try {
      return DateFormat('MMM d HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }
}
