import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scout_models/scout_models.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../widgets/page_header.dart';

class ProjectNotificationsScreen extends StatefulWidget {
  const ProjectNotificationsScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<ProjectNotificationsScreen> createState() => _ProjectNotificationsScreenState();
}

class _ProjectNotificationsScreenState extends State<ProjectNotificationsScreen> {
  final _api = ScoutApi();
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  bool _saving = false;
  Object? _error;
  bool _isOwner = false;

  bool _enabled = false;
  int _dedupMinutes = kDefaultDedupMinutes;
  Set<String> _categories = kDefaultNotificationCategories.toSet();
  Set<String> _channels = {'slack', 'email', 'whatsapp'};
  Set<String> _environments = kDefaultNotificationEnvironments.toSet();

  bool _slackOn = false;
  bool _waOn = false;
  bool _emailOn = false;
  bool _slackConfigured = false;
  bool _waConfigured = false;
  bool _emailConfigured = false;
  Map<String, bool> _platform = {'slack': true, 'whatsapp': true, 'email': true};

  final _slackWebhookCtrl = TextEditingController();
  final _waPhoneCtrl = TextEditingController();
  final _waKeyCtrl = TextEditingController();
  final _smtpUserCtrl = TextEditingController();
  final _smtpPassCtrl = TextEditingController();
  final _smtpFromCtrl = TextEditingController();
  final _recipientsCtrl = TextEditingController();

  List<Map<String, dynamic>> _deliveries = [];

  @override
  void dispose() {
    _slackWebhookCtrl.dispose();
    _waPhoneCtrl.dispose();
    _waKeyCtrl.dispose();
    _smtpUserCtrl.dispose();
    _smtpPassCtrl.dispose();
    _smtpFromCtrl.dispose();
    _recipientsCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
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
      final results = await Future.wait([
        _api.fetchProjectNotifications(widget.projectId),
        _api.fetchProjects(),
        _api.fetchNotificationDeliveries(widget.projectId),
      ]);
      final cfg = results[0] as Map<String, dynamic>;
      final projects = results[1] as List<Map<String, dynamic>>;
      final deliveries = results[2] as List<Map<String, dynamic>>;
      String? role;
      for (final p in projects) {
        if (p['id'] == widget.projectId) {
          role = p['role'] as String?;
          break;
        }
      }
      if (AuthService.instance.isAdmin) role = 'owner';
      _applyConfig(cfg);
      if (mounted) {
        setState(() {
          _isOwner = role == 'owner' || AuthService.instance.isAdmin;
          _deliveries = deliveries;
          _hasData = true;
          _loading = false;
          _refreshing = false;
        });
      }
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

  void _applyConfig(Map<String, dynamic> cfg) {
    _enabled = cfg['enabled'] == true;
    _dedupMinutes = cfg['dedupMinutes'] as int? ?? kDefaultDedupMinutes;
    final rules = cfg['rules'] as List?;
    final rule = rules?.isNotEmpty == true ? Map<String, dynamic>.from(rules!.first as Map) : <String, dynamic>{};
    _categories = (rule['categories'] as List?)?.map((e) => e.toString()).toSet() ?? kDefaultNotificationCategories.toSet();
    _channels = (rule['channels'] as List?)?.map((e) => e.toString()).toSet() ?? _channels;
    _environments = (rule['environments'] as List?)?.map((e) => e.toString()).toSet() ?? kDefaultNotificationEnvironments.toSet();

    final platform = cfg['platform'] is Map ? Map<String, dynamic>.from(cfg['platform'] as Map) : <String, dynamic>{};
    _platform = {
      'slack': platform['slack'] != false,
      'whatsapp': platform['whatsapp'] != false,
      'email': platform['email'] != false,
    };

    final ch = cfg['channels'] is Map ? Map<String, dynamic>.from(cfg['channels'] as Map) : <String, dynamic>{};
    final slack = ch['slack'] is Map ? Map<String, dynamic>.from(ch['slack'] as Map) : <String, dynamic>{};
    final wa = ch['whatsapp'] is Map ? Map<String, dynamic>.from(ch['whatsapp'] as Map) : <String, dynamic>{};
    final email = ch['email'] is Map ? Map<String, dynamic>.from(ch['email'] as Map) : <String, dynamic>{};

    _slackOn = slack['enabled'] == true;
    _waOn = wa['enabled'] == true;
    _emailOn = email['enabled'] == true;
    _slackConfigured = slack['configured'] == true;
    _waConfigured = wa['configured'] == true;
    _emailConfigured = email['configured'] == true;
    _recipientsCtrl.text = (email['recipients'] as List?)?.join(', ') ?? '';
  }

  Map<String, dynamic> _buildPatch() {
    final patch = <String, dynamic>{
      'enabled': _enabled,
      'dedupMinutes': _dedupMinutes,
      'rules': [
        {
          'id': 'default',
          'enabled': true,
          'categories': _categories.toList(),
          'channels': _channels.toList(),
          'environments': _environments.toList(),
        },
      ],
      'channels': {
        'slack': {'enabled': _slackOn, if (_slackWebhookCtrl.text.trim().isNotEmpty) 'webhookUrl': _slackWebhookCtrl.text.trim()},
        'whatsapp': {
          'enabled': _waOn,
          if (_waPhoneCtrl.text.trim().isNotEmpty) 'phone': _waPhoneCtrl.text.trim(),
          if (_waKeyCtrl.text.trim().isNotEmpty) 'apiKey': _waKeyCtrl.text.trim(),
        },
        'email': {
          'enabled': _emailOn,
          'smtpHost': 'smtp.gmail.com',
          'smtpPort': 587,
          if (_smtpUserCtrl.text.trim().isNotEmpty) 'smtpUser': _smtpUserCtrl.text.trim(),
          if (_smtpPassCtrl.text.trim().isNotEmpty) 'smtpPassword': _smtpPassCtrl.text.trim(),
          if (_smtpFromCtrl.text.trim().isNotEmpty) 'from': _smtpFromCtrl.text.trim(),
          'recipients': _recipientsCtrl.text.split(RegExp(r'[,\s]+')).where((s) => s.contains('@')).toList(),
        },
      },
    };
    return patch;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final cfg = await _api.updateProjectNotifications(widget.projectId, _buildPatch());
      _applyConfig(cfg);
      _slackWebhookCtrl.clear();
      _waPhoneCtrl.clear();
      _waKeyCtrl.clear();
      _smtpUserCtrl.clear();
      _smtpPassCtrl.clear();
      _smtpFromCtrl.clear();
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alert settings saved')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _test(String channel) async {
    try {
      await _api.updateProjectNotifications(widget.projectId, _buildPatch());
      await _api.testProjectNotification(widget.projectId, channel);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Test $channel alert sent')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && !_isOwner) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline, size: 48, color: AppTheme.muted),
          const SizedBox(height: 12),
          const Text('Only the project owner can manage alert notifications'),
          const SizedBox(height: 16),
          TextButton(onPressed: () => context.go('/p/${widget.projectId}/settings'), child: const Text('Back to settings')),
        ]),
      );
    }

    return AsyncScreenBody(
      loading: _loading,
      refreshing: _refreshing,
      error: _error,
      onRetry: _load,
      placeholderLayout: PlaceholderLayout.settings,
      builder: _buildContent,
    );
  }

  Widget _buildContent(BuildContext context) {
    return ListView(
      padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
      children: [
        PageHeader(
          title: 'Alert notifications',
          subtitle: 'Slack, WhatsApp (CallMeBot), and Gmail SMTP — critical events only',
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
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => context.go('/p/${widget.projectId}/settings'),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Project settings'),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable alerts', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Send notifications when matching events are ingested'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              const SizedBox(height: 8),
              Text('Dedup window (${_dedupMinutes} min)', style: const TextStyle(fontWeight: FontWeight.w600)),
              Slider(
                value: _dedupMinutes.toDouble(),
                min: 1,
                max: 120,
                divisions: 119,
                label: '${_dedupMinutes}m',
                onChanged: (v) => setState(() => _dedupMinutes = v.round()),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        _routingCard(),
        const SizedBox(height: 16),
        _setupCard(),
        const SizedBox(height: 16),
        _channelsCard(),
        if (_deliveries.isNotEmpty) ...[const SizedBox(height: 16), _deliveriesCard()],
      ],
    );
  }

  Widget _routingCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Routing', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Default: crash, error, and critical network failures in production.', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
            const SizedBox(height: 12),
            const Text('Categories', style: TextStyle(fontWeight: FontWeight.w600)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in kNotificationCategories)
                  FilterChip(
                    label: Text(_catLabel(c)),
                    selected: _categories.contains(c),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _categories.add(c);
                      } else if (_categories.length > 1) {
                        _categories.remove(c);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Environments', style: TextStyle(fontWeight: FontWeight.w600)),
            Wrap(
              spacing: 8,
              children: [
                for (final e in const ['production', 'staging', 'development', '*'])
                  FilterChip(
                    label: Text(e == '*' ? 'All' : e),
                    selected: _environments.contains(e),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _environments.add(e);
                      } else if (_environments.length > 1) {
                        _environments.remove(e);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Channels', style: TextStyle(fontWeight: FontWeight.w600)),
            Wrap(
              spacing: 8,
              children: [
                for (final ch in kNotificationChannels)
                  FilterChip(
                    label: Text(ch[0].toUpperCase() + ch.substring(1)),
                    selected: _channels.contains(ch) && (_platform[ch] ?? true),
                    onSelected: (_platform[ch] ?? true)
                        ? (on) => setState(() {
                              if (on) {
                                _channels.add(ch);
                              } else if (_channels.length > 1) {
                                _channels.remove(ch);
                              }
                            })
                        : null,
                  ),
              ],
            ),
            if (_platform.values.contains(false))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Some channels are disabled by the platform administrator.',
                  style: TextStyle(color: AppTheme.warning.withValues(alpha: 0.9), fontSize: 13),
                ),
              ),
          ]),
        ),
      );

  Widget _setupCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Setup guide', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            _guideSection(
              'Slack (free incoming webhook)',
              const [
                'Create a Slack app at api.slack.com/apps → Create New App → From scratch.',
                'Enable Incoming Webhooks and add a webhook to your channel.',
                'Copy the webhook URL (starts with https://hooks.slack.com/).',
                'Paste it below and tap Save, then Send test.',
              ],
            ),
            const Divider(height: 24),
            _guideSection(
              'WhatsApp via CallMeBot (free)',
              const [
                'Add +34 684 72 39 62 to your phone contacts as CallMeBot.',
                'Send this WhatsApp message: I allow callmebot to send me messages',
                'CallMeBot replies with your personal API key.',
                'Enter phone in international format without + (e.g. 9665xxxxxxx) and the API key below.',
                'Note: free tier has rate limits; keep dedup window ≥ 15 minutes.',
              ],
            ),
            const Divider(height: 24),
            _guideSection(
              'Email via Gmail SMTP',
              const [
                'Use a Google account with 2-step verification enabled.',
                'Google Account → Security → App passwords → create an app password for Mail.',
                'SMTP host: smtp.gmail.com, port 587 (TLS).',
                'Enter Gmail address + 16-character app password below (not your login password).',
                'Add recipient addresses (comma-separated) for your on-call team.',
              ],
            ),
          ]),
        ),
      );

  Widget _guideSection(String title, List<String> steps) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${i + 1}. ${steps[i]}', style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
            ),
        ],
      );

  Widget _channelsCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Channel credentials', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Secrets are encrypted at rest. Leave blank to keep existing values.', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
            if (_platform['slack'] == true) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Slack ${_slackConfigured ? '(configured)' : ''}'),
                value: _slackOn,
                onChanged: (v) => setState(() => _slackOn = v),
              ),
              TextField(
                controller: _slackWebhookCtrl,
                decoration: const InputDecoration(labelText: 'Webhook URL', hintText: 'https://hooks.slack.com/services/...'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: _slackOn ? () => _test('slack') : null, child: const Text('Send test')),
              ),
            ],
            if (_platform['whatsapp'] == true) ...[
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('WhatsApp ${_waConfigured ? '(configured)' : ''}'),
                value: _waOn,
                onChanged: (v) => setState(() => _waOn = v),
              ),
              TextField(controller: _waPhoneCtrl, decoration: const InputDecoration(labelText: 'Phone (no +)', hintText: '9665xxxxxxxx')),
              const SizedBox(height: 8),
              TextField(controller: _waKeyCtrl, decoration: const InputDecoration(labelText: 'CallMeBot API key'), obscureText: true),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: _waOn ? () => _test('whatsapp') : null, child: const Text('Send test')),
              ),
            ],
            if (_platform['email'] == true) ...[
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Email (Gmail) ${_emailConfigured ? '(configured)' : ''}'),
                value: _emailOn,
                onChanged: (v) => setState(() => _emailOn = v),
              ),
              TextField(controller: _smtpUserCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Gmail address')),
              const SizedBox(height: 8),
              TextField(controller: _smtpPassCtrl, decoration: const InputDecoration(labelText: 'App password'), obscureText: true),
              const SizedBox(height: 8),
              TextField(controller: _smtpFromCtrl, decoration: const InputDecoration(labelText: 'From (optional, defaults to Gmail address)')),
              const SizedBox(height: 8),
              TextField(controller: _recipientsCtrl, decoration: const InputDecoration(labelText: 'Recipients', hintText: 'ops@company.com, oncall@company.com')),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: _emailOn ? () => _test('email') : null, child: const Text('Send test')),
              ),
            ],
          ]),
        ),
      );

  Widget _deliveriesCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Recent deliveries', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            for (final d in _deliveries.take(20))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('${d['channel']} · ${d['category']} · ${d['status']}', style: const TextStyle(fontSize: 13)),
                subtitle: Text('${d['createdAt'] ?? ''}${d['errorMessage'] != null ? ' — ${d['errorMessage']}' : ''}', style: const TextStyle(fontSize: 12)),
              ),
          ]),
        ),
      );

  String _catLabel(String c) => switch (c) {
        'crash' => 'Crash',
        'error' => 'Error',
        'network_critical' => 'Network critical',
        'network_transport' => 'Transport',
        'network_user' => 'Network user',
        'network_auth' => 'Network auth',
        _ => c,
      };
}
