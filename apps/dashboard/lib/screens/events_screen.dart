import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../widgets/event_card.dart';
import '../widgets/page_header.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final _api = ScoutApi();
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _error;
  String? _typeFilter;

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
      final events = await _api.fetchEvents(widget.projectId, type: _typeFilter);
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
          child: PageHeader(
            title: 'Events',
            subtitle: 'Live stream of ingested telemetry',
            actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
          child: Wrap(
            spacing: 8,
            children: [
              FilterChip(label: const Text('All'), selected: _typeFilter == null, onSelected: (_) {
                _typeFilter = null;
                _load();
              }),
              for (final t in ['error', 'crash', 'network', 'session', 'span', 'log'])
                FilterChip(label: Text(t), selected: _typeFilter == t, onSelected: (_) {
                  _typeFilter = t;
                  _load();
                }),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const LoadingView()
              : _error != null
                  ? ErrorPanel(message: _error!, onRetry: _load)
                  : _events.isEmpty
                      ? const EmptyState(icon: Icons.inbox_outlined, title: 'No events', subtitle: 'Send a test event with ./dev test')
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(28),
                            itemCount: _events.length,
                            itemBuilder: (_, i) => EventCard(
                              event: _events[i],
                              onTap: () => context.go('/p/${widget.projectId}/events/${_events[i]['id']}'),
                            ),
                          ),
                        ),
        ),
      ],
    );
  }
}
