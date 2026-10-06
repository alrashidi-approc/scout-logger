import 'package:test/test.dart';

import 'package:scout_server/config/env_file.dart';
import 'package:scout_server/config/server_config.dart';

void main() {
  final jwt = 'a' * 64;
  final enc = 'b' * 64;

  ServerConfig load(Map<String, String> env) => ServerConfig.load(env: EnvFile(env));

  test('throws when secrets are missing', () {
    expect(() => load({'ENCRYPTION_KEY': enc}), throwsStateError);
    expect(() => load({'JWT_SECRET': jwt}), throwsStateError);
  });

  test('throws for short or placeholder secrets', () {
    expect(() => load({'JWT_SECRET': 'short', 'ENCRYPTION_KEY': enc}), throwsStateError);
    expect(() => load({'JWT_SECRET': 'change-me-jwt-secret-min-32-chars', 'ENCRYPTION_KEY': enc}), throwsStateError);
  });

  test('throws when secrets are equal', () {
    expect(() => load({'JWT_SECRET': jwt, 'ENCRYPTION_KEY': jwt}), throwsStateError);
  });

  test('loads two valid distinct secrets', () {
    final config = load({'JWT_SECRET': jwt, 'ENCRYPTION_KEY': enc, 'DATABASE_URL': 'postgres://u:p@localhost/scout'});
    expect(config.jwtSecret, jwt);
    expect(config.encryptionKey, enc);
  });

  final base = {'JWT_SECRET': jwt, 'ENCRYPTION_KEY': enc, 'DATABASE_URL': 'postgres://u:p@localhost/scout'};

  test('SIGNUP_ENABLED defaults to false', () {
    expect(load(base).signupEnabled, isFalse);
    expect(load({...base, 'SIGNUP_ENABLED': 'true'}).signupEnabled, isTrue);
  });

  test('corsOrigins = PUBLIC_URL origin + CORS_ORIGINS', () {
    expect(load({...base, 'PUBLIC_URL': 'https://scout.example.com/'}).corsOrigins, {'https://scout.example.com'});
    final config = load({
      ...base,
      'PUBLIC_URL': 'https://scout.example.com',
      'CORS_ORIGINS': 'http://localhost:8081/, ,https://a.example.com',
    });
    expect(config.corsOrigins, {'https://scout.example.com', 'http://localhost:8081', 'https://a.example.com'});
  });

  test('DASHBOARD_API_KEY optional but strong when set', () {
    expect(load(base).dashboardApiKey, '');
    expect(load({...base, 'DASHBOARD_API_KEY': '  '}).dashboardApiKey, '');
    expect(() => load({...base, 'DASHBOARD_API_KEY': 'short'}), throwsStateError);
    expect(load({...base, 'DASHBOARD_API_KEY': 'c' * 32}).dashboardApiKey, 'c' * 32);
  });
}
