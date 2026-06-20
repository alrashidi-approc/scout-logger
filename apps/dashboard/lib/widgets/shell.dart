import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key, required this.projectId, required this.child});

  final String? projectId;
  final Widget child;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  final _api = ScoutApi();
  String? _projectName;

  @override
  void initState() {
    super.initState();
    _loadProject();
  }

  @override
  void didUpdateWidget(covariant DashboardShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) _loadProject();
  }

  Future<void> _loadProject() async {
    final id = widget.projectId;
    if (id == null) {
      if (mounted) setState(() => _projectName = null);
      return;
    }
    try {
      final projects = await _api.fetchProjects();
      String? name;
      for (final p in projects) {
        if (p['id'] == id) {
          name = p['name'] as String?;
          break;
        }
      }
      if (mounted) setState(() => _projectName = name ?? id);
    } catch (_) {
      if (mounted) setState(() => _projectName = id);
    }
  }

  int _selectedIndex(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    if (widget.projectId == null) return 0;
    if (path.contains('/analytics')) return 1;
    if (path.contains('/issues')) return 2;
    if (path.contains('/events')) return 3;
    if (path.contains('/geo')) return 4;
    return 0;
  }

  void _onNav(int i, BuildContext context) {
    final id = widget.projectId;
    switch (i) {
      case 0:
        context.go(id == null ? '/projects' : '/p/$id');
      case 1:
        if (id != null) context.go('/p/$id/analytics');
      case 2:
        if (id != null) context.go('/p/$id/issues');
      case 3:
        if (id != null) context.go('/p/$id/events');
      case 4:
        if (id != null) context.go('/p/$id/geo');
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final selected = _selectedIndex(context);
    final destinations = widget.projectId == null
        ? const [NavigationRailDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: Text('Projects'))]
        : const [
            NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Overview')),
            NavigationRailDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: Text('Analytics')),
            NavigationRailDestination(icon: Icon(Icons.bug_report_outlined), selectedIcon: Icon(Icons.bug_report), label: Text('Issues')),
            NavigationRailDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: Text('Events')),
            NavigationRailDestination(icon: Icon(Icons.public_outlined), selectedIcon: Icon(Icons.public), label: Text('Geography')),
          ];

    final rail = NavigationRail(
      selectedIndex: selected.clamp(0, destinations.length - 1),
      onDestinationSelected: (i) => _onNav(i, context),
      extended: wide && widget.projectId != null,
      labelType: wide ? null : NavigationRailLabelType.selected,
      leading: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        child: Column(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.radar, color: Colors.white, size: 22),
          ),
          if (wide) ...[
            const SizedBox(height: 8),
            const Text('Scout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ]),
      ),
      destinations: destinations,
    );

    return Scaffold(
      body: Row(children: [
        Material(color: AppTheme.sidebar, child: SizedBox(width: wide && widget.projectId != null ? 220 : 72, child: rail)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Material(
              color: Colors.white,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
                child: Row(children: [
                  if (widget.projectId != null)
                    TextButton.icon(
                      onPressed: () => context.go('/projects'),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Projects'),
                    ),
                  if (_projectName != null) ...[
                    const Text(' / ', style: TextStyle(color: AppTheme.muted)),
                    Text(_projectName!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ],
                  const Spacer(),
                  if (widget.projectId != null)
                    OutlinedButton.icon(
                      onPressed: () => context.go('/projects'),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Switch project'),
                    ),
                ]),
              ),
            ),
            Expanded(child: widget.child),
          ]),
        ),
      ]),
    );
  }
}
