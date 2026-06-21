import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../widgets/event_card.dart';
import '../widgets/filter_bar.dart';
import '../utils/responsive.dart';
import '../widgets/page_header.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({
    super.key,
    required this.projectId,
    this.initialType,
    this.initialDays,
    this.initialQuery,
    this.initialCountry,
  });

  final String projectId;
  final String? initialType;
  final int? initialDays;
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
  late String? _typeFilter;
  late int? _days;
  late String _search;
  String? _country;

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.initialType;
    _days = widget.initialDays;
    _search = widget.initialQuery ?? '';
    _country = widget.initialCountry;
    _load();
  }

  void _syncUrl() {
    final q = <String, String>{};
    if (_typeFilter != null) q['type'] = _typeFilter!;
    if (_days != null) q['days'] = '$_days';
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
        type: _typeFilter,
        days: _days,
        q: _search.isEmpty ? null : _search,
        country: _country,
      );
      if (mounted) setState(() {
        _events = events;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _applyFilters({String? type, bool setType = false, int? days, String? search, String? country, bool clearCountry = false}) {
    setState(() {
      if (setType) _typeFilter = type;
      if (days != null) _days = days;
      if (search != null) _search = search;
      if (country != null) _country = country;
      if (clearCountry) _country = null;
    });
    _syncUrl();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: pageInsets(context, top: pagePad(context)),
          child: PageHeader(
            title: 'Events',
            subtitle: '${_events.length} events${_days != null ? ' · last $_days days' : ''}',
            actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
          ),
        ),
        Padding(
          padding: pageInsets(context, top: 12),
          child: FilterBar(
            days: _days ?? 7,
            onDaysChanged: (d) => _applyFilters(days: d),
            searchHint: 'Search message…',
            searchValue: _search,
            onSearch: (q) => _applyFilters(search: q),
            typeOptions: const [null, 'errors', 'error', 'crash', 'network', 'session', 'span', 'log'],
            typeSelected: _typeFilter,
            onTypeSelected: (t) => _applyFilters(type: t, setType: true),
          ),
        ),
        Expanded(
          child: _loading
              ? const LoadingView()
              : _error != null
                  ? ErrorPanel(message: _error!, onRetry: _load)
                  : _events.isEmpty
                      ? const EmptyState(icon: Icons.inbox_outlined, title: 'No events', subtitle: 'Try adjusting filters or send a test event')
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
