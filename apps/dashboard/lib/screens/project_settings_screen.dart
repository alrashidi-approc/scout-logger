import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scout_models/scout_models.dart';

import '../services/dashboard_log_service.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_range.dart';
import '../utils/project_roles.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../widgets/page_header.dart';
import '../widgets/sdk_health_card.dart';

class ProjectSettingsScreen extends StatefulWidget {
  const ProjectSettingsScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<ProjectSettingsScreen> createState() => _ProjectSettingsScreenState();
}

class _ProjectSettingsScreenState extends State<ProjectSettingsScreen> {
  final _api = ScoutApi();
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  bool _saving = false;
  bool _deleting = false;
  bool _purging = false;
  Object? _error;
  String? _role;
  int _configVersion = 1;
  Set<String> _levels = ProjectSdkConfig.defaultEnabledLevels.toSet();
  bool _flutterHooks = true;
  bool _trackNavigation = true;
  bool _networkBodies = true;
  int _slowThresholdMs = 3000;
  final _ignoreCodesCtrl = TextEditingController();
  final _memberEmailCtrl = TextEditingController();
  final _memberPasswordCtrl = TextEditingController();
  Set<int> _ignoreCodes = {};
  String _networkLogScope = ProjectSdkConfig.defaultNetworkLogScope;
  List<Map<String, dynamic>> _members = [];
  String _newMemberRole = assignableProjectRoles.first;
  bool _addingMember = false;
  Map<String, dynamic> _sdkHealth = {};

  @override
  void dispose() {
    _ignoreCodesCtrl.dispose();
    _memberEmailCtrl.dispose();
    _memberPasswordCtrl.dispose();
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
        _api.fetchProjectSettings(widget.projectId),
        _api.fetchProjects(),
        _api.fetchSdkHealth(widget.projectId),
      ]);
      final settings = results[0] as Map<String, dynamic>;
      final health = results[2] as Map<String, dynamic>;
      final projects = results[1] as List<Map<String, dynamic>>;
      String? role;
      for (final p in projects) {
        if (p['id'] == widget.projectId) {
          role = p['role'] as String?;
          break;
        }
      }
      if (AuthService.instance.isAdmin) role = 'owner';
      final remote = ProjectRemoteConfig(
        configVersion: settings['configVersion'] as int? ?? 1,
        updatedAt: settings['updatedAt'] as String? ?? '',
        sdk: ProjectSdkConfig.fromJson(settings['sdk'] is Map ? Map<String, dynamic>.from(settings['sdk'] as Map) : null),
      );
      final sdk = remote.sdk.resolved();
      List<Map<String, dynamic>> members = [];
      final canManage = role == 'owner' || AuthService.instance.isAdmin;
      if (canManage) {
        members = await _api.fetchProjectMembers(widget.projectId);
      }
      if (mounted) {
        setState(() {
          _role = role;
          _members = members;
          _configVersion = remote.configVersion;
          _levels = sdk.enabledLevels!.toSet();
          _flutterHooks = sdk.enableFlutterHooks!;
          _trackNavigation = sdk.trackNavigation!;
          _networkBodies = sdk.networkCaptureBodies!;
          _slowThresholdMs = sdk.networkSlowThresholdMs!;
          _ignoreCodes = sdk.networkIgnoreStatusCodes!.toSet();
          _ignoreCodesCtrl.text = _ignoreCodes.join(', ');
          _networkLogScope = sdk.networkLogScope!;
          _sdkHealth = health;
          _hasData = true;
          _loading = false;

          _refreshing = false;
        });
      }
    } catch (e) {
      DashboardLogService.record(projectId: widget.projectId, message: formatLoadError(e));
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;

          _refreshing = false;
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
          'networkLogScope': normalizeNetworkLogScope(_networkLogScope),
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

  bool get _canDelete => _role == 'owner' || AuthService.instance.isAdmin;

  bool get _canManageMembers => _role == 'owner' || AuthService.instance.isAdmin;

  Future<void> _addMember() async {
    final email = _memberEmailCtrl.text.trim();
    final password = _memberPasswordCtrl.text;
    if (email.isEmpty) return;
    setState(() => _addingMember = true);
    try {
      final member = await _api.addProjectMember(
        widget.projectId,
        email: email,
        password: password,
        role: _newMemberRole,
      );
      if (mounted) {
        setState(() {
          _members = [..._members, member];
          _memberEmailCtrl.clear();
          _memberPasswordCtrl.clear();
          _addingMember = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${member['email']}')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _addingMember = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatLoadError(e))));
      }
    }
  }

  Future<void> _updateMemberRole(String userId, String role) async {
    try {
      final member = await _api.updateProjectMemberRole(widget.projectId, userId, role);
      if (!mounted) return;
      setState(() {
        final i = _members.indexWhere((m) => m['userId'] == userId);
        if (i >= 0) _members[i] = member;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatLoadError(e))));
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove team member?'),
        content: Text('${member['email']} will lose access to this project.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.removeProjectMember(widget.projectId, member['userId'] as String);
      if (mounted) {
        setState(() => _members.removeWhere((m) => m['userId'] == member['userId']));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatLoadError(e))));
    }
  }

  Future<void> _confirmPurgeData() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
      helpText: 'Delete data in range (UTC)',
    );
    if (range == null || !mounted) return;
    final from = DateTime(range.start.year, range.start.month, range.start.day);
    final to = DateTime(range.end.year, range.end.month, range.end.day);
    final err = PeriodFilter.rangeError(from, to);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final period = PeriodFilter.range(from, to);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete data in range?'),
        content: Text(
          'Permanently deletes all events, sessions, issues, and stats for ${period.label()} (UTC). '
          'Data outside this range is kept. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete data'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _purging = true);
    try {
      final res = await _api.purgeProjectData(widget.projectId, period: period);
      final deleted = res['deleted'] is Map ? Map<String, dynamic>.from(res['deleted'] as Map) : <String, dynamic>{};
      final events = deleted['deletedEvents'] ?? 0;
      if (mounted) {
        setState(() => _purging = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $events events and related data for ${period.label()}')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _purging = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatLoadError(e))));
      }
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project?'),
        content: const Text(
          'This permanently deletes the project, all events, issues, and sessions. '
          'Mobile apps using this DSN will stop reporting. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _api.deleteProject(widget.projectId);
      if (mounted) context.go('/projects');
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          title: 'Project settings',
          subtitle: 'SDK remote config (v$_configVersion) and team access',
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
        if (_canManageMembers) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Team access', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 6),
                  const Text(
                    'Invite dashboard users with email and password. Existing accounts are linked without changing their password.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _memberEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email', hintText: 'qa@company.com'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _memberPasswordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      hintText: 'Required for new users (min 8 characters)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _newMemberRole,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: [
                      for (final role in assignableProjectRoles)
                        DropdownMenuItem(value: role, child: Text(projectRoleLabel(role))),
                    ],
                    onChanged: _addingMember ? null : (v) => setState(() => _newMemberRole = v ?? _newMemberRole),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: _addingMember ? null : _addMember,
                      icon: _addingMember
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.person_add_outlined, size: 18),
                      label: const Text('Add member'),
                    ),
                  ),
                  if (_members.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    for (final member in _members) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primarySoft,
                          child: Text(
                            ((member['email'] as String?) ?? '?')[0].toUpperCase(),
                            style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700),
                          ),
                        ),
                        title: Text(member['email'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(projectRoleLabel(member['role'] as String? ?? '')),
                        trailing: member['role'] == 'owner'
                            ? const Chip(label: Text('Owner'))
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  DropdownButton<String>(
                                    value: assignableProjectRoles.contains(member['role']) ? member['role'] as String : assignableProjectRoles.first,
                                    underline: const SizedBox.shrink(),
                                    items: [
                                      for (final role in assignableProjectRoles)
                                        DropdownMenuItem(value: role, child: Text(projectRoleLabel(role))),
                                    ],
                                    onChanged: (role) {
                                      if (role != null) _updateMemberRole(member['userId'] as String, role);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: AppTheme.error),
                                    tooltip: 'Remove',
                                    onPressed: () => _removeMember(member),
                                  ),
                                ],
                              ),
                      ),
                      if (member != _members.last) const Divider(height: 1),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SdkHealthCard(health: _sdkHealth),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('SDK — Log levels', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
              const Text('SDK — Capture', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
              const Text('Network log scope', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                'Which HTTP calls the SDK uploads. Errors are always 4xx/5xx and Dio failures.',
                style: TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('All')),
                  ButtonSegment(value: 'errorsOnly', label: Text('Errors')),
                  ButtonSegment(value: 'slowOnly', label: Text('Slow')),
                ],
                selected: {_networkLogScope},
                onSelectionChanged: (v) => setState(() => _networkLogScope = v.first),
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
        if (_canDelete) ...[
          const SizedBox(height: 16),
          Card(
            color: AppTheme.error.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Danger zone', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.error)),
                const SizedBox(height: 8),
                const Text(
                  'Delete events in a date range to start over, or remove the entire project.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _purging ? null : _confirmPurgeData,
                  icon: _purging
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.date_range, color: AppTheme.error),
                  label: const Text('Delete data in date range…', style: TextStyle(color: AppTheme.error)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.error)),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _deleting ? null : _confirmDelete,
                  icon: _deleting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.delete_outline, color: AppTheme.error),
                  label: const Text('Delete project', style: TextStyle(color: AppTheme.error)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.error)),
                ),
              ]),
            ),
          ),
        ],
      ],
    );
  }
}
