/// App-user identity inferred from ingest payloads — no SDK flag required.
library;

/// Guest: `user.id` equals the device install / anonymous id (UUID).
/// Logged-in: `user.id` differs from `device.installId` / `device.anonymousId`.

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

const _uuidSql =
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';

String? installIdFromPayload(Map<String, dynamic> payload) {
  final device = payload['device'] is Map ? Map<String, dynamic>.from(payload['device'] as Map) : null;
  final user = payload['user'] is Map ? Map<String, dynamic>.from(payload['user'] as Map) : null;
  for (final v in [
    device?['installId'],
    user?['installId'],
    device?['anonymousId'],
    user?['anonymousId'],
  ]) {
    final s = v?.toString().trim();
    if (s != null && s.isNotEmpty) return s;
  }
  return null;
}

String? userEmailFromPayload(Map<String, dynamic> payload) {
  final user = payload['user'] is Map ? Map<String, dynamic>.from(payload['user'] as Map) : null;
  final email = user?['email']?.toString().trim();
  return email != null && email.isNotEmpty ? email : null;
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

/// SQL predicate on [events] columns `user_id` and `install_id` (optional table alias).
String identifiedUserSql({String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return '''
${p}user_id IS NOT NULL AND ${p}user_id <> ''
AND (
  (${p}install_id IS NOT NULL AND ${p}user_id <> ${p}install_id)
  OR (${p}install_id IS NULL AND ${p}user_id !~* '$_uuidSql')
)''';
}

/// Guest events on a device (pre-login anonymous id).
String guestUserSql({String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return '''
${p}user_id IS NOT NULL AND ${p}install_id IS NOT NULL AND ${p}user_id = ${p}install_id''';
}
