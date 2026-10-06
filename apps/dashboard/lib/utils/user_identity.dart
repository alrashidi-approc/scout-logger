/// Display helpers on top of the shared identity rules in `scout_models`.
library;

import 'package:scout_models/scout_models.dart' show installIdFromPayload, isGuestAppUser;

export 'package:scout_models/scout_models.dart'
    show installIdFromPayload, userEmailFromPayload, isIdentifiedAppUser, isGuestAppUser;

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
