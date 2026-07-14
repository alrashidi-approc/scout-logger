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
  const UsersScreen({super.key, required this.projectId, this.initialPeriod = const PeriodFilter.days(7), this.initialQuery});

  final String projectId;
  final PeriodFilter initialPeriod;
  final String? initialQuery;

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
  late String _search = widget.initialQuery ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _syncUrl() {
    final q = <String, String>{..._period.toQuery()};
    if (_search.isNotEmpty) q['q'] = _search;
    context.go(Uri(path: '/p/${widget.projectId}/users', queryParameters: q).toString());
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
      final users = await _api.fetchUsers(widget.projectId, period: _period, q: _search.isEmpty ? null : _search);
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
    _syncUrl();
    _load();
  }

  void _setSearch(String q) {
    _search = q.trim();
    _syncUrl();
    _load();
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: _setPeriod);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: pageInsets(context, top: pagePad(context)),
        child: PageHeader(
          title: 'Logged-in users',
          subtitle: _search.isNotEmpty
              ? '${_users.length} matches for “$_search”'
              : '${_users.length} identified accounts · guest devices stay in Events & Sessions',
          period: _period,
          onPeriodTap: _openPeriodPicker,
          actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
        ),
      ),
      Padding(
        padding: pageInsets(context, top: 12),
        child: FilterBar(
          period: _period,
          onPeriodChanged: _setPeriod,
          searchHint: 'User, email, phone, install id, device name…',
          searchValue: _search,
          onSearch: _setSearch,
        ),
      ),
      Expanded(
        child: AsyncScreenBody(
          loading: _loading,
          refreshing: _refreshing,
          error: _error,
          onRetry: _load,
          placeholderLayout: PlaceholderLayout.list,
          empty: !_loading && _users.isEmpty
              ? EmptyState(
                  icon: _search.isNotEmpty ? Icons.search_off : Icons.people_outline,
                  title: _search.isNotEmpty ? 'No users match your search' : 'No logged-in users yet',
                  subtitle: _search.isNotEmpty
                      ? 'Try a different name, email, or user id'
                      : 'When the SDK sends a real user id (not the install UUID), they appear here with profile and device context from the client.',
                )
              : null,
          builder: (context) => RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              key: PageStorageKey('users-${widget.projectId}'),
              padding: pageInsets(context, top: 12, bottom: pagePad(context)),
              itemCount: _users.length,
              itemBuilder: (_, i) => _UserCard(user: _users[i], onTap: () => context.push('/p/${widget.projectId}/users/${Uri.encodeComponent(_users[i]['userId'] as String)}')),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.onTap});

  final Map<String, dynamic> user;
  final VoidCallback onTap;

  static String _shortId(String id) => id.length > 16 ? '${id.substring(0, 10)}…${id.substring(id.length - 4)}' : id;

  @override
  Widget build(BuildContext context) {
    final email = user['email'] as String?;
    final name = user['displayName'] as String?;
    final username = user['username'] as String?;
    final userId = user['userId'] as String;
    final title = name ?? email ?? username ?? 'User ${_shortId(userId)}';
    final subtitle = name != null
        ? (email ?? username)
        : (email != null && username != null ? username : null);
    final last = DateTime.tryParse(user['lastSeenAt'] as String? ?? '');
    final errors = user['errorCount'] as int? ?? 0;
    final events = user['eventCount'] as int? ?? 0;
    final contextLine = [
      if (user['platform'] != null) '${user['platform']}',
      if (user['appVersion'] != null) 'v${user['appVersion']}',
      if (user['country'] != null) '${user['country']}',
      if (user['deviceName'] != null) '${user['deviceName']}',
    ].join(' · ');
    final activity = [
      if (last != null) TextSpan(text: 'Last ${DateFormat.MMMd().add_jm().format(last.toLocal())} · ', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
      TextSpan(text: '$events events', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
      if (errors > 0) TextSpan(text: ' · $errors errors', style: const TextStyle(fontSize: 11, color: AppTheme.error, fontWeight: FontWeight.w600)),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: errors > 0 ? AppTheme.error.withValues(alpha: 0.35) : AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                child: Text((title.isNotEmpty ? title[0] : '?').toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  if (subtitle != null) Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                  if (name != null || email != null || username != null)
                    Text(_shortId(userId), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppTheme.muted, fontFamily: 'monospace')),
                  if (contextLine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(contextLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                  ],
                  const SizedBox(height: 2),
                  Text.rich(TextSpan(children: activity)),
                ]),
              ),
              const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.chevron_right, size: 18, color: AppTheme.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}
