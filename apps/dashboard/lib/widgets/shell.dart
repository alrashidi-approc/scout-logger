import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_range.dart';
import '../utils/responsive.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key, required this.projectId, required this.child});

  final String? projectId;
  final Widget child;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  final _api = ScoutApi();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _pageBucket = PageStorageBucket();
  String? _projectName;

  static const _navItems = [
    (Icons.dashboard_outlined, Icons.dashboard, 'Overview'),
    (Icons.people_outline, Icons.people, 'Users'),
    (Icons.play_circle_outline, Icons.play_circle, 'Sessions'),
    (Icons.insights_outlined, Icons.insights, 'Analytics'),
    (Icons.bug_report_outlined, Icons.bug_report, 'Issues'),
    (Icons.list_alt_outlined, Icons.list_alt, 'Events'),
    (Icons.public_outlined, Icons.public, 'Geography'),
  ];

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
    if (path.contains('/stats')) return 0;
    if (path.contains('/users')) return 1;
    if (path.contains('/sessions')) return 2;
    if (path.contains('/analytics')) return 3;
    if (path.contains('/issues')) return 4;
    if (path.contains('/events')) return 5;
    if (path.contains('/geo')) return 6;
    return 0;
  }

  void _onNav(int i, BuildContext context) {
    final id = widget.projectId;
    final periodQ = PeriodFilter.queryFromUri(GoRouterState.of(context).uri.queryParameters);
    final path = switch (i) {
      0 => id == null ? '/projects' : '/p/$id',
      1 => '/p/$id/users',
      2 => '/p/$id/sessions',
      3 => '/p/$id/analytics',
      4 => '/p/$id/issues',
      5 => '/p/$id/events',
      6 => '/p/$id/geo',
      _ => '/projects',
    };
    if (i > 0 && id == null) return;
    context.go(Uri(path: path, queryParameters: periodQ).toString());
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final drawerMode = useDrawerNav(context);
    final wide = !drawerMode && MediaQuery.sizeOf(context).width >= Breakpoints.shellDrawer;
    final extended = wide && widget.projectId != null;
    final selected = _selectedIndex(context);
    final compact = isMobile(context);

    final topBar = _TopBar(
      compact: compact,
      drawerMode: drawerMode,
      projectName: _projectName,
      onMenu: () => _scaffoldKey.currentState?.openDrawer(),
      onProjects: () => context.go('/projects'),
    );

    final content = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.bg, Color(0xFFF1F5F9)],
        ),
      ),
      child: PageStorage(bucket: _pageBucket, child: widget.child),
    );

    if (drawerMode) {
      return Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppTheme.bg,
        drawer: widget.projectId == null
            ? null
            : Drawer(
                backgroundColor: AppTheme.sidebar,
                child: SafeArea(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text('Scout', style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.w800, fontSize: 18)),
                    ),
                    for (var i = 0; i < _navItems.length; i++)
                      _NavTile(
                        icon: _navItems[i].$1,
                        activeIcon: _navItems[i].$2,
                        label: _navItems[i].$3,
                        selected: selected == i,
                        extended: true,
                        onTap: () => _onNav(i, context),
                      ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton.icon(onPressed: () => context.go('/projects'), icon: const Icon(Icons.swap_horiz, size: 16), label: const Text('Switch project')),
                    ),
                  ]),
                ),
              ),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [topBar, Expanded(child: content)]),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Row(children: [
        Container(
          width: extended ? 220 : 72,
          decoration: BoxDecoration(
            color: AppTheme.sidebar,
            border: Border(right: BorderSide(color: AppTheme.border)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(1, 0)),
            ],
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.accentPurple]),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 12)],
                  ),
                  child: const Icon(Icons.radar, color: Colors.white, size: 22),
                ),
                if (extended) ...[
                  const SizedBox(width: 10),
                  const Text('Scout', style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.w800, fontSize: 16)),
                ],
              ]),
            ),
            if (widget.projectId == null)
              _NavTile(icon: Icons.folder_outlined, activeIcon: Icons.folder, label: 'Projects', selected: true, extended: extended, onTap: () => _onNav(0, context))
            else
              for (var i = 0; i < _navItems.length; i++)
                _NavTile(
                  icon: _navItems[i].$1,
                  activeIcon: _navItems[i].$2,
                  label: _navItems[i].$3,
                  selected: selected == i,
                  extended: extended,
                  onTap: () => _onNav(i, context),
                ),
            const Spacer(),
            if (widget.projectId != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: extended
                    ? OutlinedButton.icon(onPressed: () => context.go('/projects'), icon: const Icon(Icons.swap_horiz, size: 16), label: const Text('Switch'))
                    : IconButton(onPressed: () => context.go('/projects'), icon: const Icon(Icons.swap_horiz, color: AppTheme.muted), tooltip: 'Switch project'),
              ),
          ]),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [topBar, Expanded(child: content)])),
      ]),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.compact, required this.drawerMode, required this.projectName, required this.onMenu, required this.onProjects});

  final bool compact;
  final bool drawerMode;
  final String? projectName;
  final VoidCallback onMenu;
  final VoidCallback onProjects;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.panel,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20, vertical: compact ? 10 : 12),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(children: [
          if (drawerMode && projectName != null)
            IconButton(onPressed: onMenu, icon: const Icon(Icons.menu, size: 22), tooltip: 'Menu')
          else if (projectName != null)
            TextButton.icon(onPressed: onProjects, icon: const Icon(Icons.arrow_back, size: 16), label: Text(compact ? 'Back' : 'Projects')),
          if (projectName != null) ...[
            if (!compact) const Text(' / ', style: TextStyle(color: AppTheme.muted)),
            Expanded(
              child: Text(
                projectName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 13 : 14, color: AppTheme.text),
              ),
            ),
          ]           else
            const Spacer(),
          if (AuthService.instance.isAdmin && projectName == null)
            TextButton.icon(
              onPressed: () => context.go('/admin/users'),
              icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
              label: Text(compact ? '' : 'Team'),
            ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            onSelected: (v) async {
              if (v == 'logout') {
                await AuthService.instance.logout();
                if (context.mounted) context.go('/login');
              } else if (v == 'admin') {
                context.go('/admin/users');
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(AuthService.instance.email, style: const TextStyle(fontSize: 12, color: AppTheme.muted))),
              if (AuthService.instance.isAdmin) const PopupMenuItem(value: 'admin', child: Text('Team & permissions')),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: CircleAvatar(
                radius: compact ? 14 : 16,
                backgroundColor: AppTheme.primarySoft,
                child: Text(
                  AuthService.instance.email.isNotEmpty ? AuthService.instance.email[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 4 : 6),
            decoration: BoxDecoration(color: AppTheme.panelElevated, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.border)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle)),
              if (!compact) ...[const SizedBox(width: 8), const Text('Live', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.muted))],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.activeIcon, required this.label, required this.selected, required this.extended, required this.onTap});

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? AppTheme.primary : AppTheme.muted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: EdgeInsets.symmetric(horizontal: extended ? 12 : 0, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected ? Border.all(color: AppTheme.primary.withValues(alpha: 0.25)) : null,
          ),
          child: Row(mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
            if (selected && extended)
              Container(width: 3, height: 20, margin: const EdgeInsets.only(right: 10), decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(2)))
            else if (extended)
              const SizedBox(width: 13),
            Icon(selected ? activeIcon : icon, color: accent, size: 20),
            if (extended) ...[
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: TextStyle(color: accent, fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w500))),
            ],
          ]),
        ),
      ),
    );
  }
}
