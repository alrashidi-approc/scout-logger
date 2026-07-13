import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/event_detail_screen.dart';
import '../screens/issue_detail_screen.dart';
import '../screens/link_fallback_screen.dart';
import '../screens/shared_alert_screen.dart';
import '../services/api_client.dart';
import '../utils/clipboard.dart';
import '../utils/share_seo.dart';
import '../theme/app_theme.dart';
import '../widgets/page_placeholder.dart';

final _shareTokenRe = RegExp(r'^[a-zA-Z0-9_-]{20,128}$');

class SharedDetailScreen extends StatefulWidget {
  const SharedDetailScreen({super.key, required this.token});

  final String token;

  @override
  State<SharedDetailScreen> createState() => _SharedDetailScreenState();
}

class _SharedDetailScreenState extends State<SharedDetailScreen> {
  final _api = ScoutApi();
  String? _type;
  Map<String, dynamic>? _event;
  Map<String, dynamic>? _issue;
  Map<String, dynamic>? _alertData;
  String? _expiresAt;
  bool _loading = true;
  bool _invalid = false;

  @override
  void dispose() {
    clearShareSeo();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (!_shareTokenRe.hasMatch(widget.token)) {
      _invalid = true;
      _loading = false;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _invalid = false;
      _loading = true;
    });
    try {
      final res = await _api.fetchShare(widget.token);
      if (!mounted) return;
      final type = res['type'] as String?;
      if (type == 'alert') {
        setState(() {
          _type = type;
          _alertData = res;
          _expiresAt = res['expiresAt'] as String?;
          _loading = false;
        });
      } else {
        setState(() {
          _type = type;
          _event = res['event'] is Map ? Map<String, dynamic>.from(res['event'] as Map) : null;
          _issue = res['issue'] is Map ? Map<String, dynamic>.from(res['issue'] as Map) : null;
          _expiresAt = res['expiresAt'] as String?;
          _loading = false;
        });
      }
      _syncSeo();
    } catch (_) {
      if (mounted) {
        setState(() {
          _invalid = true;
          _loading = false;
        });
      }
    }
  }

  void _syncSeo() {
    applyShareSeo(
      title: _type == 'alert'
          ? (_alertData?['title'] as String? ?? 'Scout alert')
          : shareSeoTitle(type: _type, issue: _issue, event: _event),
      description: _type == 'alert'
          ? (_alertData?['summary'] as String? ?? 'Read-only Scout alert')
          : shareSeoDescription(type: _type, issue: _issue, event: _event),
      url: _shareUrl,
    );
  }

  String get _shareUrl {
    final base = Uri.base;
    final path = base.path.endsWith('/') ? base.path : '${base.path}/';
    return '${base.origin}${path}share/${widget.token}';
  }

  @override
  Widget build(BuildContext context) {
    if (_invalid) return const LinkFallbackScreen();
    if (_loading) {
      return const Material(color: AppTheme.bg, child: ScoutBootstrapView());
    }
    if (_type == 'alert' && _alertData != null) {
      return SharedAlertScreen(token: widget.token, data: _alertData!);
    }
    return Material(
      color: AppTheme.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SharedBanner(shareUrl: _shareUrl, expiresAt: _expiresAt, onCopy: () => _copyLink(context)),
          Expanded(
            child: _type == 'event' && _event != null
                ? EventDetailScreen.viewOnly(initialEvent: _event!, shareUrl: _shareUrl)
                : _type == 'issue' && _issue != null
                    ? IssueDetailScreen.viewOnly(initialIssue: _issue!, shareUrl: _shareUrl)
                    : const LinkFallbackScreen(),
          ),
        ],
      ),
    );
  }

  void _copyLink(BuildContext context) => copyWithFeedback(context, _shareUrl, message: 'Share link copied');
}

class _SharedBanner extends StatelessWidget {
  const _SharedBanner({required this.shareUrl, this.expiresAt, required this.onCopy});

  final String shareUrl;
  final String? expiresAt;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final expiry = DateTime.tryParse(expiresAt ?? '');
    final expiryText = expiry != null ? 'Expires ${DateFormat.yMMMd().add_jm().format(expiry.toLocal())}' : null;

    return Material(
      color: AppTheme.panelElevated,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined, size: 16, color: AppTheme.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                expiryText != null ? 'Read-only · $expiryText' : 'Read-only · view only, no edits',
                style: const TextStyle(fontSize: 12, color: AppTheme.muted, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.share_outlined, size: 14),
              label: const Text('Copy link'),
            ),
          ],
        ),
      ),
    );
  }
}
