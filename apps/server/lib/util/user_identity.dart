/// SQL mirrors of the shared identity rules in `scout_models`.
library;

import 'package:scout_models/scout_models.dart' show uuidV4;

export 'package:scout_models/scout_models.dart'
    show installIdFromPayload, userEmailFromPayload, isIdentifiedAppUser, isGuestAppUser;

/// SQL predicate on [events] columns `user_id` and `install_id` (optional table alias).
String identifiedUserSql({String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return '''
${p}user_id IS NOT NULL AND ${p}user_id <> ''
AND (
  (${p}install_id IS NOT NULL AND ${p}user_id <> ${p}install_id)
  OR (${p}install_id IS NULL AND ${p}user_id !~* '${uuidV4.pattern}')
)''';
}

/// Guest events on a device (pre-login anonymous id).
String guestUserSql({String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return '''
${p}user_id IS NOT NULL AND ${p}install_id IS NOT NULL AND ${p}user_id = ${p}install_id''';
}
