import 'package:scout_models/scout_models.dart';
import 'package:scout_server/config/server_config.dart';
import 'package:scout_server/db/scout_db.dart';
import 'package:scout_server/util/dashboard_links.dart';
import 'package:test/test.dart';

ServerConfig _cfg() => ServerConfig(
      host: '0.0.0.0',
      port: 8081,
      dbConfig: DbConfig(host: 'localhost', port: 5432, database: 'scout', username: 'scout', password: 'scout'),
      dashboardApiKey: 'k',
      publicUrl: 'http://46.62.217.25:8081',
      geoEnabled: false,
      dashboardWebDir: '',
      dashboardWebPath: 'scout/dashboard',
      jwtSecret: 's',
      jwtSessionTtlDays: 1,
      jwtRememberTtlDays: 30,
      smtpHost: '',
      smtpPort: 587,
      smtpUser: '',
      smtpPassword: '',
      smtpFrom: '',
      smtpAllowInsecure: false,
      encryptionKey: 's',
      platformOwnerEmail: 'a@b.com',
      slackSigningSecret: '',
    );

void main() {
  test('dashboardSpikeUrl links to filtered events', () {
    const t = ThresholdConfig(windowMinutes: 5, crashCount: 1);
    final url = dashboardSpikeUrl(
      _cfg(),
      projectId: 'proj1',
      metric: 'crash',
      threshold: t,
    );
    expect(
      url,
      'http://46.62.217.25:8081/scout/dashboard/p/proj1/events?hours=1&type=crash&environment=production',
    );
  });
}
