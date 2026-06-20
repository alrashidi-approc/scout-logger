import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config/server_config.dart';
import 'middleware/http_utils.dart';
import 'routes/api_routes.dart';
import 'routes/ingest_routes.dart';
import 'routes/web_routes.dart';
import 'services/geo_enricher.dart';
import 'store/analytics_store.dart';
import 'store/scout_store.dart';

Handler createApp({
  required ServerConfig config,
  required ScoutStore store,
  AnalyticsStore? analytics,
}) {
  final router = Router();
  final geo = GeoEnricher(enabled: config.geoEnabled);
  final web = dashboardWebHandler(config);
  final api = apiRoutes(config, store, analytics ?? AnalyticsStore(store.db));
  final dash = config.dashboardWebPath;

  router.get('/health', (_) => Response.ok('{"ok":true}', headers: {'Content-Type': 'application/json'}));
  router.get('/', (_) => Response.found('${config.dashboardUrlPath}/'));
  router.get('/scout', (_) => Response.found('${config.dashboardUrlPath}/'));
  router.post('/v1/events/batch', ingestRoutes(store, geo));

  router.get('/api/dashboard/config', (_) {
    return Response.ok(
      jsonEncode({
        'ok': true,
        'apiBaseUrl': '',
        'publicUrl': config.publicUrl,
        'dashboardPath': config.dashboardUrlPath,
        'apiKey': config.dashboardApiKey,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.mount('/api/', dashboardAuth(config)(api));

  if (web != null) {
    router.get('/$dash', (_) => Response.found('/$dash/'));
    router.mount('/$dash/', web);
  } else {
    router.get('/$dash', dashboardFallback(config, null));
    router.get('/$dash/', dashboardFallback(config, null));
  }

  return Pipeline().addMiddleware(corsMiddleware()).addHandler(router.call);
}
