import 'package:scout_models/scout_models.dart';

Set<String> notificationCategoriesFor({
  required String type,
  required Map<String, dynamic> payload,
}) {
  final cats = <String>{};
  if (type == 'crash') cats.add('crash');
  if (type == 'error') cats.add('error');
  if (type != 'network') return cats;

  final network = payload['network'];
  if (network is! Map) return cats;
  final n = Map<String, dynamic>.from(network);
  final readable = n['readable'];
  final fault = NetworkFaultInfo.fromJson(readable is Map ? readable['fault'] : null) ?? classifyNetworkFault(n);

  if (fault.kind == 'transport') cats.add('network_transport');
  switch (fault.faultClass) {
    case NetworkFaultClass.critical:
      cats.add('network_critical');
    case NetworkFaultClass.user:
      cats.add('network_user');
    case NetworkFaultClass.auth:
      cats.add('network_auth');
    case NetworkFaultClass.success:
    case NetworkFaultClass.unknown:
      break;
  }
  return cats;
}

bool environmentMatchesRule(String environment, List<String> ruleEnvs) {
  if (ruleEnvs.contains('*')) return true;
  return ruleEnvs.map((e) => e.toLowerCase()).contains(environment.toLowerCase());
}

/// Automatic alerts only for release/production builds (not debug/staging/dev).
/// Accepts common SDK labels: production, prod, release.
bool isReleaseNotificationEnvironment(String? environment) {
  final e = environment?.trim().toLowerCase() ?? '';
  return e == 'production' || e == 'prod' || e == 'release';
}
