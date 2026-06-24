import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/page_header.dart';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() => _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  final _api = ScoutApi();
  bool _loading = true;
  Object? _error;
  bool _saving = false;
  bool _slack = true;
  bool _whatsapp = true;
  bool _email = true;

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
      final policy = await _api.fetchNotificationPolicy();
      if (mounted) {
        setState(() {
          _slack = policy['slack'] != false;
          _whatsapp = policy['whatsapp'] != false;
          _email = policy['email'] != false;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _api.updateNotificationPolicy({'slack': _slack, 'whatsapp': _whatsapp, 'email': _email});
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Platform notification policy saved')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.instance.isPlatformOwner) {
      return const Center(child: Text('Platform owner access required'));
    }

    return AsyncScreenBody(
      loading: _loading,
      error: _error,
      onRetry: _load,
      placeholderLayout: PlaceholderLayout.settings,
      builder: (context) => ListView(
        padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
        children: [
          PageHeader(
            title: 'Notification channels',
            subtitle: 'Control which alert channels project owners can use',
            actions: [
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Available channels', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 6),
                const Text(
                  'When disabled, project owners cannot enable or route alerts through that channel.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 13),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Slack webhooks'),
                  value: _slack,
                  onChanged: (v) => setState(() => _slack = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('WhatsApp (CallMeBot)'),
                  value: _whatsapp,
                  onChanged: (v) => setState(() => _whatsapp = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Email (Gmail SMTP per project)'),
                  value: _email,
                  onChanged: (v) => setState(() => _email = v),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
