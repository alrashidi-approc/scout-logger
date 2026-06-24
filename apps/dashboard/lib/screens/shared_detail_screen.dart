import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../screens/event_detail_screen.dart';
import '../screens/issue_detail_screen.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';

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
  String? _expiresAt;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final res = await _api.fetchShare(widget.token);
      if (!mounted) return;
      setState(() {
        _type = res['type'] as String?;
        _event = res['event'] is Map ? Map<String, dynamic>.from(res['event'] as Map) : null;
        _issue = res['issue'] is Map ? Map<String, dynamic>.from(res['issue'] as Map) : null;
        _expiresAt = res['expiresAt'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String get _shareUrl {
    final base = Uri.base;
    final path = base.path.endsWith('/') ? base.path : '${base.path}/';
    return '${base.origin}${path}share/${widget.token}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.bg,
      child: AsyncScreenBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        placeholderLayout: PlaceholderLayout.detail,
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SharedBanner(shareUrl: _shareUrl, expiresAt: _expiresAt, onCopy: () => _copyLink(context)),
            Expanded(
              child: _type == 'event' && _event != null
                  ? EventDetailScreen.viewOnly(initialEvent: _event!, shareUrl: _shareUrl)
                  : _type == 'issue' && _issue != null
                      ? IssueDetailScreen.viewOnly(initialIssue: _issue!, shareUrl: _shareUrl)
                      : const Center(child: Text('Not found', style: TextStyle(color: AppTheme.muted))),
            ),
          ],
        ),
      ),
    );
  }

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _shareUrl));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Share link copied')));
  }
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
            const Icon(Icons.link, size: 16, color: AppTheme.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                expiryText != null
                    ? 'Shared view — $expiryText'
                    : 'Shared view — this link only shows this event or issue',
                style: const TextStyle(fontSize: 12, color: AppTheme.muted, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.share_outlined, size: 14),
              label: const Text('Share link'),
            ),
          ],
        ),
      ),
    );
  }
}
