import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/dashboard_log_service.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/date_range.dart';
import '../utils/responsive.dart';
import '../widgets/filter_bar.dart';
import '../utils/screen_load.dart';
import '../widgets/page_header.dart';
import '../widgets/period_picker.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, required this.projectId, this.initialPeriod = const PeriodFilter.days(30)});

  final String projectId;
  final PeriodFilter initialPeriod;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _api = ScoutApi();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;
  late PeriodFilter _period = widget.initialPeriod;

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
      final users = await _api.fetchUsers(widget.projectId, period: _period);
      if (mounted) setState(() {
        _users = users;
        _hasData = true;
        _loading = false;

        _refreshing = false;
      });
    } catch (e) {
      DashboardLogService.record(projectId: widget.projectId, message: formatLoadError(e));
      if (mounted) setState(() {
        _error = e;
        _loading = false;

        _refreshing = false;
      });
    }
  }

  void _setPeriod(PeriodFilter p) {
    _period = p;
    context.go(Uri(path: '/p/${widget.projectId}/users', queryParameters: p.toQuery()).toString());
    _load();
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: _setPeriod);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: pageInsets(context, top: pagePad(context)),
        child: PageHeader(
          title: 'Users',
          subtitle: '${_users.length} logged-in users',
          period: _period,
          onPeriodTap: _openPeriodPicker,
          actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
        ),
      ),
      Padding(padding: pageInsets(context, top: 12), child: FilterBar(period: _period, onPeriodChanged: _setPeriod)),
      Expanded(
        child: AsyncScreenBody(
          loading: _loading,
            refreshing: _refreshing,
          error: _error,
          onRetry: _load,
          placeholderLayout: PlaceholderLayout.list,
          empty: !_loading && _users.isEmpty
              ? const EmptyState(icon: Icons.people_outline, title: 'No logged-in users yet', subtitle: 'Only identified users appear here. Guest traffic stays in Events and Sessions.')
              : null,
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              key: PageStorageKey('users-${widget.projectId}'),
              padding: pageInsets(context, top: 12, bottom: pagePad(context)),
              itemCount: _users.length,
              itemBuilder: (_, i) {
                final u = _users[i];
                final last = DateTime.tryParse(u['lastSeenAt'] as String? ?? '');
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
                  child: ListTile(
                    onTap: () => context.push('/p/${widget.projectId}/users/${Uri.encodeComponent(u['userId'] as String)}'),
                    leading: CircleAvatar(backgroundColor: AppTheme.primary.withValues(alpha: 0.15), child: const Icon(Icons.person, color: AppTheme.primary, size: 18)),
                    title: Text('${u['userId']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    subtitle: Text(
                      '${u['eventCount']} events · ${u['errorCount']} errors · ${u['sessionCount']} sessions',
                      style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                    ),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(last != null ? DateFormat.MMMd().format(last.toLocal()) : '—', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                      const Icon(Icons.chevron_right, size: 18, color: AppTheme.muted),
                    ]),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ]);
  }
}
