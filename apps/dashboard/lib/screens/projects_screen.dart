import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../widgets/page_header.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _api = ScoutApi();
  final _nameCtrl = TextEditingController();
  List<Map<String, dynamic>> _projects = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;
  String? _newDsn;
  String? _newKey;
  final _expandedCreds = <String>{};
  final _credentials = <String, Map<String, dynamic>>{};
  final _loadingCreds = <String>{};

  bool get _canCreate => AuthService.instance.canCreateProjects;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
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
      final projects = await _api.fetchProjects();
      if (mounted) setState(() {
        _projects = projects;
        _hasData = true;
        _loading = false;

        _refreshing = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e;
        _loading = false;

        _refreshing = false;
      });
    }
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    try {
      final project = await _api.createProject(name);
      _nameCtrl.clear();
      if (mounted) {
        setState(() {
          _newDsn = project['dsn'] as String?;
          _newKey = project['ingestKey'] as String?;
        });
        await _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _loadCredentials(String projectId) async {
    if (_credentials.containsKey(projectId) || _loadingCreds.contains(projectId)) return;
    setState(() => _loadingCreds.add(projectId));
    try {
      final creds = await _api.fetchProjectCredentials(projectId);
      if (mounted) {
        setState(() {
          _credentials[projectId] = creds;
          _loadingCreds.remove(projectId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingCreds.remove(projectId));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _toggleCreds(String projectId) {
    setState(() {
      if (_expandedCreds.contains(projectId)) {
        _expandedCreds.remove(projectId);
      } else {
        _expandedCreds.add(projectId);
        _loadCredentials(projectId);
      }
    });
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) {
    return AsyncScreenBody(
      loading: _loading,
            refreshing: _refreshing,
      error: _error,
      onRetry: _load,
      placeholderLayout: PlaceholderLayout.projects,
      builder: _buildContent,
    );
  }

  Widget _buildContent(BuildContext context) {
    return ListView(
      padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
      children: [
        const PageHeader(
          title: 'Projects',
          subtitle: 'Your apps and DSN credentials. Only projects you belong to are listed here.',
        ),
        if (!_canCreate) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.info_outline, color: AppTheme.muted, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You can view projects shared with you. Ask an admin to grant “Create projects” if you need to add a new app.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.4),
                  ),
                ),
              ]),
            ),
          ),
        ],
        if (_canCreate) ...[
          const SizedBox(height: 28),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('New project', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(hintText: 'e.g. My Flutter App'),
                      onSubmitted: (_) => _create(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Create')),
                ]),
              ]),
            ),
          ),
        ],
        if (_newKey != null) ...[
          const SizedBox(height: 16),
          Card(
            color: AppTheme.primarySoft,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.key, color: AppTheme.primary, size: 20),
                  SizedBox(width: 8),
                  Text('Save these credentials — also available anytime below', style: TextStyle(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 16),
                _credentialRow('Ingest key', _newKey!, () => _copy(_newKey!, 'Ingest key')),
                if (_newDsn != null) ...[
                  const SizedBox(height: 12),
                  _credentialRow('DSN', _newDsn!, () => _copy(_newDsn!, 'DSN')),
                ],
              ]),
            ),
          ),
        ],
        const SizedBox(height: 28),
        Text('${_projects.length} project${_projects.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.muted)),
        const SizedBox(height: 12),
        if (_projects.isEmpty)
          const EmptyState(
            icon: Icons.folder_open_outlined,
            title: 'No projects yet',
            subtitle: 'Create a project or ask an admin to add you to one.',
          )
        else
          ..._projects.map((p) {
            final id = p['id'] as String;
            final events = p['eventCount'] as int? ?? 0;
            final issues = p['issueCount'] as int? ?? 0;
            final expanded = _expandedCreds.contains(id);
            final creds = _credentials[id];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                InkWell(
                  onTap: () => context.go('/p/$id'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.apps, color: AppTheme.primary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p['name'] as String? ?? id, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text('$events events · $issues issues', style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                        ]),
                      ),
                      TextButton.icon(
                        onPressed: () => _toggleCreds(id),
                        icon: Icon(expanded ? Icons.expand_less : Icons.key_outlined, size: 18),
                        label: Text(expanded ? 'Hide DSN' : 'DSN'),
                      ),
                      const Icon(Icons.chevron_right, color: AppTheme.muted),
                    ]),
                  ),
                ),
                if (expanded) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _loadingCreds.contains(id)
                        ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
                        : creds == null
                            ? const Text('Could not load credentials', style: TextStyle(color: AppTheme.muted))
                            : creds['available'] == false
                                ? Text(creds['message'] as String? ?? 'Credentials unavailable', style: const TextStyle(color: AppTheme.muted, fontSize: 13))
                                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    _credentialRow('Ingest key', creds['ingestKey'] as String, () => _copy(creds['ingestKey'] as String, 'Ingest key')),
                                    const SizedBox(height: 10),
                                    _credentialRow('DSN', creds['dsn'] as String, () => _copy(creds['dsn'] as String, 'DSN')),
                                  ]),
                  ),
                ],
              ]),
            );
          }),
      ],
    );
  }

  Widget _credentialRow(String label, String value, VoidCallback onCopy) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: SelectableText(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
            IconButton(onPressed: onCopy, icon: const Icon(Icons.copy, size: 18)),
          ]),
        ],
      );
}
