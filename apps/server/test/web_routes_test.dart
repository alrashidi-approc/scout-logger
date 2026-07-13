import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'package:scout_server/db/scout_db.dart';
import 'package:scout_server/config/server_config.dart';
import 'package:scout_server/routes/web_routes.dart';

void main() {
  test('dashboardWebHandler falls back to index.html for client routes', () async {
    final dir = Directory.systemTemp.createTempSync('scout-web-');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/index.html').writeAsStringSync('<html>scout</html>');
    File('${dir.path}/main.dart.js').writeAsStringSync('// js');

    final config = ServerConfig(
      host: '0.0.0.0',
      port: 8080,
      dbConfig: DbConfig(host: 'localhost', port: 5432, database: 'scout', username: 'scout', password: 'scout'),
      dashboardApiKey: 'k',
      publicUrl: 'http://localhost:8080',
      geoEnabled: false,
      dashboardWebDir: dir.path,
      dashboardWebPath: 'scout/dashboard',
      jwtSecret: 'secret',
      jwtSessionTtlDays: 1,
      jwtRememberTtlDays: 30,
      smtpHost: '',
      smtpPort: 587,
      smtpUser: '',
      smtpPassword: '',
      smtpFrom: '',
      smtpAllowInsecure: false,
      encryptionKey: 'secret',
      platformOwnerEmail: 'owner@test.com',
      slackSigningSecret: '',
    );

    final handler = dashboardWebHandler(config)!;
    final spa = await handler(Request('GET', Uri.parse('http://localhost/p/proj/issues')));
    expect(spa.statusCode, 200);
    expect(spa.headers['cache-control'], contains('no-cache'));
    expect(await spa.readAsString(), '<html>scout</html>');

    final asset = await handler(Request('GET', Uri.parse('http://localhost/main.dart.js')));
    expect(asset.statusCode, 200);
    expect(asset.headers['cache-control'], contains('no-cache'));
    expect(await asset.readAsString(), '// js');

    final missing = await handler(Request('GET', Uri.parse('http://localhost/missing.asset.js')));
    expect(missing.statusCode, 404);
  });
}
