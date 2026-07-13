import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

import '../config/server_config.dart';

bool _looksLikeAssetPath(String path) {
  final last = path.split('/').last;
  return last.contains('.');
}

const _noCacheHeaders = {
  'Cache-Control': 'no-cache, no-store, must-revalidate',
  'Pragma': 'no-cache',
  'Expires': '0',
};

bool _shouldNotCache(String path, int statusCode) {
  if (statusCode != 200 && statusCode != 304) return false;
  final lower = path.toLowerCase();
  if (!lower.contains('.')) return true;
  return lower.endsWith('.html') ||
      lower.endsWith('.js') ||
      lower.endsWith('.wasm') ||
      lower.endsWith('.json') ||
      lower.endsWith('.css');
}

Response _applyCacheHeaders(Request request, Response response) {
  if (!_shouldNotCache(request.url.path, response.statusCode)) return response;
  final headers = Map<String, String>.from(response.headers)..addAll(_noCacheHeaders);
  return response.change(headers: headers);
}

Handler? dashboardWebHandler(ServerConfig config) {
  final dir = config.dashboardWebDir;
  if (dir.isEmpty || !Directory(dir).existsSync()) return null;
  final indexFile = File('$dir/index.html');
  final staticHandler = createStaticHandler(
    dir,
    defaultDocument: 'index.html',
    serveFilesOutsidePath: true,
  );
  return (Request request) async {
    final response = await staticHandler(request);
    if (response.statusCode == 404 && !_looksLikeAssetPath(request.url.path)) {
      if (!indexFile.existsSync()) return _applyCacheHeaders(request, response);
      return _applyCacheHeaders(
        request,
        Response.ok(
          await indexFile.readAsString(),
          headers: {'Content-Type': 'text/html; charset=utf-8', ..._noCacheHeaders},
        ),
      );
    }
    return _applyCacheHeaders(request, response);
  };
}

Handler dashboardFallback(ServerConfig config, Handler? handler) {
  if (handler == null) {
    return (_) => Response.notFound('Dashboard not built. Run: cd apps/dashboard && flutter build web');
  }
  return handler;
}
