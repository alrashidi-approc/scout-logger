import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

import '../config/server_config.dart';

Handler? dashboardWebHandler(ServerConfig config) {
  final dir = config.dashboardWebDir;
  if (dir.isEmpty || !Directory(dir).existsSync()) return null;
  return createStaticHandler(
    dir,
    defaultDocument: 'index.html',
    serveFilesOutsidePath: true,
  );
}

Handler dashboardFallback(ServerConfig config, Handler? handler) {
  if (handler == null) {
    return (_) => Response.notFound('Dashboard not built. Run: cd apps/dashboard && flutter build web');
  }
  return handler;
}
