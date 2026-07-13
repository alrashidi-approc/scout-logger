import '../config/server_config.dart';
import 'package:scout_models/scout_models.dart';

String dashboardBaseUrl(ServerConfig config) =>
    '${config.publicUrl}${config.dashboardUrlPath}';

/// Deep link for threshold / spike alerts — opens filtered events for the alert window.
String dashboardShareUrl(ServerConfig config, String token) =>
    '${dashboardBaseUrl(config)}/share/$token';

String dashboardSpikeUrl(
  ServerConfig config, {
  required String projectId,
  required String metric,
  required ThresholdConfig threshold,
}) {
  final hours = (threshold.windowMinutes / 60).ceil().clamp(1, 72);
  final query = <String, String>{'hours': '$hours'};
  if (metric == 'crash') {
    query['type'] = 'crash';
  } else {
    query['type'] = 'errors';
    query['level'] = 'error';
  }
  if (!threshold.environments.contains('*') && threshold.environments.isNotEmpty) {
    query['environment'] = threshold.environments.first;
  }
  return Uri.parse('${dashboardBaseUrl(config)}/p/$projectId/events')
      .replace(queryParameters: query)
      .toString();
}
