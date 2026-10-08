import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../services/dashboard_log_service.dart';
import '../services/screen_cache.dart';
import '../theme/app_theme.dart';
import '../utils/date_range.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../widgets/event_card.dart';
import '../widgets/filter_bar.dart';
import '../widgets/page_header.dart';
import '../widgets/period_picker.dart';

class AdvancedSearchScreen extends StatefulWidget {
  const AdvancedSearchScreen({
    super.key,
    required this.projectId,
    this.initialPeriod = const PeriodFilter.days(7),
    this.initialQuery,
  });

  final String projectId;
  final PeriodFilter initialPeriod;
  final String? initialQuery;

  @override
  State<AdvancedSearchScreen> createState() => _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends State<AdvancedSearchScreen> {
  static const _pageSize = 50;

  final _api = ScoutApi();
  List<Map<String, dynamic>> _events = [];
  bool _loading = false;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _hasData = false;
  bool _hasMore = false;
  Object? _error;
  late PeriodFilter _period = widget.initialPeriod;
  late String _search = widget.initialQuery?.trim() ?? '';

  bool get _ready => _search.length >= 3;

  String get _cacheKey => screenCacheKey(
        'search',
        projectId: widget.projectId,
        period: _period,
        extra: {'q': _search},
      );

  @override
  void initState() {
    super.initState();
    if (_ready && !_restore()) _load();
  }

  bool _restore() {
    final cached = ScreenCache.instance.read<Map<String, Object>>(_cacheKey);
    if (cached == null) return false;
    final events = cached['events'];
    if (events is! List) return false;
    _events = [for (final e in events) Map<String, dynamic>.from(e as Map)];
    _hasMore = cached['hasMore'] == true;
    _hasData = true;
    _loading = false;
    _refreshing = false;
    _loadingMore = false;
    _error = null;
    return true;
  }

  void _writeCache() {
    ScreenCache.instance.write(_cacheKey, <String, Object>{
      'events': _events,
      'hasMore': _hasMore,
    });
  }

  void _syncUrl() {
    final q = <String, String>{..._period.toQuery()};
    if (_search.isNotEmpty) q['q'] = _search;
    context.go(Uri(path: '/p/${widget.projectId}/search', queryParameters: q).toString());
  }

  Future<void> _load({bool more = false}) async {
    if (!_ready) return;
    setState(() {
      _error = null;
      if (more) {
        _loadingMore = true;
      } else {
        beginScreenLoad(
          hasData: _hasData,
          apply: ({required loading, required refreshing, error}) {
            _loading = loading;
            _refreshing = refreshing;
            _error = error;
          },
        );
      }
    });
    try {
      final page = await _api.searchLogs(
        widget.projectId,
        q: _search,
        period: _period,
        limit: _pageSize,
        offset: more ? _events.length : 0,
      );
      final events = (page['events'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _events = more ? [..._events, ...events] : events;
        _hasMore = page['hasMore'] == true;
        _hasData = true;
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
      });
      _writeCache();
    } catch (e) {
      DashboardLogService.record(projectId: widget.projectId, message: formatLoadError(e));
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
      });
    }
  }

  void _applySearch(String q) {
    _search = q.trim();
    _hasData = false;
    _syncUrl();
    if (!_ready) {
      setState(() {
        _events = [];
        _hasMore = false;
        _loading = false;
        _refreshing = false;
        _error = null;
      });
      return;
    }
    if (_restore()) {
      setState(() {});
    } else {
      _load();
    }
  }

  void _setPeriod(PeriodFilter p) {
    _period = p;
    _hasData = false;
    _syncUrl();
    if (!_ready) {
      setState(() {});
      return;
    }
    if (_restore()) {
      setState(() {});
    } else {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _events.length;
    final subtitle = !_ready
        ? 'Searches the raw JSON of every event in this project'
        : '$count${_hasMore ? '+' : ''} matches for “$_search”';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: pageInsets(context, top: pagePad(context)),
        child: PageHeader(
          title: 'Advanced search',
          subtitle: subtitle,
          period: _period,
          onPeriodTap: () => showPeriodPicker(context, current: _period, onSelected: _setPeriod),
        ),
      ),
      Padding(
        padding: pageInsets(context, top: 12),
        child: FilterBar(
          period: _period,
          onPeriodChanged: _setPeriod,
          searchHint: 'Text from a request body, response, phone, or any event JSON',
          searchValue: _search,
          onSearch: _applySearch,
        ),
      ),
      Expanded(
        child: AsyncScreenBody(
          loading: _loading,
          refreshing: _refreshing,
          error: _error,
          onRetry: _load,
          placeholderLayout: PlaceholderLayout.list,
          empty: !_loading && _events.isEmpty
              ? EmptyState(
                  icon: _ready ? Icons.search_off : Icons.manage_search,
                  title: _search.isEmpty
                      ? 'Search this project’s logs'
                      : _ready
                          ? 'No events contain that text'
                          : 'Type at least 3 characters',
                  subtitle: _ready
                      ? 'Try a wider date range, or a shorter unique string from the JSON.'
                      : 'Matches request bodies, responses, user numbers, and anything else stored on the event.',
                )
              : null,
          builder: (context) => RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              key: PageStorageKey('search-${widget.projectId}'),
              padding: pageInsets(context, top: 12, bottom: pagePad(context)),
              itemCount: _events.length + (_hasMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= _events.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: _loadingMore
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : TextButton(onPressed: () => _load(more: true), child: const Text('Load more')),
                    ),
                  );
                }
                final event = _events[i];
                final snippet = event['matchSnippet']?.toString() ?? '';
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  EventCard(
                    event: event,
                    onTap: () => context.push('/p/${widget.projectId}/events/${event['id']}'),
                  ),
                  if (snippet.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.panelElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Matched in event JSON', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.muted)),
                        const SizedBox(height: 6),
                        SelectableText(snippet, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.4)),
                      ]),
                    ),
                ]);
              },
            ),
          ),
        ),
      ),
    ]);
  }
}
