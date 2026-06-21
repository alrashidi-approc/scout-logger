import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../widgets/event_card.dart';
import '../widgets/filter_bar.dart';
import '../widgets/page_header.dart';
import '../utils/date_range.dart';
import '../utils/responsive.dart';
import '../widgets/period_picker.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({
    super.key,
    required this.projectId,
    this.initialType,
    this.initialLevel,
    this.initialCategory,
    this.initialPeriod = const PeriodFilter.days(7),
    this.initialQuery,
    this.initialCountry,
  });

  final String projectId;
  final String? initialType;
  final String? initialLevel;
  final String? initialCategory;
  final PeriodFilter initialPeriod;
  final String? initialQuery;
  final String? initialCountry;

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final _api = ScoutApi();
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _error;
  late String? _kindFilter;
  late String? _levelFilter;
  late String? _categoryFilter;
  late PeriodFilter _period = widget.initialPeriod;
  late String _search;
  String? _country;

  static const _levelOptions = [null, 'error', 'info', 'warning', 'success'];
  static const _kindOptions = [null, 'errors', 'error', 'crash', 'network', 'session', 'log', 'span'];
  static const _categoryOptions = [null, 'network', 'system', 'crashing', 'logic', 'ui'];

  @override
  void initState() {
    super.initState();
    _kindFilter = widget.initialType;
    _levelFilter = widget.initialLevel;
    _categoryFilter = widget.initialCategory;
    _period = widget.initialPeriod;
    _search = widget.initialQuery ?? '';
    _country = widget.initialCountry;
    _load();
  }

  void _syncUrl() {
    final q = <String, String>{};
    if (_kindFilter != null) q['type'] = _kindFilter!;
    if (_levelFilter != null) q['level'] = _levelFilter!;
    if (_categoryFilter != null) q['category'] = _categoryFilter!;
    q.addAll(_period.toQuery());
    if (_search.isNotEmpty) q['q'] = _search;
    if (_country != null) q['country'] = _country!;
    final uri = Uri(path: '/p/${widget.projectId}/events', queryParameters: q.isEmpty ? null : q);
    context.go(uri.toString());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final events = await _api.fetchEvents(
        widget.projectId,
        type: _kindFilter,
        level: _levelFilter,
        category: _categoryFilter,
        period: _period,
        q: _search.isEmpty ? null : _search,
        country: _country,
      );
      if (mounted) {
        setState(() {
          _events = events;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _apply({
    String? kind,
    bool setKind = false,
    String? level,
    bool setLevel = false,
    String? category,
    bool setCategory = false,
    PeriodFilter? period,
    String? search,
    String? country,
    bool clearCountry = false,
  }) {
    setState(() {
      if (setKind) _kindFilter = kind;
      if (setLevel) _levelFilter = level;
      if (setCategory) _categoryFilter = category;
      if (period != null) _period = period;
      if (search != null) _search = search;
      if (country != null) _country = country;
      if (clearCountry) _country = null;
    });
    _syncUrl();
    _load();
  }

  String _filterSummary() {
    final parts = <String>[];
    if (_levelFilter != null) parts.add('level $_levelFilter');
    if (_kindFilter != null) parts.add('kind $_kindFilter');
    if (_categoryFilter != null) parts.add('category $_categoryFilter');
    if (parts.isEmpty) return '${_events.length} events';
    return '${_events.length} events · ${parts.join(' · ')}';
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: (p) => _apply(period: p));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: pageInsets(context, top: pagePad(context)),
          child: PageHeader(
            title: 'Events',
            subtitle: _filterSummary(),
            period: _period,
            onPeriodTap: _openPeriodPicker,
            actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
          ),
        ),
        Padding(
          padding: pageInsets(context, top: 12),
          child: FilterBar(
            period: _period,
            onPeriodChanged: (p) => _apply(period: p),
            searchHint: 'Search message…',
            searchValue: _search,
            onSearch: (q) => _apply(search: q),
            levelOptions: _levelOptions,
            levelSelected: _levelFilter,
            onLevelSelected: (l) => _apply(level: l, setLevel: true),
            typeOptions: _kindOptions,
            typeSelected: _kindFilter,
            onTypeSelected: (t) => _apply(kind: t, setKind: true),
            categoryOptions: _categoryOptions,
            categorySelected: _categoryFilter,
            onCategorySelected: (c) => _apply(category: c, setCategory: true),
          ),
        ),
        Expanded(
          child: _loading
              ? const LoadingView()
              : _error != null
                  ? ErrorPanel(message: _error!, onRetry: _load)
                  : _events.isEmpty
                      ? const EmptyState(
                          icon: Icons.inbox_outlined,
                          title: 'No events',
                          subtitle: 'Try adjusting level, kind, or category filters',
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            key: PageStorageKey('events-${widget.projectId}'),
                            padding: pageInsets(context, top: 12, bottom: pagePad(context)),
                            itemCount: _events.length,
                            itemBuilder: (_, i) => EventCard(
                              event: _events[i],
                              onTap: () => context.push('/p/${widget.projectId}/events/${_events[i]['id']}'),
                            ),
                          ),
                        ),
        ),
      ],
    );
  }
}
