import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/dashboard_scope.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_range.dart';
import '../utils/responsive.dart';
import 'dashboard_footer.dart';
import 'scout_logo.dart';

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
    (Icons.people_outline, Icons.people, 'Logged-in users'),
    (Icons.play_circle_outline, Icons.play_circle, 'Sessions'),
    (Icons.insights_outlined, Icons.insights, 'Analytics'),
    (Icons.bug_report_outlined, Icons.bug_report, 'Issues'),
    (Icons.list_alt_outlined, Icons.list_alt, 'Events'),
    (Icons.public_outlined, Icons.public, 'Geography'),
    (Icons.terminal_outlined, Icons.terminal, 'UI errors'),
    (Icons.tune_outlined, Icons.tune, 'Settings'),
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
    if (path.contains('/logs')) return 7;
    if (path.contains('/settings')) return 8;
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
      7 => '/p/$id/logs',
      8 => '/p/$id/settings',
      _ => '/projects',
    };
    if (i > 0 && id == null) return;
    context.go(Uri(path: path, queryParameters: periodQ).toString());
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  Widget _sidebarNav(BuildContext context, {required bool extended, required int selected}) {
    if (widget.projectId == null) {
      return _NavTile(
        icon: Icons.folder_outlined,
        activeIcon: Icons.folder,
        label: 'Projects',
        selected: true,
        extended: extended,
        onTap: () => _onNav(0, context),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(extended ? 16 : 12, 0, extended ? 16 : 12, 8),
          child: Text(
            'MONITORING',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.muted.withValues(alpha: 0.85),
              letterSpacing: 1.1,
            ),
          ),
        ),
        for (var i = 0; i < _navItems.length; i++)
          _NavTile(
            icon: _navItems[i].$1,
            activeIcon: _navItems[i].$2,
            label: _navItems[i].$3,
            selected: selected == i,
            extended: extended,
            onTap: () => _onNav(i, context),
          ),
      ],
    );
  }

  Widget _sidebarHeader({required bool extended, VoidCallback? onLogoTap}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(extended ? 16 : 12, 20, extended ? 16 : 12, 16),
      child: ScoutLogo(
        compact: !extended,
        showTagline: extended,
        iconSize: extended ? 38 : 36,
        onTap: onLogoTap ?? () => context.go(widget.projectId == null ? '/projects' : '/p/${widget.projectId}'),
      ),
    );
  }

  Widget _sidebarFooter(BuildContext context, {required bool extended}) {
    if (widget.projectId == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: extended
          ? OutlinedButton.icon(
              onPressed: () => context.go('/projects'),
              icon: const Icon(Icons.swap_horiz, size: 16),
              label: const Text('Switch project'),
            )
          : IconButton(
              onPressed: () => context.go('/projects'),
              icon: const Icon(Icons.swap_horiz, color: AppTheme.muted),
              tooltip: 'Switch project',
            ),
    );
  }

  Widget _mainColumn(BuildContext context, {required Widget topBar, required Widget content, required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        topBar,
        Expanded(child: content),
        DashboardFooter(compact: compact),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    DashboardScope.projectId = widget.projectId;
    DashboardScope.route = GoRouterState.of(context).uri.path;

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
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sidebarHeader(extended: true),
                      if (_projectName != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text(
                            _projectName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.text),
                          ),
                        ),
                      Expanded(child: SingleChildScrollView(child: _sidebarNav(context, extended: true, selected: selected))),
                      _sidebarFooter(context, extended: true),
                    ],
                  ),
                ),
              ),
        body: _mainColumn(context, topBar: topBar, content: content, compact: compact),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Row(
        children: [
          Container(
            width: extended ? 232 : 76,
            decoration: BoxDecoration(
              color: AppTheme.sidebar,
              border: const Border(right: BorderSide(color: AppTheme.border)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(2, 0))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sidebarHeader(extended: extended),
                if (extended && _projectName != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.panelElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_outlined, size: 14, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _projectName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.text),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(child: SingleChildScrollView(child: _sidebarNav(context, extended: extended, selected: selected))),
                _sidebarFooter(context, extended: extended),
              ],
            ),
          ),
          Expanded(child: _mainColumn(context, topBar: topBar, content: content, compact: compact)),
        ],
      ),
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
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20, vertical: compact ? 10 : 12),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          border: const Border(bottom: BorderSide(color: AppTheme.border)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            if (drawerMode && projectName != null)
              IconButton(onPressed: onMenu, icon: const Icon(Icons.menu, size: 22), tooltip: 'Menu')
            else if (drawerMode)
              const Padding(padding: EdgeInsets.only(right: 4), child: ScoutLogo(compact: true, iconSize: 32)),
            if (projectName != null) ...[
              if (!drawerMode)
                TextButton.icon(
                  onPressed: onProjects,
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: Text(compact ? 'Back' : 'Projects'),
                ),
              if (!compact) const Text(' / ', style: TextStyle(color: AppTheme.muted)),
              Expanded(
                child: Text(
                  projectName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 13 : 15, color: AppTheme.text),
                ),
              ),
            ] else ...[
              if (!drawerMode) ...[
                ScoutLogo(compact: compact, iconSize: 32, onTap: () => context.go('/projects')),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  compact ? 'Projects' : 'Your projects',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 14 : 16, color: AppTheme.text),
                ),
              ),
            ],
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
                } else                 if (v == 'admin') {
                  context.go('/admin/users');
                } else if (v == 'notifications') {
                  context.go('/admin/notifications');
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(enabled: false, child: Text(AuthService.instance.email, style: const TextStyle(fontSize: 12, color: AppTheme.muted))),
                if (AuthService.instance.isAdmin) const PopupMenuItem(value: 'admin', child: Text('Team & permissions')),
                if (AuthService.instance.isPlatformOwner)
                  const PopupMenuItem(value: 'notifications', child: Text('Notification channels')),
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
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.success.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle)),
                  if (!compact) ...[
                    const SizedBox(width: 8),
                    const Text('Live', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.success)),
                  ],
                ],
              ),
            ),
          ],
        ),
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
          margin: EdgeInsets.symmetric(horizontal: extended ? 10 : 8, vertical: 2),
          padding: EdgeInsets.symmetric(horizontal: extended ? 12 : 0, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected ? Border.all(color: AppTheme.primary.withValues(alpha: 0.2)) : null,
          ),
          child: Row(
            mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(selected ? activeIcon : icon, color: accent, size: 20),
              if (extended) ...[
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: TextStyle(color: accent, fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w500))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
