import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scout_models/scout_models.dart';

import '../services/api_client.dart';
import '../services/project_access_service.dart';
import '../services/screen_cache.dart';
import '../theme/app_theme.dart';
import '../utils/notification_deliveries.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../widgets/page_header.dart';

class _EnvNotifyPrefs {
  _EnvNotifyPrefs({this.enabled = false, Set<String>? categories})
      : categories = categories ?? kDefaultNotificationCategories.toSet();

  bool enabled;
  Set<String> categories;
}

class ProjectNotificationsScreen extends StatefulWidget {
  const ProjectNotificationsScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<ProjectNotificationsScreen> createState() => _ProjectNotificationsScreenState();
}

class _ProjectNotificationsCache {
  const _ProjectNotificationsCache({
    required this.cfg,
    required this.facets,
    required this.deliveries,
    required this.summary,
    required this.isOwner,
  });
  final Map<String, dynamic> cfg;
  final Map<String, dynamic> facets;
  final List<Map<String, dynamic>> deliveries;
  final Map<String, dynamic> summary;
  final bool isOwner;
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
  int _maxAlertsPerHour = kDefaultMaxAlertsPerHour;
  int _groupMinutes = kDefaultGroupMinutes;

  bool _thresholdOn = false;
  String _thresholdMode = 'count';
  int _thresholdWindow = 15;
  int _thresholdErrors = 0;
  int _thresholdCrashes = 0;
  double _thresholdSensitivity = 3;

  bool _digestOn = false;
  String _digestFreq = 'daily';
  int _digestHour = 8;
  Set<String> _channels = {'slack', 'email', 'whatsapp'};
  final Map<String, _EnvNotifyPrefs> _envPrefs = {};
  List<String> _knownEnvs = const ['production', 'release', 'prod'];
  Set<String> _thresholdEnvs = {'production'};

  static bool _isReleaseEnvLabel(String env) {
    final e = env.trim().toLowerCase();
    return e == 'production' || e == 'prod' || e == 'release';
  }

  bool _slackOn = false;
  bool _waOn = false;
  bool _emailOn = false;
  bool _slackConfigured = false;
  bool _waConfigured = false;
  bool _emailConfigured = false;
  String? _emailUserHint;
  Map<String, bool> _platform = {'slack': true, 'whatsapp': true, 'email': true};

  final _slackWebhookCtrl = TextEditingController();
  final _waPhoneCtrl = TextEditingController();
  final _waKeyCtrl = TextEditingController();
  final _smtpUserCtrl = TextEditingController();
  final _smtpPassCtrl = TextEditingController();
  final _smtpFromCtrl = TextEditingController();
  final _recipientsCtrl = TextEditingController();

  List<Map<String, dynamic>> _deliveries = [];
  Map<String, dynamic> _summary = {};

  String get _cacheKey => screenCacheKey('project-notifications', projectId: widget.projectId);

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
    if (!_restore()) _load();
  }

  bool _restore() {
    final cached = ScreenCache.instance.read<_ProjectNotificationsCache>(_cacheKey);
    if (cached == null) return false;
    _applyConfig(cached.cfg, cached.facets);
    _deliveries = cached.deliveries;
    _summary = cached.summary;
    _isOwner = cached.isOwner;
    _hasData = true;
    _loading = false;
    _refreshing = false;
    _error = null;
    return true;
  }

  void _writeCache(Map<String, dynamic> cfg, Map<String, dynamic> facets) {
    ScreenCache.instance.write(
      _cacheKey,
      _ProjectNotificationsCache(
        cfg: cfg,
        facets: facets,
        deliveries: _deliveries,
        summary: _summary,
        isOwner: _isOwner,
      ),
    );
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
      await ProjectAccessService.instance.load();
      final results = await Future.wait([
        _api.fetchProjectNotifications(widget.projectId),
        _api.fetchNotificationDeliveries(widget.projectId),
        _api.fetchFilterFacets(widget.projectId),
      ]);
      final cfg = results[0] as Map<String, dynamic>;
      final deliveryData = results[1] as Map<String, dynamic>;
      final facets = results[2] as Map<String, dynamic>;
      final deliveries = (deliveryData['deliveries'] as List).cast<Map<String, dynamic>>();
      final summary = Map<String, dynamic>.from(deliveryData['summary'] as Map? ?? {});
      _applyConfig(cfg, facets);
      if (mounted) {
        setState(() {
          _isOwner = true;
          _deliveries = deliveries;
          _summary = summary;
          _hasData = true;
          _loading = false;
          _refreshing = false;
        });
        _writeCache(cfg, facets);
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

  void _applyConfig(Map<String, dynamic> cfg, Map<String, dynamic> facets) {
    _enabled = cfg['enabled'] == true;
    _dedupMinutes = cfg['dedupMinutes'] as int? ?? kDefaultDedupMinutes;
    _maxAlertsPerHour = cfg['maxAlertsPerHour'] as int? ?? kDefaultMaxAlertsPerHour;
    _groupMinutes = cfg['groupMinutes'] as int? ?? kDefaultGroupMinutes;

    final observed = (facets['environments'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? [];
    final fromRules = <String>{};
    _envPrefs.clear();
    final rules = cfg['rules'] as List?;
    if (rules != null) {
      for (final raw in rules) {
        if (raw is! Map) continue;
        final rule = Map<String, dynamic>.from(raw);
        final envs = (rule['environments'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final cats = (rule['categories'] as List?)?.map((e) => e.toString()).toSet() ?? kDefaultNotificationCategories.toSet();
        final ruleChannels = (rule['channels'] as List?)?.map((e) => e.toString()).toSet();
        if (ruleChannels != null && ruleChannels.isNotEmpty) _channels = ruleChannels;
        final on = rule['enabled'] != false;
        for (final env in envs) {
          if (env == '*') continue;
          fromRules.add(env);
          _envPrefs[env] = _EnvNotifyPrefs(enabled: on, categories: cats);
        }
      }
    }
    _knownEnvs = {
      ...const ['production', 'release', 'prod'],
      ...observed.where(_isReleaseEnvLabel),
      ...fromRules.where(_isReleaseEnvLabel),
    }.toList()
      ..sort();
    for (final env in _knownEnvs) {
      _envPrefs.putIfAbsent(
        env,
        () => _EnvNotifyPrefs(
          enabled: _isReleaseEnvLabel(env),
          categories: kDefaultNotificationCategories.toSet(),
        ),
      );
    }

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
    _emailUserHint = email['smtpUserHint'] as String?;
    _recipientsCtrl.text = (email['recipients'] as List?)?.join(', ') ?? '';

    final t = cfg['threshold'] is Map ? Map<String, dynamic>.from(cfg['threshold'] as Map) : <String, dynamic>{};
    _thresholdOn = t['enabled'] == true;
    _thresholdMode = t['mode'] == 'anomaly' ? 'anomaly' : 'count';
    _thresholdWindow = t['windowMinutes'] as int? ?? 15;
    _thresholdErrors = t['errorCount'] as int? ?? 0;
    _thresholdCrashes = t['crashCount'] as int? ?? 0;
    _thresholdSensitivity = (t['sensitivity'] as num?)?.toDouble() ?? 3;
    final thresholdEnvs = (t['environments'] as List?)?.map((e) => e.toString()).where(_isReleaseEnvLabel).toSet() ?? <String>{};
    _thresholdEnvs = thresholdEnvs.isEmpty ? {'production'} : thresholdEnvs;

    final dg = cfg['digest'] is Map ? Map<String, dynamic>.from(cfg['digest'] as Map) : <String, dynamic>{};
    _digestOn = dg['enabled'] == true;
    _digestFreq = dg['frequency'] == 'weekly' ? 'weekly' : 'daily';
    _digestHour = dg['hourUtc'] as int? ?? 8;
  }

  Map<String, dynamic> _buildPatch() {
    final patch = <String, dynamic>{
      'enabled': _enabled,
      'dedupMinutes': _dedupMinutes,
      'maxAlertsPerHour': _maxAlertsPerHour,
      'groupMinutes': _groupMinutes,
      'rules': [
        for (final env in _knownEnvs)
          if (_envPrefs[env]?.enabled == true && (_envPrefs[env]?.categories.isNotEmpty ?? false))
            {
              'id': env,
              'enabled': true,
              'categories': _envPrefs[env]!.categories.toList(),
              'channels': _channels.toList(),
              'environments': [env],
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
      'threshold': {
        'enabled': _thresholdOn,
        'mode': _thresholdMode,
        'windowMinutes': _thresholdWindow,
        'errorCount': _thresholdErrors,
        'crashCount': _thresholdCrashes,
        'sensitivity': _thresholdSensitivity,
        'channels': _channels.toList(),
        'environments': _thresholdEnvs.toList(),
      },
      'digest': {
        'enabled': _digestOn,
        'frequency': _digestFreq,
        'hourUtc': _digestHour,
        'channel': 'email',
      },
    };
    return patch;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final cfg = await _api.updateProjectNotifications(widget.projectId, _buildPatch());
      final facets = await _api.fetchFilterFacets(widget.projectId);
      _applyConfig(cfg, facets);
      _slackWebhookCtrl.clear();
      _waPhoneCtrl.clear();
      _waKeyCtrl.clear();
      _smtpUserCtrl.clear();
      _smtpPassCtrl.clear();
      _smtpFromCtrl.clear();
      if (mounted) {
        setState(() => _saving = false);
        _writeCache(cfg, facets);
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
    if (!_loading && !_isOwner && _error == null && !_hasData) {
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
          subtitle: 'Slack, WhatsApp, and Gmail — control alerts per environment / flavor',
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable alerts', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Send notifications when matching events are ingested'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              const SizedBox(height: 8),
              Text('Dedup window ($_dedupMinutes min)', style: const TextStyle(fontWeight: FontWeight.w600)),
              Slider(
                value: _dedupMinutes.toDouble(),
                min: 1,
                max: 120,
                divisions: 119,
                label: '${_dedupMinutes}m',
                onChanged: (v) => setState(() => _dedupMinutes = v.round()),
              ),
              const SizedBox(height: 8),
              Text(
                _groupMinutes == 0 ? 'Group window: off (send immediately)' : 'Group window: $_groupMinutes min',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Slider(
                value: _groupMinutes.toDouble(),
                min: 0,
                max: 30,
                divisions: 30,
                label: _groupMinutes == 0 ? 'off' : '${_groupMinutes}m',
                onChanged: (v) => setState(() => _groupMinutes = v.round()),
              ),
              const Text(
                'Roll similar alerts on the same issue into one message per channel.',
                style: TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
              const SizedBox(height: 8),
              Text(
                _maxAlertsPerHour == 0 ? 'Rate limit: unlimited' : 'Rate limit: $_maxAlertsPerHour alerts/hour',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Slider(
                value: _maxAlertsPerHour.toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                label: _maxAlertsPerHour == 0 ? 'off' : '$_maxAlertsPerHour/h',
                onChanged: (v) => setState(() => _maxAlertsPerHour = v.round()),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        _routingCard(),
        const SizedBox(height: 16),
        _thresholdCard(),
        const SizedBox(height: 16),
        _digestCard(),
        const SizedBox(height: 16),
        _setupCard(),
        const SizedBox(height: 16),
        _channelsCard(),
        if (_deliveries.isNotEmpty) ...[const SizedBox(height: 16), _deliveriesCard()],
      ],
    );
  }

  Widget _thresholdCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Spike alerts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              subtitle: const Text('Alert when incidents cross a threshold in a time window'),
              value: _thresholdOn,
              onChanged: (v) => setState(() => _thresholdOn = v),
            ),
            if (_thresholdOn) ...[
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'count', label: Text('Fixed count'), icon: Icon(Icons.numbers, size: 16)),
                  ButtonSegment(value: 'anomaly', label: Text('Anomaly'), icon: Icon(Icons.insights, size: 16)),
                ],
                selected: {_thresholdMode},
                onSelectionChanged: (s) => setState(() => _thresholdMode = s.first),
              ),
              const SizedBox(height: 8),
              Text(
                _thresholdMode == 'anomaly'
                    ? 'Learns a baseline and alerts on statistical spikes. The numbers below act as a noise floor (0 = ignore that metric).'
                    : 'Alerts when counts in the window reach the numbers below (0 = off).',
                style: const TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
              const SizedBox(height: 8),
              Text('Window: $_thresholdWindow min', style: const TextStyle(fontWeight: FontWeight.w600)),
              Slider(
                value: _thresholdWindow.toDouble(),
                min: 5,
                max: 120,
                divisions: 23,
                label: '${_thresholdWindow}m',
                onChanged: (v) => setState(() => _thresholdWindow = v.round()),
              ),
              if (_thresholdMode == 'anomaly') ...[
                Text('Sensitivity: ${_thresholdSensitivity.toStringAsFixed(0)}σ above baseline',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Slider(
                  value: _thresholdSensitivity,
                  min: 1,
                  max: 6,
                  divisions: 5,
                  label: '${_thresholdSensitivity.toStringAsFixed(0)}σ',
                  onChanged: (v) => setState(() => _thresholdSensitivity = v),
                ),
              ],
              Row(children: [
                Expanded(
                    child: _countField(_thresholdMode == 'anomaly' ? 'Error floor (0=off)' : 'Errors ≥ (0=off)',
                        _thresholdErrors, (n) => setState(() => _thresholdErrors = n))),
                const SizedBox(width: 12),
                Expanded(
                    child: _countField(_thresholdMode == 'anomaly' ? 'Crash floor (0=off)' : 'Crashes ≥ (0=off)',
                        _thresholdCrashes, (n) => setState(() => _thresholdCrashes = n))),
              ]),
              const SizedBox(height: 8),
              const Text('Uses the channels selected in Routing.', style: TextStyle(fontSize: 12, color: AppTheme.muted)),
              const SizedBox(height: 12),
              const Text('Environments (release builds only)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                'Spike checks only count production / release. Staging and debug builds never trigger spikes.',
                style: TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final env in const ['production', 'release', 'prod'])
                    FilterChip(
                      label: Text(env),
                      selected: _thresholdEnvs.contains(env),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _thresholdEnvs.add(env);
                        } else if (_thresholdEnvs.length > 1) {
                          _thresholdEnvs.remove(env);
                        }
                        if (_thresholdEnvs.isEmpty) _thresholdEnvs = {'production'};
                      }),
                    ),
                ],
              ),
            ],
          ]),
        ),
      );

  Widget _countField(String label, int value, ValueChanged<int> onChanged) => TextFormField(
        initialValue: '$value',
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (s) => onChanged(int.tryParse(s.trim()) ?? 0),
      );

  Widget _digestCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Digest email', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              subtitle: const Text('Scheduled summary of top issues + regressions (email channel)'),
              value: _digestOn,
              onChanged: (v) => setState(() => _digestOn = v),
            ),
            if (_digestOn) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Text('Frequency', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _digestFreq,
                  onChanged: (v) => setState(() => _digestFreq = v ?? 'daily'),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly (Mon)')),
                  ],
                ),
              ]),
              const SizedBox(height: 8),
              Text('Send hour: ${_digestHour.toString().padLeft(2, '0')}:00 UTC', style: const TextStyle(fontWeight: FontWeight.w600)),
              Slider(
                value: _digestHour.toDouble(),
                min: 0,
                max: 23,
                divisions: 23,
                label: '$_digestHour:00 UTC',
                onChanged: (v) => setState(() => _digestHour = v.round()),
              ),
            ],
          ]),
        ),
      );

  Widget _routingCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Per-environment routing', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            const Text(
              'Automatic alerts only send for release builds (production / prod / release). '
              'Staging and development events are never notified — use “Notify team” manually if needed.',
              style: TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            for (final env in const ['production', 'release', 'prod']) _envSection(env),
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

  Widget _envSection(String env) {
    final prefs = _envPrefs[env]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(env, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(prefs.enabled ? 'Alerts on for this environment' : 'Muted — no alerts from $env'),
              value: prefs.enabled,
              onChanged: (v) => setState(() => prefs.enabled = v),
            ),
            if (prefs.enabled) ...[
              const SizedBox(height: 4),
              const Text('Issue types', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in kNotificationCategories)
                    FilterChip(
                      label: Text(_catLabel(c)),
                      selected: prefs.categories.contains(c),
                      onSelected: (on) => setState(() {
                        if (on) {
                          prefs.categories.add(c);
                        } else if (prefs.categories.length > 1) {
                          prefs.categories.remove(c);
                        }
                      }),
                    ),
                ],
              ),
            ],
          ]),
        ),
      ),
    );
  }

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
                'Optional (Resolve/Mute buttons): in your Slack app enable Interactivity, set the Request URL to <your-server>/slack/interactions, and set SLACK_SIGNING_SECRET on the server.',
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
            const Text('Secrets are encrypted at rest. Saved values stay set — leave a field blank to keep it.', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
            if (_platform['slack'] == true) ...[
              const SizedBox(height: 16),
              _channelHeader('Slack', _slackConfigured),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
                value: _slackOn,
                onChanged: (v) => setState(() => _slackOn = v),
              ),
              TextField(
                controller: _slackWebhookCtrl,
                decoration: InputDecoration(
                  labelText: 'Webhook URL',
                  hintText: 'https://hooks.slack.com/services/...',
                  helperText: _slackConfigured ? 'Saved — leave blank to keep current webhook' : null,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: _slackOn ? () => _test('slack') : null, child: const Text('Send test')),
              ),
            ],
            if (_platform['whatsapp'] == true) ...[
              const Divider(),
              _channelHeader('WhatsApp', _waConfigured),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
                value: _waOn,
                onChanged: (v) => setState(() => _waOn = v),
              ),
              TextField(
                controller: _waPhoneCtrl,
                decoration: InputDecoration(
                  labelText: 'Phone (no +)',
                  hintText: '9665xxxxxxxx',
                  helperText: _waConfigured ? 'Saved — leave blank to keep current number' : null,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _waKeyCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'CallMeBot API key',
                  helperText: _waConfigured ? 'Saved — leave blank to keep current key' : null,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: _waOn ? () => _test('whatsapp') : null, child: const Text('Send test')),
              ),
            ],
            if (_platform['email'] == true) ...[
              const Divider(),
              _channelHeader('Email (Gmail)', _emailConfigured),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
                value: _emailOn,
                onChanged: (v) => setState(() => _emailOn = v),
              ),
              TextField(
                controller: _smtpUserCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Gmail address',
                  hintText: _emailUserHint,
                  helperText: _emailUserHint != null ? 'Saved: $_emailUserHint — leave blank to keep' : null,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _smtpPassCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'App password',
                  helperText: _emailConfigured ? 'Saved — leave blank to keep current app password' : null,
                ),
              ),
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

  Widget _channelHeader(String name, bool configured) => Row(
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          if (configured)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle, size: 13, color: AppTheme.success),
                SizedBox(width: 4),
                Text('Saved', style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600, fontSize: 11)),
              ]),
            ),
        ],
      );

  int _stat(String k) => (_summary[k] as int?) ?? 0;

  Widget _statChip(String label, int n, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text('$label $n', style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      );

  Widget _deliveriesCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Recent deliveries', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const Text('Last 24 hours', style: TextStyle(fontSize: 12, color: AppTheme.muted)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _statChip('Sent', _stat('sent'), AppTheme.success),
              _statChip('Failed', _stat('failed'), AppTheme.error),
              _statChip('Deduped', _stat('skipped_dedup'), AppTheme.muted),
              _statChip('Grouped', _stat('batched'), AppTheme.primary),
              _statChip('Rate-limited', _stat('rate_limited'), AppTheme.warning),
            ]),
            const SizedBox(height: 12),
            for (final d in groupNotificationDeliveries(_deliveries).take(15))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  '${d['channel']} · ${d['category']} · ${deliveryStatusLabel('${d['status']}', count: d['count'] as int? ?? 1)}',
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  '${d['latestAt'] ?? d['createdAt'] ?? ''}${d['errorMessage'] != null ? ' — ${d['errorMessage']}' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
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
        'share' => 'Manual share',
        'grouped' => 'Grouped',
        _ => c,
      };
}
