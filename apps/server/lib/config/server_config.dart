import 'dart:io';

import 'package:scout_server/db/scout_db.dart';

import 'env_file.dart';

class ServerConfig {
  ServerConfig({
    required this.host,
    required this.port,
    required this.dbConfig,
    required this.dashboardApiKey,
    required this.publicUrl,
    required this.geoEnabled,
    required this.dashboardWebDir,
    required this.dashboardWebPath,
  });

  factory ServerConfig.load({EnvFile? env}) {
    final e = env ?? EnvFile.load();
    final port = int.tryParse(e['PORT'] ?? '') ?? 8080;
    final host = e['HOST'] ?? '0.0.0.0';
    final webPath = _normalizeWebPath(e['DASHBOARD_WEB_PATH'] ?? 'scout/dashboard');
    return ServerConfig(
      host: host,
      port: port,
      dbConfig: DbConfig.fromEnv(e),
      dashboardApiKey: e['DASHBOARD_API_KEY'] ?? '',
      publicUrl: (e['PUBLIC_URL'] ?? 'http://localhost:$port').replaceAll(RegExp(r'/+$'), ''),
      geoEnabled: _bool(e['GEO_ENABLED'], defaultValue: true),
      dashboardWebDir: e['DASHBOARD_WEB_DIR'] ?? _defaultDashboardDir(e),
      dashboardWebPath: webPath,
    );
  }

  final String host;
  final int port;
  final DbConfig dbConfig;
  final String dashboardApiKey;
  final String publicUrl;
  final bool geoEnabled;
  final String dashboardWebDir;
  /// URL path without leading slash, e.g. `scout/dashboard`.
  final String dashboardWebPath;

  String get dashboardUrlPath => '/$dashboardWebPath';

  String get dashboardPublicUrl => '$publicUrl$dashboardUrlPath/';

  static bool _bool(String? v, {required bool defaultValue}) {
    if (v == null) return defaultValue;
    return v == '1' || v.toLowerCase() == 'true' || v.toLowerCase() == 'yes';
  }

  static String _normalizeWebPath(String raw) {
    return raw.replaceAll(RegExp(r'^/+|/+$'), '');
  }

  static String _defaultDashboardDir(EnvFile e) {
    final root = projectRootFromEnv();
    final cwd = Directory.current.path;
    final candidates = [
      if (root != null) '$root/apps/dashboard/build/web',
      '$cwd/apps/dashboard/build/web',
      '$cwd/../dashboard/build/web',
      '$cwd/dashboard/build/web',
    ];
    for (final path in candidates) {
      if (Directory(path).existsSync()) return path;
    }
    return candidates.first;
  }
}
