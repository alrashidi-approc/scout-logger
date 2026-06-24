import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../widgets/page_header.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _api = ScoutApi();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;

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
      final users = await _api.fetchAdminUsers();
      if (mounted) setState(() {
        _users = users;
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

  Future<void> _toggleCreate(Map<String, dynamic> user, bool value) async {
    try {
      await _api.updateAdminUser(user['id'] as String, canCreateProjects: value);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _toggleAdmin(Map<String, dynamic> user, bool value) async {
    try {
      await _api.updateAdminUser(user['id'] as String, globalRole: value ? 'admin' : 'user');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncScreenBody(
      loading: _loading,
            refreshing: _refreshing,
      error: _error,
      onRetry: _load,
      placeholderLayout: PlaceholderLayout.list,
      builder: _buildContent,
    );
  }

  Widget _buildContent(BuildContext context) {
    return ListView(
      padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
      children: [
        const PageHeader(
          title: 'Team & permissions',
          subtitle: 'Admins can access everything. Grant “Create projects” so members can add new apps.',
        ),
        const SizedBox(height: 20),
        ..._users.map((u) {
          final verified = u['emailVerified'] == true;
          final isAdmin = u['globalRole'] == 'admin';
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(u['email'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        '${u['projectCount'] ?? 0} projects · ${verified ? 'Verified' : 'Pending verification'}',
                        style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                    ]),
                  ),
                  if (isAdmin)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(6)),
                      child: const Text('Admin', style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                ]),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Admin', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Full access to all projects and settings', style: TextStyle(fontSize: 12)),
                  value: isAdmin,
                  onChanged: (v) => _toggleAdmin(u, v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Can create projects', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Allow creating new Scout apps / DSN keys', style: TextStyle(fontSize: 12)),
                  value: isAdmin || u['canCreateProjects'] == true,
                  onChanged: isAdmin ? null : (v) => _toggleCreate(u, v),
                ),
              ]),
            ),
          );
        }),
      ],
    );
  }
}
