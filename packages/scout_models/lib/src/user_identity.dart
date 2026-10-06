/// App-user identity inferred from ingest payloads — no SDK flag required.
///
/// Guest: `user.id` equals the device install / anonymous id (UUID).
/// Logged-in: `user.id` differs from `device.installId` / `device.anonymousId`.
final uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

String? installIdFromPayload(Map<String, dynamic>? payload) {
  if (payload == null) return null;
  final device = payload['device'] is Map ? Map<String, dynamic>.from(payload['device'] as Map) : null;
  final user = payload['user'] is Map ? Map<String, dynamic>.from(payload['user'] as Map) : null;
  for (final v in [device?['installId'], user?['installId'], device?['anonymousId'], user?['anonymousId']]) {
    final s = v?.toString().trim();
    if (s != null && s.isNotEmpty) return s;
  }
  return null;
}

String? userEmailFromPayload(Map<String, dynamic>? payload) {
  if (payload == null) return null;
  final user = payload['user'] is Map ? Map<String, dynamic>.from(payload['user'] as Map) : null;
  final email = user?['email']?.toString().trim();
  return email != null && email.isNotEmpty ? email : null;
}

bool isIdentifiedAppUser({String? userId, String? installId}) {
  if (userId == null || userId.isEmpty) return false;
  if (installId != null && installId.isNotEmpty) return userId != installId;
  return !uuidV4.hasMatch(userId);
}

bool isGuestAppUser({String? userId, String? installId}) {
  if (userId == null || userId.isEmpty) return false;
  if (installId != null && installId.isNotEmpty) return userId == installId;
  return uuidV4.hasMatch(userId);
}
