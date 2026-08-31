import 'package:flutter/material.dart';
import 'package:scout_models/scout_models.dart';

import '../services/api_client.dart';
import '../services/dashboard_log_service.dart';
import '../theme/app_theme.dart';
import '../utils/clipboard.dart';
import '../utils/health_check_prompts.dart';
import '../widgets/health_check_report_card.dart';
import '../widgets/page_header.dart';

const _defaultScript = '''import 'dart:convert';
import 'dart:io';

// --- Config (edit here — saved with the script in Scout) ---
const exampleHealthUrl = 'https://example.com/health';
const includeWrite = false;

void emitReport({
  required List<Map<String, dynamic>> checks,
  required List<String> allIds,
  String? current,
  List<String> pending = const [],
}) {
  final ok = checks.where((c) => c['status'] == 'ok').length;
  final fail = checks.where((c) => c['status'] == 'fail').length;
  final timeout = checks.where((c) => c['status'] == 'timeout').length;
  final completed = checks.length;
  final total = allIds.length;
  final pendingN = pending.isNotEmpty ? pending.length : total - completed - (current == null ? 0 : 1);
  final verdict = fail + timeout == 0 && pendingN == 0 ? 'healthy' : ok > 0 ? 'degraded' : 'unhealthy';
  stdout.writeln('SCOUT_REPORT:\${jsonEncode({
    'verdict': verdict,
    'summary': current == null ? '\$ok/\$total ok' : '\$completed/\$total — running \$current',
    'checks': checks,
    'stats': {'total': total, 'completed': completed, 'ok': ok, 'fail': fail, 'timeout': timeout, 'pending': pendingN},
    if (current != null) 'current': current,
    if (pending.isNotEmpty) 'pending': pending,
  })}');
  stdout.flush();
}

Future<void> main() async {
  const allIds = ['example.health'];
  final checks = <Map<String, dynamic>>[];

  for (final id in allIds) {
    final pending = allIds.skip(allIds.indexOf(id) + 1).toList();
    emitReport(checks: checks, allIds: allIds, current: id, pending: pending);
    final url = exampleHealthUrl;
    final sw = Stopwatch()..start();
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final res = await req.close().timeout(const Duration(seconds: 10));
      sw.stop();
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      checks.add({
        'name': id,
        'status': ok ? 'ok' : 'fail',
        'url': url,
        'latencyMs': sw.elapsedMilliseconds,
        'detail': 'HTTP \${res.statusCode}',
      });
      client.close(force: true);
    } catch (e) {
      sw.stop();
      final timedOut = '\$e'.contains('TimeoutException');
      checks.add({
        'name': id,
        'status': timedOut ? 'timeout' : 'fail',
        'url': url,
        'latencyMs': sw.elapsedMilliseconds,
        'detail': '\$e',
      });
    }
    emitReport(checks: checks, allIds: allIds);
  }
}
''';

class HealthCheckScreen extends StatefulWidget {
  const HealthCheckScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<HealthCheckScreen> createState() => _HealthCheckScreenState();
}

class _HealthCheckScreenState extends State<HealthCheckScreen> {
  final _api = ScoutApi();
  final _scriptCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _running = false;
  Object? _error;
  Map<String, dynamic>? _latestRun;
  List<Map<String, dynamic>> _runs = [];
  String? _scriptUpdatedAt;
  Map<String, dynamic>? _share;

  @override
  void dispose() {
    _scriptCtrl.dispose();
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
      final data = await _api.fetchHealthCheck(widget.projectId);
      final runs = await _api.fetchHealthCheckRuns(widget.projectId);
      final scriptMeta = jsonMap(data['script']);
      final script = scriptMeta['script'] as String?;
      if (!mounted) return;
      setState(() {
        _scriptCtrl.text = (script != null && script.isNotEmpty) ? script : _defaultScript;
        _scriptUpdatedAt = scriptMeta['updatedAt'] as String?;
        _latestRun = data['latestRun'] == null ? null : jsonMap(data['latestRun']);
        _share = data['share'] == null ? null : jsonMap(data['share']);
        _runs = runs;
        _loading = false;
      });
    } catch (e, st) {
      DashboardLogService.record(projectId: widget.projectId, message: formatLoadError(e), context: {'stack': '$st'});
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await _api.saveHealthCheckScript(widget.projectId, _scriptCtrl.text);
      if (!mounted) return;
      setState(() {
        _scriptUpdatedAt = saved['updatedAt'] as String?;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Script saved')));
    } catch (e, st) {
      DashboardLogService.record(projectId: widget.projectId, message: formatLoadError(e), context: {'stack': '$st'});
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatLoadError(e))));
    }
  }

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      final result = await _api.runHealthCheck(widget.projectId);
      if (!mounted) return;
      setState(() {
        _latestRun = result['run'] == null ? null : jsonMap(result['run']);
        _share = result['share'] == null ? null : jsonMap(result['share']);
        _running = false;
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Health check finished')));
    } catch (e, st) {
      DashboardLogService.record(projectId: widget.projectId, message: formatLoadError(e), context: {'stack': '$st'});
      if (!mounted) return;
      setState(() => _running = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatLoadError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncScreenBody(
      loading: _loading,
      error: _error,
      onRetry: _load,
      builder: (context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          PageHeader(
            title: 'Server health',
            subtitle: 'Copy a prompt into your app repo → generate script → paste below → save & run.',
            actions: [
              FilledButton.icon(
                onPressed: (_saving || _running) ? null : _save,
                icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save script'),
              ),
              FilledButton.tonalIcon(
                onPressed: (_saving || _running) ? null : _run,
                icon: _running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_outlined, size: 18),
                label: const Text('Run check'),
              ),
            ],
          ),
          if (_running) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Running health check…', style: TextStyle(fontWeight: FontWeight.w600)),
                          Text('This may take a few minutes for large scripts.', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_latestRun != null && !_running) ...[
            const SizedBox(height: 20),
            const Text('Latest report', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            HealthCheckReportCard(run: _latestRun!),
          ],
          if (_share != null) ...[
            const SizedBox(height: 16),
            _ShareLinkCard(share: _share!),
          ],
          const SizedBox(height: 20),
          _PromptCard(
            step: 1,
            title: 'Generate API reference (in your app repo)',
            hint: 'Replace {APP_NAME} and {SOURCE_HINTS}, run in Cursor/Claude/etc., save the MD file.',
            prompt: HealthCheckPrompts.prompt1GenerateApiReference,
          ),
          const SizedBox(height: 12),
          _PromptCard(
            step: 2,
            title: 'Convert MD → Dart script',
            hint: 'Paste your API reference MD where indicated, then copy the generated script.',
            prompt: HealthCheckPrompts.prompt2ConvertToDartScript,
          ),
          const SizedBox(height: 20),
          const Text('3. Paste script here', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          if (_scriptUpdatedAt != null)
            Text('Last saved: $_scriptUpdatedAt', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          if (_scriptUpdatedAt != null) const SizedBox(height: 8),
          TextField(
            controller: _scriptCtrl,
            maxLines: 18,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              labelText: 'health_check.dart',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_runs.length > 1) ...[
            const SizedBox(height: 24),
            const Text('History', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            ..._runs.map((r) => _HistoryTile(run: r, selected: r['id'] == _latestRun?['id'], onTap: () => setState(() => _latestRun = r))),
          ],
        ],
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.step, required this.title, required this.hint, required this.prompt});

  final int step;
  final String title;
  final String hint;
  final String prompt;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: step == 1,
          tilePadding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          title: Text('$step. $title', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(hint, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => copyWithFeedback(context, prompt, message: 'Prompt copied'),
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('Copy prompt'),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: AppTheme.codeBg,
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                prompt,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareLinkCard extends StatelessWidget {
  const _ShareLinkCard({required this.share});

  final Map<String, dynamic> share;

  @override
  Widget build(BuildContext context) {
    final url = share['url'] as String? ?? '';
    final updatedAt = share['updatedAt'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.link_outlined, size: 18, color: AppTheme.muted),
                SizedBox(width: 8),
                Text('Public snapshot link', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Same results until the next health check run. Share with anyone — no login.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
            if (updatedAt != null) ...[
              const SizedBox(height: 4),
              Text('Snapshot updated: $updatedAt', style: TextStyle(color: AppTheme.muted, fontSize: 11)),
            ],
            const SizedBox(height: 12),
            SelectableText(url, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: url.isEmpty ? null : () => copyWithFeedback(context, url, message: 'Share link copied'),
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Copy link'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.run, required this.selected, required this.onTap});

  final Map<String, dynamic> run;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final report = run['report'] is Map ? HealthCheckReport.fromJson(Map<String, dynamic>.from(run['report'] as Map)) : null;
    final stats = report?.stats;
    final okLabel = stats != null ? '${stats.ok}/${stats.total} ok' : '${report?.okCount ?? 0}/${report?.checks.length ?? 0} ok';
    return ListTile(
      selected: selected,
      onTap: onTap,
      leading: Icon(
        Icons.circle,
        size: 10,
        color: report != null ? HealthCheckReportCard.verdictColor(report.verdict) : AppTheme.muted,
      ),
      title: Text(report?.summary ?? '${run['status']} · ${run['startedAt'] ?? ''}'),
      subtitle: report != null ? Text('$okLabel · ${report.verdict}') : null,
      trailing: Text('${run['durationMs'] ?? '—'} ms', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
    );
  }
}
