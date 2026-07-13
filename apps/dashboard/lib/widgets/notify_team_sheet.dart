import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';

String _channelLabel(String ch) => switch (ch) {
      'slack' => 'Slack',
      'whatsapp' => 'WhatsApp',
      'email' => 'Email',
      _ => ch,
    };

/// Pick enabled project channels and send a manual team alert (not a spike).
Future<void> showNotifyTeamSheet(
  BuildContext context, {
  required String projectId,
  required String resourceType,
  required String resourceId,
}) async {
  final api = ScoutApi();
  List<String> ready;
  try {
    ready = await api.fetchNotifyChannels(projectId);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    return;
  }

  if (!context.mounted) return;
  if (ready.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No channels ready'),
        content: const Text(
          'Enable and configure Slack, WhatsApp, or email under Settings → Notifications, then try again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/p/$projectId/notifications');
            },
            child: const Text('Open notifications'),
          ),
        ],
      ),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _NotifyTeamSheet(
      parentContext: context,
      projectId: projectId,
      resourceType: resourceType,
      resourceId: resourceId,
      ready: ready,
      api: api,
    ),
  );
}

class _NotifyTeamSheet extends StatefulWidget {
  const _NotifyTeamSheet({
    required this.parentContext,
    required this.projectId,
    required this.resourceType,
    required this.resourceId,
    required this.ready,
    required this.api,
  });

  final BuildContext parentContext;
  final String projectId;
  final String resourceType;
  final String resourceId;
  final List<String> ready;
  final ScoutApi api;

  @override
  State<_NotifyTeamSheet> createState() => _NotifyTeamSheetState();
}

class _NotifyTeamSheetState extends State<_NotifyTeamSheet> {
  late final Set<String> _picked = {...widget.ready};
  bool _sending = false;

  Future<void> _send() async {
    if (_picked.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await widget.api.notifyTeamShare(
        widget.projectId,
        resourceType: widget.resourceType,
        resourceId: widget.resourceId,
        channels: _picked.toList(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      final sent = (res['sent'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final failed = res['failed'] as List? ?? [];
      final msg = failed.isEmpty
          ? 'Sent to ${sent.map(_channelLabel).join(', ')}'
          : 'Sent to ${sent.map(_channelLabel).join(', ')} · ${failed.length} failed';
      if (widget.parentContext.mounted) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Notify team', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              '🟢 Manual share — not an automatic spike. Errors 🛑🛑 · crashes 🛑🟡',
              style: TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ch in widget.ready)
                  FilterChip(
                    label: Text(_channelLabel(ch)),
                    selected: _picked.contains(ch),
                    onSelected: _sending
                        ? null
                        : (on) => setState(() {
                              if (on) {
                                _picked.add(ch);
                              } else if (_picked.length > 1) {
                                _picked.remove(ch);
                              }
                            }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending || _picked.isEmpty ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_outlined, size: 18),
              label: Text(_sending ? 'Sending…' : 'Send alert'),
            ),
          ],
        ),
      ),
    );
  }
}
