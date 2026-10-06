import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'package:scout_server/config/env_file.dart';
import 'package:scout_server/config/server_config.dart';
import 'package:scout_server/middleware/http_utils.dart';

void main() {
  test('constantTimeEquals', () {
    expect(constantTimeEquals('secret', 'secret'), isTrue);
    expect(constantTimeEquals('secret', 'secreT'), isFalse);
    expect(constantTimeEquals('secret', 'secrets'), isFalse);
    expect(constantTimeEquals('', ''), isTrue);
  });

  test('jsonErr escapes message', () async {
    final res = jsonErr('bad "value"\n', status: 422);
    expect(res.statusCode, 422);
    expect(jsonDecode(await res.readAsString()), {'ok': false, 'error': 'bad "value"\n'});
  });

  group('corsMiddleware', () {
    final config = ServerConfig.load(
      env: EnvFile({
        'JWT_SECRET': 'a' * 64,
        'ENCRYPTION_KEY': 'b' * 64,
        'DATABASE_URL': 'postgres://u:p@localhost/scout',
        'PUBLIC_URL': 'https://scout.example.com',
        'CORS_ORIGINS': 'http://localhost:8081',
      }),
    );
    final handler = corsMiddleware(config)((_) => Response.ok('x'));
    Future<Map<String, String>> headers(String method, String path, String? origin) async => (await handler(
          Request(method, Uri.parse('http://localhost$path'), headers: {if (origin != null) 'origin': origin}),
        ))
            .headers;

    test('v1 allows any origin', () async {
      for (final method in ['GET', 'OPTIONS']) {
        final h = await headers(method, '/v1/events/batch', 'https://app.example.com');
        expect(h['access-control-allow-origin'], '*');
        expect(h['vary'], isNull);
      }
    });

    test('api echoes allowlisted origin with Vary', () async {
      for (final method in ['GET', 'OPTIONS']) {
        final h = await headers(method, '/api/projects', 'http://localhost:8081');
        expect(h['access-control-allow-origin'], 'http://localhost:8081');
        expect(h['vary'], 'Origin');
      }
      expect((await headers('GET', '/api/projects', 'https://scout.example.com'))['access-control-allow-origin'],
          'https://scout.example.com');
    });

    test('api omits allow-origin for unknown or missing origin', () async {
      for (final method in ['GET', 'OPTIONS']) {
        expect((await headers(method, '/api/projects', 'https://evil.example.com'))['access-control-allow-origin'], isNull);
        expect((await headers(method, '/api/projects', null))['access-control-allow-origin'], isNull);
      }
    });
  });

  group('readBody', () {
    Request post(Stream<List<int>> body, {Map<String, String> headers = const {}}) =>
        Request('POST', Uri.parse('http://localhost/x'), body: body, headers: headers);

    test('reads body under the limit', () async {
      expect(await readBody(post(Stream.value(utf8.encode('{"a":"é"}')))), '{"a":"é"}');
    });

    test('rejects oversized Content-Length up front', () {
      expect(readBody(post(const Stream.empty(), headers: {'content-length': '${maxBodyBytes + 1}'})),
          throwsA(isA<BodyTooLargeException>()));
    });

    test('rejects oversized streamed body', () {
      final chunk = List.filled(1024 * 1024, 0);
      expect(readBody(post(Stream.fromIterable(List.filled(11, chunk)))), throwsA(isA<BodyTooLargeException>()));
    });
  });
}
