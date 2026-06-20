class IngestEvent {
  const IngestEvent({required this.type, required this.timestamp, required this.payload});

  final String type;
  final String timestamp;
  final Map<String, dynamic> payload;

  factory IngestEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    return IngestEvent(
      type: json['type'] as String? ?? 'error',
      timestamp: json['timestamp'] as String? ?? DateTime.now().toUtc().toIso8601String(),
      payload: payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() => {'type': type, 'timestamp': timestamp, 'payload': payload};
}

class BatchIngestRequest {
  const BatchIngestRequest({required this.events});

  final List<IngestEvent> events;

  factory BatchIngestRequest.fromJson(dynamic json) {
    if (json is List) {
      return BatchIngestRequest(
        events: json.map((e) => IngestEvent.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
    }
    if (json is Map) {
      final map = Map<String, dynamic>.from(json);
      final list = map['events'] as List? ?? [];
      return BatchIngestRequest(
        events: list.map((e) => IngestEvent.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
    }
    throw FormatException('Expected JSON array or { events: [...] }');
  }
}
