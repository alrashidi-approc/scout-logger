import 'package:flutter/material.dart';
import 'package:scout_models/scout_models.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';

class ProjectSettingsScreen extends StatefulWidget {
  const ProjectSettingsScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<ProjectSettingsScreen> createState() => _ProjectSettingsScreenState();
}

class _ProjectSettingsScreenState extends State<ProjectSettingsScreen> {
  final _api = ScoutApi();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _configVersion = 1;
  Set<String> _levels = ProjectSdkConfig.defaultEnabledLevels.toSet();
  bool _flutterHooks = true;
  bool _trackNavigation = true;
  bool _networkBodies = true;
  int _slowThresholdMs = 3000;
  final _ignoreCodesCtrl = TextEditingController();
  Set<int> _ignoreCodes = {};

  @override
  void dispose() {
    _ignoreCodesCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await _api.fetchProjectSettings(widget.projectId);
      final remote = ProjectRemoteConfig(
        configVersion: settings['configVersion'] as int? ?? 1,
        updatedAt: settings['updatedAt'] as String? ?? '',
        sdk: ProjectSdkConfig.fromJson(settings['sdk'] is Map ? Map<String, dynamic>.from(settings['sdk'] as Map) : null),
      );
      final sdk = remote.sdk.resolved();
      if (mounted) {
        setState(() {
          _configVersion = remote.configVersion;
          _levels = sdk.enabledLevels!.toSet();
          _flutterHooks = sdk.enableFlutterHooks!;
          _trackNavigation = sdk.trackNavigation!;
          _networkBodies = sdk.networkCaptureBodies!;
          _slowThresholdMs = sdk.networkSlowThresholdMs!;
          _ignoreCodes = sdk.networkIgnoreStatusCodes!.toSet();
          _ignoreCodesCtrl.text = _ignoreCodes.join(', ');
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final settings = await _api.updateProjectSettings(widget.projectId, {
        'sdk': {
          'enabledLevels': normalizeEnabledLevels(_levels.toList()),
          'enableFlutterHooks': _flutterHooks,
          'trackNavigation': _trackNavigation,
          'networkCaptureBodies': _networkBodies,
          'networkSlowThresholdMs': _slowThresholdMs,
          'networkIgnoreStatusCodes': normalizeStatusCodes(_ignoreCodes.toList()),
        },
      });
      if (mounted) {
        setState(() {
          _configVersion = settings['configVersion'] as int? ?? _configVersion + 1;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved — apps pick this up on next launch or resume')),
        );
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
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorPanel(message: _error!, onRetry: _load);

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        PageHeader(
          title: 'SDK settings',
          subtitle: 'Remote config for mobile clients (v$_configVersion). Changes apply on app launch or resume.',
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
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Log levels', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              const Text('Events below unchecked levels are dropped in the app before upload.', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final level in ProjectSdkConfig.defaultEnabledLevels)
                    FilterChip(
                      label: Text(level.toUpperCase()),
                      selected: _levels.contains(level),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _levels.add(level);
                        } else if (_levels.length > 1) {
                          _levels.remove(level);
                        }
                      }),
                    ),
                ],
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Capture', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto error & crash hooks'),
                subtitle: const Text('FlutterError.onError and platform dispatcher crashes'),
                value: _flutterHooks,
                onChanged: (v) => setState(() => _flutterHooks = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Navigation tracking'),
                subtitle: const Text('Screen trail and route breadcrumbs'),
                value: _trackNavigation,
                onChanged: (v) => setState(() => _trackNavigation = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Network response bodies'),
                subtitle: const Text('Include request/response bodies in network events'),
                value: _networkBodies,
                onChanged: (v) => setState(() => _networkBodies = v),
              ),
              const SizedBox(height: 8),
              Text('Slow request threshold (${_slowThresholdMs}ms)', style: const TextStyle(fontWeight: FontWeight.w600)),
              Slider(
                value: _slowThresholdMs.toDouble(),
                min: 500,
                max: 10000,
                divisions: 19,
                label: '${_slowThresholdMs}ms',
                onChanged: (v) => setState(() => _slowThresholdMs = v.round()),
              ),
              const SizedBox(height: 16),
              const Text('Ignore HTTP status codes', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                'Matching responses are not logged (e.g. 401 on auth refresh). Comma-separated.',
                style: TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ignoreCodesCtrl,
                decoration: const InputDecoration(hintText: '401, 403, 404'),
                keyboardType: TextInputType.number,
                onChanged: (v) => setState(() {
                  _ignoreCodes = normalizeStatusCodes(v.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList()).toSet();
                }),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final code in const [401, 403, 404, 422, 429])
                    ActionChip(
                      label: Text('$code'),
                      onPressed: () => setState(() {
                        _ignoreCodes.add(code);
                        _ignoreCodesCtrl.text = normalizeStatusCodes(_ignoreCodes.toList()).join(', ');
                      }),
                    ),
                ],
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
