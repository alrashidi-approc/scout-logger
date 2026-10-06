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
    required this.jwtSecret,
    required this.jwtSessionTtlDays,
    required this.jwtRememberTtlDays,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUser,
    required this.smtpPassword,
    required this.smtpFrom,
    required this.smtpAllowInsecure,
    required this.encryptionKey,
    required this.platformOwnerEmail,
    required this.slackSigningSecret,
    this.signupEnabled = false,
    this.corsOrigins = const {},
  });

  factory ServerConfig.load({EnvFile? env}) {
    final e = env ?? EnvFile.load();
    final port = int.tryParse(e['PORT'] ?? '') ?? 8080;
    final host = e['HOST'] ?? '0.0.0.0';
    final webPath = _normalizeWebPath(e['DASHBOARD_WEB_PATH'] ?? 'scout/dashboard');
    final jwtSecret = _secret(e, 'JWT_SECRET');
    final encryptionKey = _secret(e, 'ENCRYPTION_KEY');
    if (jwtSecret == encryptionKey) throw StateError('JWT_SECRET and ENCRYPTION_KEY must differ');
    final dashboardApiKey = e['DASHBOARD_API_KEY']?.trim() ?? '';
    if (dashboardApiKey.isNotEmpty) _secret(e, 'DASHBOARD_API_KEY');
    final publicUrl = (e['PUBLIC_URL'] ?? 'http://localhost:$port').replaceAll(RegExp(r'/+$'), '');
    return ServerConfig(
      host: host,
      port: port,
      dbConfig: DbConfig.fromEnv(e),
      dashboardApiKey: dashboardApiKey,
      publicUrl: publicUrl,
      geoEnabled: _bool(e['GEO_ENABLED'], defaultValue: true),
      dashboardWebDir: e['DASHBOARD_WEB_DIR'] ?? _defaultDashboardDir(e),
      dashboardWebPath: webPath,
      jwtSecret: jwtSecret,
      jwtSessionTtlDays: int.tryParse(e['JWT_SESSION_TTL_DAYS'] ?? '') ?? 1,
      jwtRememberTtlDays: int.tryParse(e['JWT_REMEMBER_TTL_DAYS'] ?? '') ?? 30,
      smtpHost: e['SMTP_HOST'] ?? '',
      smtpPort: int.tryParse(e['SMTP_PORT'] ?? '') ?? 587,
      smtpUser: e['SMTP_USER'] ?? '',
      smtpPassword: e['SMTP_PASSWORD'] ?? '',
      smtpFrom: e['SMTP_FROM'] ?? e['SMTP_USER'] ?? 'noreply@scout.local',
      smtpAllowInsecure: _bool(e['SMTP_ALLOW_INSECURE'], defaultValue: false),
      encryptionKey: encryptionKey,
      platformOwnerEmail: (e['PLATFORM_OWNER_EMAIL'] ?? 'mohaalrashidi4@gmail.com').trim().toLowerCase(),
      slackSigningSecret: (e['SLACK_SIGNING_SECRET'] ?? '').trim(),
      signupEnabled: _bool(e['SIGNUP_ENABLED'], defaultValue: false),
      corsOrigins: {
        Uri.parse(publicUrl).origin,
        for (final o in (e['CORS_ORIGINS'] ?? '').split(','))
          if (o.trim().isNotEmpty) o.trim().replaceAll(RegExp(r'/+$'), ''),
      },
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
  final String jwtSecret;
  final int jwtSessionTtlDays;
  final int jwtRememberTtlDays;
  final String smtpHost;
  final int smtpPort;
  final String smtpUser;
  final String smtpPassword;
  final String smtpFrom;
  final bool smtpAllowInsecure;
  final String encryptionKey;
  final String platformOwnerEmail;

  /// Slack app signing secret for verifying interactive button callbacks.
  final String slackSigningSecret;

  final bool signupEnabled;

  /// Origins allowed to call non-`/v1/*` routes cross-origin: PUBLIC_URL's origin + `CORS_ORIGINS`.
  final Set<String> corsOrigins;

  String get dashboardUrlPath => '/$dashboardWebPath';

  String get dashboardPublicUrl => '$publicUrl$dashboardUrlPath/';

  static String _secret(EnvFile e, String key) {
    final v = e[key]?.trim() ?? '';
    if (v.length < 32 || v.startsWith('change-me')) {
      throw StateError('$key must be set to >= 32 random chars (use `openssl rand -hex 32`)');
    }
    return v;
  }

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
