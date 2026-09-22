import 'package:scout_models/scout_models.dart';
import 'package:test/test.dart';

void main() {
  const empCardPath = '/EPAMobileAppServices/resources/empCardImageM';

  final empCardRule = ExpectedNetworkResponse(
    method: 'POST',
    path: empCardPath,
    statusCodes: const [404],
    note: 'Employee has no card image',
  );

  group('matchExpectedNetworkResponse', () {
    test('matches POST + normalized path + 404', () {
      final hit = matchExpectedNetworkResponse(
        rules: [empCardRule],
        method: 'POST',
        url: 'https://api.example.com$empCardPath?x=1',
        statusCode: 404,
      );
      expect(hit, isNotNull);
      expect(hit!.note, 'Employee has no card image');
    });

    test('ignores numeric id segments when matching', () {
      final hit = matchExpectedNetworkResponse(
        rules: [
          const ExpectedNetworkResponse(
            method: 'GET',
            path: '/users/:id/avatar',
            statusCodes: [404],
          ),
        ],
        method: 'GET',
        url: '/users/42/avatar',
        statusCode: 404,
      );
      expect(hit, isNotNull);
    });

    test('non-matching path stays unmatched', () {
      final hit = matchExpectedNetworkResponse(
        rules: [empCardRule],
        method: 'POST',
        url: '/other/endpoint',
        statusCode: 404,
      );
      expect(hit, isNull);
    });

    test('method must match unless *', () {
      expect(
        matchExpectedNetworkResponse(
          rules: [empCardRule],
          method: 'GET',
          url: empCardPath,
          statusCode: 404,
        ),
        isNull,
      );
      expect(
        matchExpectedNetworkResponse(
          rules: [
            ExpectedNetworkResponse(
              method: '*',
              path: empCardPath,
              statusCodes: const [404],
            ),
          ],
          method: 'GET',
          url: empCardPath,
          statusCode: 404,
        ),
        isNotNull,
      );
    });
  });

  group('networkReadableFrom with expected responses', () {
    test('matching 404 is user/expected and not issue or alert worthy', () {
      final r = networkReadableFrom(
        {
          'method': 'POST',
          'url': empCardPath,
          'statusCode': 404,
        },
        expectedResponses: [empCardRule],
      );
      expect(r['faultClass'], 'user');
      expect(r['faultKind'], 'expected');
      expect(r['alertWorthy'], isFalse);
      expect(r['issueWorthy'], isFalse);
      expect(r['faultLabel'], contains('Employee has no card image'));
    });

    test('non-matching 404 stays critical endpoint_missing', () {
      final r = networkReadableFrom(
        {
          'method': 'GET',
          'url': '/api/missing',
          'statusCode': 404,
        },
        expectedResponses: [empCardRule],
      );
      expect(r['faultClass'], 'critical');
      expect(r['faultKind'], 'endpoint_missing');
      expect(r['alertWorthy'], isTrue);
      expect(r['issueWorthy'], isTrue);
    });

    test('expected rule overrides client-supplied readable fault', () {
      final r = networkReadableFrom(
        {
          'method': 'POST',
          'url': empCardPath,
          'statusCode': 404,
          'readable': {
            'faultClass': 'critical',
            'faultKind': 'endpoint_missing',
            'alertWorthy': true,
            'issueWorthy': true,
          },
        },
        expectedResponses: [empCardRule],
      );
      expect(r['faultKind'], 'expected');
      expect(r['alertWorthy'], isFalse);
      expect(r['issueWorthy'], isFalse);
    });
  });

  group('ProjectSdkConfig expectedNetworkResponses', () {
    test('legacy settings without the field still load', () {
      final sdk = ProjectSdkConfig.fromJson({
        'enabledLevels': ['error'],
      });
      expect(sdk.expectedNetworkRules, isEmpty);
    });

    test('round-trips expected rules', () {
      final sdk = ProjectSdkConfig(
        expectedNetworkResponses: [empCardRule],
      );
      final parsed = ProjectSdkConfig.fromJson(sdk.toJson());
      expect(parsed.expectedNetworkRules, hasLength(1));
      expect(parsed.expectedNetworkRules.first.path, empCardPath);
      expect(parsed.expectedNetworkRules.first.statusCodes, [404]);
    });

    test('upsert is idempotent', () {
      final once = upsertExpectedNetworkResponse([], empCardRule);
      final twice = upsertExpectedNetworkResponse(once, empCardRule);
      expect(twice, hasLength(1));
    });
  });
}
