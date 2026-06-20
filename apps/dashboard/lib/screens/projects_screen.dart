import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
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
  String? _error;
  String? _newDsn;
  String? _newKey;

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
      _loading = true;
      _error = null;
    });
    try {
      final projects = await _api.fetchProjects();
      if (mounted) setState(() {
        _projects = projects;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
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

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorPanel(message: _error!, onRetry: _load);

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const PageHeader(
          title: 'Projects',
          subtitle: 'Each project has its own DSN and ingest key — like a Firebase app or Sentry project.',
        ),
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
                  Text('Save these credentials — shown once', style: TextStyle(fontWeight: FontWeight.w700)),
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
            subtitle: 'Create a project above, then wire the ingest key into your app SDK.',
          )
        else
          ..._projects.map((p) {
            final id = p['id'] as String;
            final events = p['eventCount'] as int? ?? 0;
            final issues = p['issueCount'] as int? ?? 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
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
                    const Icon(Icons.chevron_right, color: AppTheme.muted),
                  ]),
                ),
              ),
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
