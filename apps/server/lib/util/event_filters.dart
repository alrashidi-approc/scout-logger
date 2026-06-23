/// SQL fragment — append as `AND $sqlHideSessionHeartbeat` on events queries.
const sqlHideSessionHeartbeat = '''
  NOT (type = 'session' AND COALESCE(payload->>'action', '') = 'heartbeat')
''';

bool isSessionHeartbeat(String type, Map<String, dynamic> payload) =>
    type == 'session' && payload['action']?.toString() == 'heartbeat';
