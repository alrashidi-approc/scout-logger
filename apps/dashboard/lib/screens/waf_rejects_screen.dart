import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../services/api_client.dart';
import '../services/dashboard_log_service.dart';
import '../services/screen_cache.dart';
import '../theme/app_theme.dart';
import '../utils/date_range.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../utils/waf_rejects_pdf.dart';
import '../widgets/event_card.dart';
import '../widgets/filter_bar.dart';
import '../widgets/page_header.dart';

/// Network calls that look like WAF / edge HTML block pages
/// (status + content-type from project settings).
class WafRejectsScreen extends StatefulWidget {
  const WafRejectsScreen({
    super.key,
    required this.projectId,
    this.initialPeriod = const PeriodFilter.days(30),
    this.initialQuery,
    this.initialEnvironment,
    this.initialAppVersion,
  });

  final String projectId;
  final PeriodFilter initialPeriod;
  final String? initialQuery;
  final String? initialEnvironment;
  final String? initialAppVersion;

  @override
  State<WafRejectsScreen> createState() => _WafRejectsScreenState();
}

class _WafRejectsScreenState extends State<WafRejectsScreen> {
  static const _pageSize = 50;

  final _api = ScoutApi();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _events = [];
  List<String> _environments = [];
  List<String> _appVersions = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;
  int _offset = 0;
  int _total = 0;
  bool _hasMore = false;
  late PeriodFilter _period;
  late String _search;
  String? _environment;
  String? _appVersion;
  Map<String, dynamic>? _waf;
  bool _exporting = false;

  String get _cacheKey => screenCacheKey(
        'waf-rejects',
        projectId: widget.projectId,
        period: _period,
        extra: {
          'q': _search.isEmpty ? null : _search,
          'environment': _environment,
          'appVersion': _appVersion,
        },
      );

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
    _search = widget.initialQuery ?? '';
    _environment = widget.initialEnvironment;
    _appVersion = widget.initialAppVersion;
    _scroll.addListener(_onScroll);
    if (!_restore()) _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _restore() {
    final cached = ScreenCache.instance.read<Map<String, dynamic>>(_cacheKey);
    if (cached == null) return false;
    _events = jsonListMaps(cached['events']);
    _total = cached['total'] as int? ?? _events.length;
    _hasMore = cached['hasMore'] == true;
    _offset = cached['offset'] as int? ?? 0;
    _environments = (cached['environments'] as List?)?.map((e) => e.toString()).toList() ?? [];
    _appVersions = (cached['appVersions'] as List?)?.map((e) => e.toString()).toList() ?? [];
    _waf = cached['waf'] is Map ? Map<String, dynamic>.from(cached['waf'] as Map) : null;
    _hasData = true;
    _loading = false;
    _refreshing = false;
    _error = null;
    return true;
  }

  void _writeCache() {
    ScreenCache.instance.write(_cacheKey, {
      'events': _events,
      'total': _total,
      'hasMore': _hasMore,
      'offset': _offset,
      'environments': _environments,
      'appVersions': _appVersions,
      'waf': _waf,
    });
  }

  void _onScroll() {
    if (!_hasMore || _loading || _refreshing) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _load(more: true);
    }
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_loading || _refreshing || !_hasMore)) return;
    setState(() {
      _error = null;
      if (more) {
        _refreshing = true;
      } else {
        beginScreenLoad(
          hasData: _hasData,
          apply: ({required loading, required refreshing, error}) {
            _loading = loading;
            _refreshing = refreshing;
            _error = error;
          },
        );
        _offset = 0;
      }
    });
    try {
      final pageF = _api.fetchEvents(
        widget.projectId,
        type: 'waf',
        period: _period,
        q: _search.isEmpty ? null : _search,
        environment: _environment,
        appVersion: _appVersion,
        limit: _pageSize,
        offset: more ? _offset + _pageSize : 0,
        view: 'all',
      );
      final settingsF = more ? null : _api.fetchProjectSettings(widget.projectId);
      final facetsF = more
          ? null
          : _api.fetchFilterFacets(
              widget.projectId,
              period: _period,
              environment: _environment,
              appVersion: _appVersion,
            );
      final page = await pageF;
      final events = jsonListMaps(page['events']);
      Map<String, dynamic>? settings;
      Map<String, dynamic>? facets;
      if (settingsF != null) settings = await settingsF;
      if (facetsF != null) facets = await facetsF;
      if (!mounted) return;
      setState(() {
        if (more) {
          _events = [..._events, ...events];
          _offset = page['offset'] as int? ?? _offset + _pageSize;
        } else {
          _events = events;
          _offset = page['offset'] as int? ?? 0;
          if (settings != null) {
            _waf = settings['waf'] is Map ? Map<String, dynamic>.from(settings['waf'] as Map) : null;
          }
          if (facets != null) {
            _environments = (facets['environments'] as List?)?.map((e) => e.toString()).toList() ?? [];
            _appVersions = (facets['appVersions'] as List?)?.map((e) => e.toString()).toList() ?? [];
          }
        }
        _total = page['total'] as int? ?? _events.length;
        _hasMore = page['hasMore'] == true;
        _hasData = true;
        _loading = false;
        _refreshing = false;
      });
      _writeCache();
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

  void _apply({
    PeriodFilter? period,
    String? search,
    String? environment,
    bool setEnvironment = false,
    String? appVersion,
    bool setAppVersion = false,
  }) {
    setState(() {
      if (period != null) _period = period;
      if (search != null) _search = search;
      if (setEnvironment) _environment = environment;
      if (setAppVersion) _appVersion = appVersion;
    });
    final q = <String, String>{
      ..._period.toQuery(),
      if (_search.isNotEmpty) 'q': _search,
      if (_environment != null) 'environment': _environment!,
      if (_appVersion != null) 'appVersion': _appVersion!,
    };
    context.go(Uri(path: '/p/${widget.projectId}/waf', queryParameters: q).toString());
    _load();
  }

  String get _subtitle {
    final codes = (_waf?['statusCodes'] as List?)?.join(', ') ?? '—';
    final types = (_waf?['contentTypes'] as List?)?.join(', ') ?? '—';
    return '$_total rejects · status $codes · $types';
  }

  Future<void> _exportPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final data = await _api.fetchWafExport(
        widget.projectId,
        period: _period,
        q: _search.isEmpty ? null : _search,
        environment: _environment,
        appVersion: _appVersion,
      );
      final events = jsonListMaps(data['events']);
      final groups = groupWafExportEvents(events);
      await Printing.layoutPdf(
        onLayout: (_) => buildWafRejectsPdf(
          projectName: data['projectName']?.toString() ?? widget.projectId,
          groups: groups,
          periodLabel: _period.label(),
          environment: _environment,
          appVersion: _appVersion,
          search: _search.isEmpty ? null : _search,
          total: data['total'] as int?,
          exported: data['exported'] as int? ?? events.length,
        ),
      );
    } catch (e) {
      DashboardLogService.record(projectId: widget.projectId, message: formatLoadError(e));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncScreenBody(
      loading: _loading,
      refreshing: _refreshing && _events.isEmpty,
      error: _error,
      onRetry: _load,
      placeholderLayout: PlaceholderLayout.list,
      builder: (context) => RefreshIndicator(
        onRefresh: () => _load(),
        child: ListView(
          controller: _scroll,
          padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
          children: [
            PageHeader(
              title: 'WAF rejects',
              subtitle: _subtitle,
              actions: [
                FilledButton.icon(
                  onPressed: _exporting ? null : _exportPdf,
                  icon: _exporting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Export PDF'),
                ),
                TextButton.icon(
                  onPressed: () => context.go('/p/${widget.projectId}/settings'),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Settings'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PeriodFilterBar(value: _period, onChanged: (p) => _apply(period: p)),
            const SizedBox(height: 12),
            SearchField(
              hint: 'Search URL, message…',
              initialValue: _search,
              onSubmitted: (q) => _apply(search: q),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FacetDropdown(
                  label: 'Environment',
                  options: _environments,
                  selected: _environment,
                  onSelected: (v) => _apply(setEnvironment: true, environment: v),
                ),
                FacetDropdown(
                  label: 'App version',
                  options: _appVersions,
                  selected: _appVersion,
                  onSelected: (v) => _apply(setAppVersion: true, appVersion: v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_events.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    'No WAF-looking responses in this range.\n'
                    'HTML block pages (e.g. text/html on API calls) show up here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.muted),
                  ),
                ),
              )
            else
              for (final e in _events)
                EventCard(
                  event: e,
                  onTap: () => context.go('/p/${widget.projectId}/events/${e['id']}'),
                ),
            if (_hasMore)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: _refreshing
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(onPressed: () => _load(more: true), child: const Text('Load more')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
