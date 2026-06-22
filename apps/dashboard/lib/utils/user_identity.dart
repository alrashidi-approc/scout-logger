/// Client-side mirror of server identity rules (for badges when API has no flag).

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

String? installIdFromPayload(Map<String, dynamic>? payload) {
  if (payload == null) return null;
  final device = payload['device'] is Map ? Map<String, dynamic>.from(payload['device'] as Map) : null;
  final user = payload['user'] is Map ? Map<String, dynamic>.from(payload['user'] as Map) : null;
  for (final v in [device?['installId'], device?['anonymousId'], user?['anonymousId']]) {
    final s = v?.toString().trim();
    if (s != null && s.isNotEmpty) return s;
  }
  return null;
}

bool isIdentifiedAppUser({String? userId, String? installId}) {
  if (userId == null || userId.isEmpty) return false;
  if (installId != null && installId.isNotEmpty) return userId != installId;
  return !_uuidV4.hasMatch(userId);
}

bool isGuestAppUser({String? userId, String? installId}) {
  if (userId == null || userId.isEmpty) return false;
  if (installId != null && installId.isNotEmpty) return userId == installId;
  return _uuidV4.hasMatch(userId);
}

bool isGuestEvent(Map<String, dynamic> event) {
  final payload = event['payload'] is Map ? Map<String, dynamic>.from(event['payload'] as Map) : null;
  final userId = event['userId']?.toString() ?? payload?['user']?['id']?.toString();
  return isGuestAppUser(userId: userId, installId: installIdFromPayload(payload));
}

String userDisplayLabel({required String? userId, String? installId, bool? isGuest}) {
  if (userId == null || userId.isEmpty) return 'Guest';
  final guest = isGuest ?? isGuestAppUser(userId: userId, installId: installId);
  return guest ? 'Guest' : userId;
}
