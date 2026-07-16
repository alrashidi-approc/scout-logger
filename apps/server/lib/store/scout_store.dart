import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:scout_models/scout_models.dart';

import '../db/scout_db.dart';
import '../notifications/notification_service.dart';
import '../services/geo_enricher.dart';
import '../services/key_cipher.dart';
import '../util/dates.dart';
import '../util/event_filters.dart';
import '../util/event_trend.dart';
import '../util/ids.dart';
import '../util/identity_rollups.dart';
import '../util/insights.dart';
import '../util/user_identity.dart';

const _sessionIdleMinutes = 5;

bool _qualifiesForIssue(String type, Map<String, dynamic> payload) {
  final level = (payload['level']?.toString() ?? '').toLowerCase();
  if (level == 'info' || level == 'success') return false;
  if (type == 'error' || type == 'crash') return true;
  if (type != 'network') return false;
  final network = payload['network'];
  if (network is Map) {
    final n = Map<String, dynamic>.from(network);
    final fault = NetworkFaultInfo.fromJson(_asMap(n['readable'])['fault']) ?? classifyNetworkFault(n);
    if (!fault.issueWorthy) return false;
    final err = network['error'];
    if (err != null && err.toString().isNotEmpty) return true;
    final code = int.tryParse('${network['statusCode'] ?? ''}');
    if (code != null) return code >= 400;
  }
  return level == 'error' || level == 'warning';
}

Map<String, dynamic> _asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<String>? _normalizedEnvFilter(List<String>? environments) {
  if (environments == null || environments.isEmpty || environments.contains('*')) return null;
  final envs = environments.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet().toList();
  return envs.isEmpty ? null : envs;
}

/// Result of grouping an event into an issue.
class IssueUpsert {
  const IssueUpsert({required this.id, required this.muted, required this.regression});

  /// Issue is muted (status `ignored`) — suppress notifications.
  final bool muted;

  /// Resolved issue reopened by this event — a regression worth alerting on.
  final bool regression;
  final String id;
}

Map<String, dynamic> _payloadWithNetworkReadable(
  Map<String, dynamic> payload,
  String type, {
  Map<int, NetworkFaultClass>? faultOverrides,
}) {
  if (type != 'network' || payload['network'] is! Map) return payload;
  final network = Map<String, dynamic>.from(payload['network'] as Map);
  network['readable'] = networkReadableFrom(network, faultOverrides: faultOverrides);
  return {...payload, 'network': network};
}

class ScoutStore {
  ScoutStore(this.db, {KeyCipher? cipher, NotificationService? notifications})
      : _cipher = cipher,
        _notifications = notifications;

  final ScoutDb db;
  final KeyCipher? _cipher;
  final NotificationService? _notifications;

  Future<Map<String, dynamic>?> findProjectByIngestKey(String rawKey) async {
    final conn = await db.connect();
    final hash = hashIngestKey(rawKey);
    final rows = await conn.execute(
      Sql.named('''
        SELECT p.id, p.name, p.slug, k.id AS key_id
        FROM ingest_keys k
        JOIN projects p ON p.id = k.project_id
        WHERE k.key_hash = @hash AND k.revoked_at IS NULL
        LIMIT 1
      '''),
      parameters: {'hash': hash},
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {
      'projectId': r[0] as String,
      'name': r[1] as String,
      'slug': r[2] as String,
      'keyId': r[3] as String,
    };
  }

  Future<Map<String, dynamic>> createProject({
    required String name,
    required String publicUrl,
  }) async {
    final conn = await db.connect();
    final id = newId();
    final slug = slugify(name);
    final rawKey = generateIngestKey();
    final keyId = newId();
    final ciphertext = _cipher?.encrypt(rawKey);

    await conn.execute(
      Sql.named('INSERT INTO projects (id, name, slug) VALUES (@id, @name, @slug)'),
      parameters: {'id': id, 'name': name, 'slug': slug.isEmpty ? id.substring(0, 8) : slug},
    );
    await conn.execute(
      Sql.named('''
        INSERT INTO ingest_keys (id, project_id, key_hash, label, key_ciphertext)
        VALUES (@kid, @pid, @hash, @label, @cipher)
      '''),
      parameters: {
        'kid': keyId,
        'pid': id,
        'hash': hashIngestKey(rawKey),
        'label': 'default',
        'cipher': ciphertext,
      },
    );

    return {
      'id': id,
      'name': name,
      'slug': slug,
      'dsn': buildDsn(publicUrl: publicUrl, projectId: id, rawKey: rawKey),
      'ingestKey': rawKey,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<List<Map<String, dynamic>>> listProjects({String? userId, bool admin = false}) async {
    final conn = await db.connect();
    final Result rows;
    if (admin) {
      rows = await conn.execute('''
        SELECT p.id, p.name, p.slug, p.created_at,
               (SELECT COUNT(*)::int FROM events e WHERE e.project_id = p.id AND NOT (e.type = 'session' AND COALESCE(e.payload->>'action', '') = 'heartbeat')),
               (SELECT COUNT(*)::int FROM issues i WHERE i.project_id = p.id),
               (SELECT MAX(occurred_at) FROM events e WHERE e.project_id = p.id AND NOT (e.type = 'session' AND COALESCE(e.payload->>'action', '') = 'heartbeat')),
               NULL::text
        FROM projects p
        ORDER BY p.created_at DESC
      ''');
    } else if (userId != null) {
      rows = await conn.execute(
        Sql.named('''
        SELECT p.id, p.name, p.slug, p.created_at,
               (SELECT COUNT(*)::int FROM events e WHERE e.project_id = p.id AND NOT (e.type = 'session' AND COALESCE(e.payload->>'action', '') = 'heartbeat')),
               (SELECT COUNT(*)::int FROM issues i WHERE i.project_id = p.id),
               (SELECT MAX(occurred_at) FROM events e WHERE e.project_id = p.id AND NOT (e.type = 'session' AND COALESCE(e.payload->>'action', '') = 'heartbeat')),
               m.role
        FROM projects p
        INNER JOIN project_memberships m ON m.project_id = p.id AND m.user_id = @uid
        ORDER BY p.created_at DESC
      '''),
        parameters: {'uid': userId},
      );
    } else {
      return [];
    }
    return rows.map(_projectRow).toList();
  }

  Map<String, dynamic> _projectRow(ResultRow r) => {
        'id': r[0],
        'name': r[1],
        'slug': r[2],
        'createdAt': (r[3] as DateTime).toUtc().toIso8601String(),
        'eventCount': r[4],
        'issueCount': r[5],
        'lastEventAt': r[6] != null ? (r[6] as DateTime).toUtc().toIso8601String() : null,
        if (r.length > 7 && r[7] != null) 'role': r[7],
      };

  Future<Map<String, dynamic>?> getProjectCredentials(String projectId, {required String publicUrl}) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT key_ciphertext FROM ingest_keys
        WHERE project_id = @pid AND revoked_at IS NULL
        ORDER BY created_at ASC LIMIT 1
      '''),
      parameters: {'pid': projectId},
    );
    if (rows.isEmpty) return null;
    final rawKey = _cipher?.decrypt(rows.first[0] as String?);
    if (rawKey == null) return {'available': false, 'message': 'Credentials unavailable for legacy keys. Create a new project or contact admin.'};
    return {
      'available': true,
      'ingestKey': rawKey,
      'dsn': buildDsn(publicUrl: publicUrl, projectId: projectId, rawKey: rawKey),
    };
  }

  Future<bool> projectExists(String projectId) async {
    final conn = await db.connect();
    final rows = await conn.execute(Sql.named('SELECT 1 FROM projects WHERE id = @id'), parameters: {'id': projectId});
    return rows.isNotEmpty;
  }

  Future<Map<String, dynamic>?> fetchProjectById(String projectId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT p.id, p.name, p.slug, p.created_at,
               (SELECT COUNT(*)::int FROM events e WHERE e.project_id = p.id AND NOT (e.type = 'session' AND COALESCE(e.payload->>'action', '') = 'heartbeat')),
               (SELECT COUNT(*)::int FROM issues i WHERE i.project_id = p.id),
               (SELECT MAX(occurred_at) FROM events e WHERE e.project_id = p.id AND NOT (e.type = 'session' AND COALESCE(e.payload->>'action', '') = 'heartbeat'))
        FROM projects p WHERE p.id = @id
      '''),
      parameters: {'id': projectId},
    );
    if (rows.isEmpty) return null;
    return _projectRow(rows.first);
  }

  Future<Map<String, dynamic>?> getProject(String projectId, {String? userId, bool admin = false}) async {
    if (admin) return fetchProjectById(projectId);
    if (userId != null) {
      for (final p in await listProjects(userId: userId)) {
        if (p['id'] == projectId) return p;
      }
      return null;
    }
    return fetchProjectById(projectId);
  }

  Future<bool> deleteProject(String projectId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('DELETE FROM projects WHERE id = @id RETURNING id'),
      parameters: {'id': projectId},
    );
    return rows.isNotEmpty;
  }

  /// Delete ingest data in [window] — events, sessions, daily stats, and derived rows.
  Future<Map<String, int>> purgeProjectData(String projectId, {required TimeWindow window}) async {
    if (window.since == null) throw ArgumentError('purge window requires since');
    final conn = await db.connect();
    final tp = timeParams(window);
    final fromDate = window.since!.substring(0, 10);
    final untilDate = trendUntilDate(window);

    await conn.execute('BEGIN');
    try {
      final events = await conn.execute(
        Sql.named('''
          DELETE FROM events
          WHERE project_id = @pid
            AND occurred_at >= @since::timestamptz
            AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
          RETURNING id
        '''),
        parameters: {'pid': projectId, ...tp},
      );

      final sessions = await conn.execute(
        Sql.named('''
          DELETE FROM app_sessions
          WHERE project_id = @pid
            AND started_at >= @since::timestamptz
            AND (@until::timestamptz IS NULL OR started_at < @until::timestamptz)
          RETURNING id
        '''),
        parameters: {'pid': projectId, ...tp},
      );

      final stats = await conn.execute(
        Sql.named('''
          DELETE FROM daily_stats
          WHERE project_id = @pid
            AND date >= @fromDate::date
            AND (@untilDate::date IS NULL OR date < @untilDate::date)
          RETURNING date
        '''),
        parameters: {'pid': projectId, 'fromDate': fromDate, 'untilDate': untilDate},
      );

      await conn.execute(
        Sql.named('''
          DELETE FROM user_daily_stats
          WHERE project_id = @pid
            AND date >= @fromDate::date
            AND (@untilDate::date IS NULL OR date < @untilDate::date)
        '''),
        parameters: {'pid': projectId, 'fromDate': fromDate, 'untilDate': untilDate},
      );

      await conn.execute(
        Sql.named('''
          DELETE FROM device_daily_stats
          WHERE project_id = @pid
            AND date >= @fromDate::date
            AND (@untilDate::date IS NULL OR date < @untilDate::date)
        '''),
        parameters: {'pid': projectId, 'fromDate': fromDate, 'untilDate': untilDate},
      );

      final issues = await conn.execute(
        Sql.named('''
          DELETE FROM issues i
          WHERE i.project_id = @pid
            AND NOT EXISTS (SELECT 1 FROM events e WHERE e.issue_id = i.id)
          RETURNING i.id
        '''),
        parameters: {'pid': projectId},
      );

      await conn.execute(
        Sql.named('''
          UPDATE issues i SET
            event_count = s.cnt,
            first_seen_at = s.first_at,
            last_seen_at = s.last_at,
            affected_users = s.users
          FROM (
            SELECT issue_id,
                   COUNT(*)::int AS cnt,
                   MIN(occurred_at) AS first_at,
                   MAX(occurred_at) AS last_at,
                   COUNT(DISTINCT user_id) FILTER (WHERE user_id IS NOT NULL)::int AS users
            FROM events
            WHERE project_id = @pid AND issue_id IS NOT NULL
            GROUP BY issue_id
          ) s
          WHERE i.id = s.issue_id AND i.project_id = @pid
        '''),
        parameters: {'pid': projectId},
      );

      final users = await conn.execute(
        Sql.named('''
          DELETE FROM user_first_seen ufs
          WHERE ufs.project_id = @pid
            AND NOT EXISTS (
              SELECT 1 FROM events e
              WHERE e.project_id = @pid AND e.user_id = ufs.user_id
            )
          RETURNING ufs.user_id
        '''),
        parameters: {'pid': projectId},
      );

      await conn.execute(
        Sql.named('''
          DELETE FROM user_stats us
          WHERE us.project_id = @pid
            AND NOT EXISTS (
              SELECT 1 FROM events e
              WHERE e.project_id = @pid AND e.user_id = us.user_id
            )
        '''),
        parameters: {'pid': projectId},
      );

      await conn.execute(
        Sql.named('''
          DELETE FROM device_stats ds
          WHERE ds.project_id = @pid
            AND NOT EXISTS (
              SELECT 1 FROM events e
              WHERE e.project_id = @pid AND e.install_id = ds.install_id
            )
        '''),
        parameters: {'pid': projectId},
      );

      await conn.execute(
        Sql.named('''
          DELETE FROM user_device_links l
          WHERE l.project_id = @pid
            AND NOT EXISTS (
              SELECT 1 FROM events e
              WHERE e.project_id = @pid AND e.user_id = l.user_id AND e.install_id = l.install_id
            )
        '''),
        parameters: {'pid': projectId},
      );

      final releases = await conn.execute(
        Sql.named('''
          DELETE FROM releases r
          WHERE r.project_id = @pid
            AND NOT EXISTS (
              SELECT 1 FROM events e
              WHERE e.project_id = @pid
                AND e.release = r.release
                AND COALESCE(e.environment, 'production') = r.environment
            )
          RETURNING r.release
        '''),
        parameters: {'pid': projectId},
      );

      await conn.execute(
        Sql.named('''
          UPDATE releases r SET
            event_count = s.cnt,
            crash_count = s.crashes,
            first_seen_at = s.first_at,
            last_seen_at = s.last_at
          FROM (
            SELECT release,
                   COALESCE(environment, 'production') AS env,
                   COUNT(*)::int AS cnt,
                   COUNT(*) FILTER (WHERE type = 'crash')::int AS crashes,
                   MIN(occurred_at) AS first_at,
                   MAX(occurred_at) AS last_at
            FROM events
            WHERE project_id = @pid AND release IS NOT NULL AND $sqlHideSessionHeartbeat
            GROUP BY release, COALESCE(environment, 'production')
          ) s
          WHERE r.project_id = @pid AND r.release = s.release AND r.environment = s.env
        '''),
        parameters: {'pid': projectId},
      );

      await conn.execute('COMMIT');
      return {
        'deletedEvents': events.length,
        'deletedSessions': sessions.length,
        'deletedDailyStats': stats.length,
        'deletedIssues': issues.length,
        'deletedUserRows': users.length,
        'deletedReleases': releases.length,
      };
    } catch (e) {
      await conn.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<Map<String, List<String>>> eventFilterFacets(
    String projectId, {
    TimeWindow? window,
    String? environment,
    String? appVersion,
    String? deviceName,
  }) async {
    final conn = await db.connect();
    final w = window ?? TimeWindow.lastDays(30);
    final time = timeParams(w);
    final timeScope = '''
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)''';
    final envRows = await conn.execute(
      Sql.named('''
        SELECT DISTINCT ${sqlEnvironmentExpr()} AS environment
        FROM events WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          $timeScope
          ${sqlEventFacetFilters(applyEnvironment: false)}
        ORDER BY 1
      '''),
      parameters: eventFacetParameters(
        projectId: projectId,
        time: time,
        environment: environment,
        appVersion: appVersion,
        deviceName: deviceName,
        applyEnvironment: false,
      ),
    );
    final verRows = await conn.execute(
      Sql.named('''
        SELECT DISTINCT ${sqlAppVersionExpr()} AS app_version
        FROM events
        WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND ${sqlAppVersionExpr()} IS NOT NULL
          AND ${sqlAppVersionExpr()} <> ''
          $timeScope
          ${sqlEventFacetFilters(applyAppVersion: false)}
        ORDER BY 1 DESC
        LIMIT 50
      '''),
      parameters: eventFacetParameters(
        projectId: projectId,
        time: time,
        environment: environment,
        appVersion: appVersion,
        deviceName: deviceName,
        applyAppVersion: false,
      ),
    );
    final deviceRows = await conn.execute(
      Sql.named('''
        SELECT DISTINCT ${sqlDeviceNameExpr()} AS device_name
        FROM events
        WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND ${sqlDeviceNameExpr()} IS NOT NULL
          AND ${sqlDeviceNameExpr()} <> ''
          $timeScope
          ${sqlEventFacetFilters(applyDevice: false)}
        ORDER BY 1
        LIMIT 50
      '''),
      parameters: eventFacetParameters(
        projectId: projectId,
        time: time,
        environment: environment,
        appVersion: appVersion,
        deviceName: deviceName,
        applyDevice: false,
      ),
    );
    return {
      'environments': envRows.map((r) => r[0] as String).toList(),
      'appVersions': verRows.map((r) => r[0] as String).toList(),
      'deviceNames': deviceRows.map((r) => r[0] as String).toList(),
    };
  }

  Future<Map<String, dynamic>> ingestBatch({
    required String projectId,
    required String keyId,
    required List<IngestEvent> events,
    required Map<String, dynamic> enrichment,
  }) async {
    final conn = await db.connect();
    await closeStaleSessions(projectId: projectId, conn: conn);
    final faultOverrides = await _networkFaultOverrides(conn, projectId);
    ProjectNotificationConfig? notifConfig;
    PlatformNotificationPolicy? platformPolicy;
    final notifications = _notifications;
    if (notifications != null) {
      notifConfig = await notifications.store.getConfig(projectId);
      platformPolicy = await notifications.platformStore.getNotificationPolicy();
    }
    var accepted = 0;
    for (final event in events) {
      if (!isKnownEventType(event.type)) continue;
      await _ingestOne(
        conn,
        projectId: projectId,
        keyId: keyId,
        event: event,
        enrichment: enrichment,
        faultOverrides: faultOverrides,
        notifConfig: notifConfig,
        platformPolicy: platformPolicy,
      );
      accepted++;
    }
    return {'accepted': accepted, 'total': events.length};
  }

  Future<Map<int, NetworkFaultClass>> _networkFaultOverrides(Connection conn, String projectId) async {
    final rows = await conn.execute(
      Sql.named('SELECT settings FROM projects WHERE id = @id'),
      parameters: {'id': projectId},
    );
    if (rows.isEmpty) return const {};
    final raw = rows.first[0];
    final settings = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final sdkJson = settings['sdk'];
    final sdk = ProjectSdkConfig.fromJson(sdkJson is Map ? Map<String, dynamic>.from(sdkJson) : null);
    return sdk.networkFaultOverrides;
  }

  Future<void> _ingestOne(
    Connection conn, {
    required String projectId,
    required String keyId,
    required IngestEvent event,
    required Map<String, dynamic> enrichment,
    Map<int, NetworkFaultClass>? faultOverrides,
    ProjectNotificationConfig? notifConfig,
    PlatformNotificationPolicy? platformPolicy,
  }) async {
    final payload = _payloadWithNetworkReadable(event.payload, event.type, faultOverrides: faultOverrides);
    final occurredAt = DateTime.tryParse(event.timestamp)?.toUtc() ?? DateTime.now().toUtc();
    final user = payload['user'] is Map ? Map<String, dynamic>.from(payload['user'] as Map) : <String, dynamic>{};
    final device = payload['device'] is Map ? Map<String, dynamic>.from(payload['device'] as Map) : <String, dynamic>{};
    final userId = user['id']?.toString() ?? user['userId']?.toString();
    final installId = installIdFromPayload(payload);
    final sessionId = user['sessionId']?.toString() ??
        payload['sessionId']?.toString() ??
        (payload['session'] is Map ? (payload['session'] as Map)['id']?.toString() : null);
    final release = releaseFromPayload(payload);
    final environment = payload['environment']?.toString() ??
        (payload['release'] is Map ? (payload['release'] as Map)['environment']?.toString() : null) ??
        'production';
    final platform = device['platform']?.toString();
    final releaseMap = payload['release'] is Map ? Map<String, dynamic>.from(payload['release'] as Map) : null;
    final appVersion = composeAppVersionFromDevice(device, release: releaseMap) ??
        device['appVersion']?.toString() ??
        device['version']?.toString();

    if (isSessionHeartbeat(event.type, payload)) {
      await _trackAppSession(
        conn,
        projectId: projectId,
        userId: userId,
        payload: payload,
        occurredAt: occurredAt,
      );
      return;
    }

    final message = payload['message']?.toString() ??
        (event.type == 'session' ? 'session ${payload['action'] ?? ''}'.trim() : null);
    final ipGeo = GeoLookup.fromJson(enrichment['geo']);
    final resolved = GeoEnricher.resolveForEvent(device: device, ipGeo: ipGeo);
    final country = resolved.geo.country;
    final region = ipGeo.region ?? resolved.geo.region;
    final city = ipGeo.city ?? resolved.geo.city;
    final eventEnrichment = {
      ...enrichment,
      'geo': resolved.toEnrichmentJson(),
    };

    String? issueId;
    String? fingerprint;
    var issueMuted = false;
    var issueRegression = false;
    if (groupsIntoIssue(event.type) && _qualifiesForIssue(event.type, payload)) {
      fingerprint = eventFingerprint(event.type, payload);
      final upsert = await _upsertIssue(
        conn,
        projectId: projectId,
        fingerprint: fingerprint,
        type: event.type,
        title: eventTitle(event.type, payload),
        occurredAt: occurredAt,
        userId: userId,
        installId: installId,
        country: country,
      );
      issueId = upsert.id;
      issueMuted = upsert.muted;
      issueRegression = upsert.regression;
    }

    final eventId = newId();
    await conn.execute(
      Sql.named('''
        INSERT INTO events (
          id, project_id, issue_id, type, occurred_at,
          user_id, session_id, install_id, release, environment, platform, app_version,
          country, region, city, message, payload, enrichment
        ) VALUES (
          @id, @pid, @iid, @type, @at,
          @uid, @sid, @iid_install, @rel, @env, @plat, @aver,
          @country, @region, @city, @msg, @payload::jsonb, @enrich::jsonb
        )
      '''),
      parameters: {
        'id': eventId,
        'pid': projectId,
        'iid': issueId,
        'type': event.type,
        'at': occurredAt,
        'uid': userId,
        'sid': sessionId,
        'iid_install': installId,
        'rel': release,
        'env': environment,
        'plat': platform,
        'aver': appVersion,
        'country': country,
        'region': region,
        'city': city,
        'msg': message,
        'payload': jsonEncode(payload),
        'enrich': jsonEncode({...eventEnrichment, 'ingestKeyId': keyId}),
      },
    );

    final notifications = _notifications;
    if (notifications != null && notifConfig != null && platformPolicy != null && !issueMuted) {
      fingerprint ??= (event.type == 'error' || event.type == 'crash' || event.type == 'network')
          ? eventFingerprint(event.type, payload)
          : null;
      await notifications.onEventIngested(
        projectId: projectId,
        eventId: eventId,
        issueId: issueId,
        type: event.type,
        environment: environment,
        message: message,
        payload: payload,
        fingerprint: fingerprint,
        regression: issueRegression,
        notifications: notifConfig,
        platform: platformPolicy,
      );
    }

    if (event.type == 'session') {
      await _trackAppSession(
        conn,
        projectId: projectId,
        userId: userId,
        payload: payload,
        occurredAt: occurredAt,
      );
    }

    if (userId != null && isIdentifiedAppUser(userId: userId, installId: installId)) {
      await conn.execute(
        Sql.named('''
          INSERT INTO user_first_seen (project_id, user_id, first_seen_at, first_country)
          VALUES (@pid, @uid, @at, @country)
          ON CONFLICT (project_id, user_id) DO NOTHING
        '''),
        parameters: {'pid': projectId, 'uid': userId, 'at': occurredAt, 'country': country},
      );
    }

    if (release != null) {
      final isCrash = event.type == 'crash';
      await conn.execute(
        Sql.named('''
          INSERT INTO releases (project_id, release, environment, first_seen_at, last_seen_at, event_count, crash_count)
          VALUES (@pid, @rel, @env, @at, @at, 1, @crash)
          ON CONFLICT (project_id, release, environment) DO UPDATE SET
            last_seen_at = GREATEST(releases.last_seen_at, EXCLUDED.last_seen_at),
            event_count = releases.event_count + 1,
            crash_count = releases.crash_count + EXCLUDED.crash_count
        '''),
        parameters: {
          'pid': projectId,
          'rel': release,
          'env': environment,
          'at': occurredAt,
          'crash': isCrash ? 1 : 0,
        },
      );
    }

    final day = occurredAt.toIso8601String().substring(0, 10);
    final errFlag = isErrorEvent(event.type, payload) ? 1 : 0;
    final crashFlag = event.type == 'crash' ? 1 : 0;
    await conn.execute(
      Sql.named('''
        INSERT INTO daily_stats (project_id, date, country, events_total, errors, crashes, unique_users)
        VALUES (@pid, @day::date, @country, 1, @err, @crash, @uu)
        ON CONFLICT (project_id, date, country) DO UPDATE SET
          events_total = daily_stats.events_total + 1,
          errors = daily_stats.errors + EXCLUDED.errors,
          crashes = daily_stats.crashes + EXCLUDED.crashes
      '''),
      parameters: {
        'pid': projectId,
        'day': day,
        'country': country ?? '',
        'err': errFlag,
        'crash': crashFlag,
        'uu': 0,
      },
    );

    await upsertIdentityRollups(
      conn,
      projectId: projectId,
      occurredAt: occurredAt,
      type: event.type,
      payload: payload,
      userId: userId,
      installId: installId,
      platform: platform,
      appVersion: appVersion,
      environment: environment,
      release: release,
      country: country,
    );
  }

  Future<IssueUpsert> _upsertIssue(
    Connection conn, {
    required String projectId,
    required String fingerprint,
    required String type,
    required String title,
    required DateTime occurredAt,
    String? userId,
    String? installId,
    String? country,
  }) async {
    final existing = await conn.execute(
      Sql.named('SELECT id, status FROM issues WHERE project_id = @pid AND fingerprint = @fp'),
      parameters: {'pid': projectId, 'fp': fingerprint},
    );

    if (existing.isNotEmpty) {
      final id = existing.first[0] as String;
      final status = existing.first[1] as String? ?? 'open';
      final muted = status == 'ignored';
      final regression = status == 'resolved';
      await conn.execute(
        Sql.named('''
          UPDATE issues SET
            last_seen_at = GREATEST(last_seen_at, @at),
            event_count = event_count + 1,
            title = COALESCE(NULLIF(@title, ''), title),
            top_country = COALESCE(top_country, @country),
            status = CASE WHEN status = 'resolved' THEN 'open' ELSE status END,
            regressed_at = CASE WHEN status = 'resolved' THEN @at ELSE regressed_at END
          WHERE id = @id
        '''),
        parameters: {'id': id, 'at': occurredAt, 'title': title, 'country': country},
      );
      return IssueUpsert(id: id, muted: muted, regression: regression);
    }

    final id = newId();
    await conn.execute(
      Sql.named('''
        INSERT INTO issues (
          id, project_id, fingerprint, type, title, first_seen_at, last_seen_at,
          event_count, affected_users, top_country
        ) VALUES (@id, @pid, @fp, @type, @title, @at, @at, 1, @au, @country)
      '''),
      parameters: {
        'id': id,
        'pid': projectId,
        'fp': fingerprint,
        'type': type,
        'title': title,
        'at': occurredAt,
        'au': isIdentifiedAppUser(userId: userId, installId: installId) ? 1 : 0,
        'country': country,
      },
    );
    return IssueUpsert(id: id, muted: false, regression: false);
  }

  Future<List<Map<String, dynamic>>> listIssues(
    String projectId, {
    int limit = 100,
    String? type,
    String? status,
    String? q,
    String? environment,
    String? appVersion,
    String? deviceName,
    int? days,
    TimeWindow? window,
  }) async {
    final conn = await db.connect();
    final w = window ?? (days == null ? TimeWindow.all : TimeWindow.lastDays(days));
    final facetScope = sqlIssueEventScope();
    final facetActive = hasEventFacetFilters(environment: environment, appVersion: appVersion, deviceName: deviceName);
    final issueTimeClause = facetActive
        ? ''
        : '''
          AND (@since::timestamptz IS NULL OR last_seen_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR last_seen_at < @until::timestamptz)''';
    final rows = await conn.execute(
      Sql.named('''
        SELECT id, fingerprint, type, title, status, event_count, affected_users,
               first_seen_at, last_seen_at, top_country,
               (SELECT COALESCE(NULLIF(e.payload->>'level', ''), 'error')
                FROM events e WHERE ${sqlIssueEventScope()}
                ORDER BY e.occurred_at DESC LIMIT 1) AS level,
               (SELECT e.payload->'network'->>'statusCode'
                FROM events e WHERE ${sqlIssueEventScope()}
                ORDER BY e.occurred_at DESC LIMIT 1) AS status_code,
               (SELECT COUNT(*)::int
                FROM events e
                WHERE ${sqlIssueEventScope()}
               ) AS period_events,
               (SELECT device FROM (
                  SELECT ${sqlDeviceNameExpr(alias: 'e2')} AS device, COUNT(*)::int AS c
                  FROM events e2
                  WHERE ${sqlIssueEventScope(alias: 'e2')}
                    AND ${sqlDeviceNameExpr(alias: 'e2')} IS NOT NULL AND ${sqlDeviceNameExpr(alias: 'e2')} <> ''
                  GROUP BY device ORDER BY c DESC LIMIT 1
                ) d) AS top_device,
               (SELECT COUNT(DISTINCT e.user_id)::int
                FROM events e
                WHERE ${sqlIssueEventScope()}
                  AND e.user_id IS NOT NULL AND e.user_id <> ''
               ) AS period_users
        FROM issues WHERE project_id = @pid
          AND EXISTS (
            SELECT 1 FROM events e
            WHERE ${sqlIssueEventScope()}
          )
          AND (@type::text IS NULL OR type = @type::text)
          AND (@status::text IS NULL OR status = @status::text)
          AND (
            @q::text IS NULL
            OR title ILIKE '%' || @q::text || '%'
            OR EXISTS (
              SELECT 1 FROM events e WHERE e.project_id = @pid AND e.issue_id = issues.id
                AND (e.message ILIKE '%' || @q::text || '%'
                  OR e.payload->>'stack' ILIKE '%' || @q::text || '%'
                  OR e.payload->'network'->>'url' ILIKE '%' || @q::text || '%')
            )
          )
          $issueTimeClause
        ORDER BY last_seen_at DESC LIMIT @lim
      '''),
      parameters: {
        'pid': projectId,
        'lim': limit,
        'type': type,
        'status': status,
        'q': q,
        'env': environment,
        'ver': appVersion,
        'device': deviceName,
        ...timeParams(w),
      },
    );
    return rows
        .map((r) {
          final totalEvents = r[5] as int;
          final periodEvents = r[12] as int;
          final periodUsers = (r[14] as int?) ?? 0;
          final inPeriod = w.since != null;
          final lastSeen = r[8] as DateTime;
          final sev = computeIssueSeverity(
            eventCount: facetActive || inPeriod ? periodEvents : totalEvents,
            affectedUsers: facetActive ? periodUsers : (r[6] as int?) ?? 0,
            hoursSinceLastSeen: DateTime.now().toUtc().difference(lastSeen.toUtc()).inHours,
            isCrash: r[2] == 'crash',
          );
          return {
              'id': r[0],
              'fingerprint': r[1],
              'type': r[2],
              'title': r[3],
              'status': r[4],
              'eventCount': facetActive || inPeriod ? periodEvents : totalEvents,
              if (inPeriod && !facetActive) 'totalEventCount': totalEvents,
              'affectedUsers': facetActive ? periodUsers : (r[6] as int?) ?? 0,
              'firstSeenAt': (r[7] as DateTime).toUtc().toIso8601String(),
              'lastSeenAt': lastSeen.toUtc().toIso8601String(),
              'topCountry': r[9],
              'level': r[10],
              if (r[11] != null) 'statusCode': r[11],
              if (r[13] != null) 'topDevice': r[13],
              'severity': sev.severity,
            };
        })
        .toList();
  }

  Future<Map<String, dynamic>?> getIssue(String projectId, String issueId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT i.id, i.project_id, i.fingerprint, i.type, i.title, i.status, i.first_seen_at, i.last_seen_at,
               i.event_count, i.affected_users, i.top_country, i.assignee_user_id, u.email, u.display_name
        FROM issues i
        LEFT JOIN dashboard_users u ON u.id = i.assignee_user_id
        WHERE i.project_id = @pid AND i.id = @id
      '''),
      parameters: {'pid': projectId, 'id': issueId},
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final issue = {
      'id': r[0],
      'projectId': r[1],
      'fingerprint': r[2],
      'type': r[3],
      'title': r[4],
      'status': r[5],
      'firstSeenAt': (r[6] as DateTime).toUtc().toIso8601String(),
      'lastSeenAt': (r[7] as DateTime).toUtc().toIso8601String(),
      'eventCount': r[8],
      'affectedUsers': r[9],
      'topCountry': r[10],
      if (r[11] != null) 'assigneeUserId': r[11],
      if (r[11] != null) 'assigneeEmail': r[12],
      if (r[11] != null) 'assigneeName': r[13],
    };
    issue['notes'] = await listIssueNotes(projectId, issueId);
    final events = await conn.execute(
      Sql.named('''
        SELECT id, type, occurred_at, user_id, release, country, message, payload, enrichment
        FROM events e WHERE project_id = @pid AND issue_id = @iid AND ${sqlIsErrorEvent(alias: 'e')}
        ORDER BY occurred_at DESC LIMIT 20
      '''),
      parameters: {'pid': projectId, 'iid': issueId},
    );
    issue['events'] = events.map(_eventRow).toList();
    issue['geoBreakdown'] = await _issueGeo(conn, projectId, issueId);
    issue['deviceBreakdown'] = await _issueDevices(conn, projectId, issueId);
    issue['insights'] = await _issueInsights(conn, projectId, issueId, issue);
    return issue;
  }

  /// Zero-cost heuristics: stack culprit, dominant correlations, severity score.
  Future<Map<String, dynamic>> _issueInsights(
    Connection conn,
    String projectId,
    String issueId,
    Map<String, dynamic> issue,
  ) async {
    final correlations = <Map<String, dynamic>>[];
    for (final (col, label) in [
      ('app_version', 'App version'),
      ('platform', 'Platform'),
      ('country', 'Country'),
      ('environment', 'Environment'),
    ]) {
      final c = await _topCorrelation(conn, projectId, issueId, col);
      if (c != null && c.ratio >= 0.6 && c.value != 'unknown') {
        correlations.add({'label': label, 'value': c.value, 'ratio': c.ratio, 'count': c.count});
      }
    }

    final culprit = await _stackCulprit(conn, projectId, issueId);

    final last = DateTime.tryParse(issue['lastSeenAt'] as String? ?? '');
    final sev = computeIssueSeverity(
      eventCount: (issue['eventCount'] as int?) ?? 0,
      affectedUsers: (issue['affectedUsers'] as int?) ?? 0,
      hoursSinceLastSeen: last == null ? 9999 : DateTime.now().toUtc().difference(last).inHours,
      isCrash: (issue['type'] as String?) == 'crash',
    );

    return {
      'severity': sev.severity,
      'severityReasons': sev.reasons,
      if (culprit != null) 'culprit': culprit,
      'correlations': correlations,
    };
  }

  Future<({String value, double ratio, int count})?> _topCorrelation(
    Connection conn,
    String projectId,
    String issueId,
    String column,
  ) async {
    final rows = await conn.execute(
      Sql.named('''
        SELECT COALESCE(NULLIF($column, ''), 'unknown') AS v,
               COUNT(*)::int AS c,
               SUM(COUNT(*)) OVER ()::int AS total
        FROM events e
        WHERE project_id = @pid AND issue_id = @iid AND ${sqlIsErrorEvent(alias: 'e')}
        GROUP BY v ORDER BY c DESC LIMIT 1
      '''),
      parameters: {'pid': projectId, 'iid': issueId},
    );
    if (rows.isEmpty) return null;
    final value = rows.first[0] as String;
    final count = (rows.first[1] as int?) ?? 0;
    final total = (rows.first[2] as int?) ?? 0;
    if (total == 0) return null;
    return (value: value, ratio: count / total, count: count);
  }

  Future<String?> _stackCulprit(Connection conn, String projectId, String issueId) async {
    final rows = await conn.execute(
      Sql.named('''
        SELECT COALESCE(payload->>'stack', payload->>'stackTrace')
        FROM events e
        WHERE project_id = @pid AND issue_id = @iid
          AND (payload ? 'stack' OR payload ? 'stackTrace')
        ORDER BY occurred_at DESC LIMIT 1
      '''),
      parameters: {'pid': projectId, 'iid': issueId},
    );
    if (rows.isEmpty || rows.first[0] == null) return null;
    return stackCulpritFromTrace(rows.first[0] as String);
  }

  Future<Map<String, dynamic>?> updateIssueStatus(String projectId, String issueId, String status) async {
    if (!{'open', 'resolved', 'ignored'}.contains(status)) {
      throw ArgumentError('Invalid status');
    }
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        UPDATE issues SET
          status = @status,
          resolved_at = CASE WHEN @status = 'resolved' THEN now() ELSE NULL END
        WHERE project_id = @pid AND id = @id
        RETURNING id
      '''),
      parameters: {'pid': projectId, 'id': issueId, 'status': status},
    );
    if (rows.isEmpty) return null;
    return getIssue(projectId, issueId);
  }

  /// Error + crash event counts in the last [minutes] (for spike detection).
  Future<({int errors, int crashes})> incidentCounts(
    String projectId, {
    required int minutes,
    List<String>? environments,
  }) async {
    final envs = _normalizedEnvFilter(environments);
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT
          COUNT(*) FILTER (WHERE ${sqlIsErrorEvent(alias: 'e')})::int AS errors,
          COUNT(*) FILTER (WHERE type = 'crash')::int AS crashes
        FROM events e
        WHERE project_id = @pid
          AND occurred_at >= now() - (@mins::text || ' minutes')::interval
          ${envs == null ? '' : 'AND lower(environment) = ANY(@envs)'}
      '''),
      parameters: {
        'pid': projectId,
        'mins': minutes,
        if (envs != null) 'envs': envs,
      },
    );
    final r = rows.first;
    return (errors: (r[0] as int?) ?? 0, crashes: (r[1] as int?) ?? 0);
  }

  /// Per-window counts for the current window (index 0) plus [lookback] prior
  /// windows, for anomaly detection. Returns both metrics as count lists where
  /// index 0 is the most recent (current) window.
  Future<({List<int> errors, List<int> crashes})> windowedCounts(
    String projectId, {
    required int windowMinutes,
    int lookback = 24,
    List<String>? environments,
  }) async {
    final envs = _normalizedEnvFilter(environments);
    final conn = await db.connect();
    final total = windowMinutes * (lookback + 1);
    final rows = await conn.execute(
      Sql.named('''
        SELECT
          floor(extract(epoch from (now() - occurred_at)) / (@win * 60))::int AS bucket,
          COUNT(*) FILTER (WHERE ${sqlIsErrorEvent(alias: 'e')})::int AS errors,
          COUNT(*) FILTER (WHERE type = 'crash')::int AS crashes
        FROM events e
        WHERE project_id = @pid
          AND occurred_at >= now() - (@total::text || ' minutes')::interval
          ${envs == null ? '' : 'AND lower(environment) = ANY(@envs)'}
        GROUP BY bucket
      '''),
      parameters: {
        'pid': projectId,
        'win': windowMinutes,
        'total': total,
        if (envs != null) 'envs': envs,
      },
    );
    final errors = List<int>.filled(lookback + 1, 0);
    final crashes = List<int>.filled(lookback + 1, 0);
    for (final r in rows) {
      final bucket = (r[0] as int?) ?? -1;
      if (bucket < 0 || bucket > lookback) continue;
      errors[bucket] = (r[1] as int?) ?? 0;
      crashes[bucket] = (r[2] as int?) ?? 0;
    }
    return (errors: errors, crashes: crashes);
  }

  /// Top issues by event volume in the last [hours] + regression count (for digests).
  Future<({List<Map<String, dynamic>> issues, int regressions, int newIssues})> digestData(
    String projectId, {
    required int hours,
    int limit = 10,
  }) async {
    final conn = await db.connect();
    final top = await conn.execute(
      Sql.named('''
        SELECT i.id, i.title, i.type, COUNT(e.id)::int AS c,
          (SELECT v.app_ver FROM (
              SELECT ${sqlAppVersionExpr(alias: 'e2')} AS app_ver,
                     COUNT(*)::int AS vc
              FROM events e2
              WHERE e2.project_id = @pid AND e2.issue_id = i.id AND ${sqlIsErrorEvent(alias: 'e2')}
                AND e2.occurred_at >= now() - (@hrs::text || ' hours')::interval
              GROUP BY 1
            ) v
            WHERE v.app_ver IS NOT NULL AND v.app_ver <> ''
            ORDER BY v.vc DESC LIMIT 1
          ) AS top_version
        FROM issues i
        JOIN events e ON e.issue_id = i.id AND e.project_id = @pid AND ${sqlIsErrorEvent(alias: 'e')}
          AND e.occurred_at >= now() - (@hrs::text || ' hours')::interval
        WHERE i.project_id = @pid
        GROUP BY i.id, i.title, i.type
        ORDER BY c DESC LIMIT @lim
      '''),
      parameters: {'pid': projectId, 'hrs': hours, 'lim': limit},
    );
    final counts = await conn.execute(
      Sql.named('''
        SELECT
          COUNT(*) FILTER (WHERE regressed_at >= now() - (@hrs::text || ' hours')::interval)::int,
          COUNT(*) FILTER (WHERE first_seen_at >= now() - (@hrs::text || ' hours')::interval)::int
        FROM issues WHERE project_id = @pid
      '''),
      parameters: {'pid': projectId, 'hrs': hours},
    );
    return (
      issues: top
          .map((r) => {
                'id': r[0],
                'title': r[1],
                'type': r[2],
                'count': r[3],
                'version': r[4] as String?,
              })
          .toList(),
      regressions: (counts.first[0] as int?) ?? 0,
      newIssues: (counts.first[1] as int?) ?? 0,
    );
  }

  /// Update issue status by id alone (used by Slack action callbacks).
  /// Returns the issue title + project on success.
  Future<({String projectId, String title})?> updateIssueStatusById(String issueId, String status) async {
    if (!{'open', 'resolved', 'ignored'}.contains(status)) throw ArgumentError('Invalid status');
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        UPDATE issues SET
          status = @status,
          resolved_at = CASE WHEN @status = 'resolved' THEN now() ELSE NULL END
        WHERE id = @id
        RETURNING project_id, title
      '''),
      parameters: {'id': issueId, 'status': status},
    );
    if (rows.isEmpty) return null;
    return (projectId: rows.first[0] as String, title: rows.first[1] as String? ?? 'Issue');
  }

  /// Assign (or unassign when [userId] is null) an issue to a project member.
  Future<Map<String, dynamic>?> assignIssue(String projectId, String issueId, String? userId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('UPDATE issues SET assignee_user_id = @uid WHERE project_id = @pid AND id = @id RETURNING id'),
      parameters: {'pid': projectId, 'id': issueId, 'uid': userId},
    );
    if (rows.isEmpty) return null;
    return getIssue(projectId, issueId);
  }

  Future<List<Map<String, dynamic>>> listIssueNotes(String projectId, String issueId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT n.id, n.body, n.created_at, n.author_id, u.email, u.display_name
        FROM issue_notes n
        LEFT JOIN dashboard_users u ON u.id = n.author_id
        WHERE n.project_id = @pid AND n.issue_id = @iid
        ORDER BY n.created_at ASC
      '''),
      parameters: {'pid': projectId, 'iid': issueId},
    );
    return rows
        .map((r) => {
              'id': r[0],
              'body': r[1],
              'createdAt': (r[2] as DateTime).toUtc().toIso8601String(),
              'authorId': r[3],
              'authorEmail': r[4],
              'authorName': r[5],
            })
        .toList();
  }

  Future<Map<String, dynamic>?> addIssueNote(String projectId, String issueId, String? authorId, String body) async {
    final text = body.trim();
    if (text.isEmpty) throw ArgumentError('Note cannot be empty');
    final conn = await db.connect();
    final exists = await conn.execute(
      Sql.named('SELECT 1 FROM issues WHERE project_id = @pid AND id = @id'),
      parameters: {'pid': projectId, 'id': issueId},
    );
    if (exists.isEmpty) return null;
    final id = newId();
    await conn.execute(
      Sql.named('''
        INSERT INTO issue_notes (id, project_id, issue_id, author_id, body)
        VALUES (@id, @pid, @iid, @aid, @body)
      '''),
      parameters: {'id': id, 'pid': projectId, 'iid': issueId, 'aid': authorId, 'body': text},
    );
    final rows = await conn.execute(
      Sql.named('''
        SELECT n.id, n.body, n.created_at, n.author_id, u.email, u.display_name
        FROM issue_notes n LEFT JOIN dashboard_users u ON u.id = n.author_id
        WHERE n.id = @id
      '''),
      parameters: {'id': id},
    );
    final r = rows.first;
    return {
      'id': r[0],
      'body': r[1],
      'createdAt': (r[2] as DateTime).toUtc().toIso8601String(),
      'authorId': r[3],
      'authorEmail': r[4],
      'authorName': r[5],
    };
  }

  Future<Map<String, dynamic>?> getEvent(String projectId, String eventId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT id, type, occurred_at, issue_id, user_id, session_id, install_id, release, environment,
               platform, app_version, country, region, city, message, payload, enrichment, created_at
        FROM events WHERE project_id = @pid AND id = @eid LIMIT 1
      '''),
      parameters: {'pid': projectId, 'eid': eventId},
    );
    if (rows.isEmpty) return null;
    final event = _eventRowFull(rows.first);
    final issueId = event['issueId'] as String?;
    if (issueId != null) {
      final issue = await getIssue(projectId, issueId);
      if (issue != null) {
        event['issue'] = {
          'id': issue['id'],
          'title': issue['title'],
          'type': issue['type'],
          'status': issue['status'],
          'eventCount': issue['eventCount'],
          'fingerprint': issue['fingerprint'],
          'firstSeenAt': issue['firstSeenAt'],
          'lastSeenAt': issue['lastSeenAt'],
        };
      }
      final related = await conn.execute(
        Sql.named('''
          SELECT id, type, occurred_at, message, country
          FROM events WHERE project_id = @pid AND issue_id = @iid AND id != @eid
          ORDER BY occurred_at DESC LIMIT 8
        '''),
        parameters: {'pid': projectId, 'iid': issueId, 'eid': eventId},
      );
      event['relatedEvents'] = related
          .map((r) => {
                'id': r[0],
                'type': r[1],
                'occurredAt': (r[2] as DateTime).toUtc().toIso8601String(),
                'message': r[3],
                'country': r[4],
              })
          .toList();
    }
    final occurredAt = DateTime.parse(event['occurredAt'] as String).toUtc();
    event['sessionEvents'] = await _sessionEventsAround(
      conn,
      projectId: projectId,
      eventId: eventId,
      occurredAt: occurredAt,
      sessionId: event['sessionId'] as String?,
      userId: event['userId'] as String?,
      installId: event['installId'] as String?,
    );
    return event;
  }

  Future<List<Map<String, dynamic>>> _sessionEventsAround(
    Connection conn, {
    required String projectId,
    required String eventId,
    required DateTime occurredAt,
    String? sessionId,
    String? userId,
    String? installId,
  }) async {
    final from = occurredAt.subtract(const Duration(minutes: 5));
    final to = occurredAt.add(const Duration(minutes: 1));
    const limit = 40;

    final hasSession = sessionId != null && sessionId.isNotEmpty;
    final hasUser = userId != null && userId.isNotEmpty;
    final hasInstall = installId != null && installId.isNotEmpty;
    if (!hasSession && !hasUser && !hasInstall) return [];

    final rows = await conn.execute(
      Sql.named('''
        SELECT id, type, occurred_at, message, country,
               payload->>'level' AS level,
               payload->'screen'->>'currentRoute' AS route,
               payload->'network'->>'url' AS network_url,
               payload->'network'->>'statusCode' AS status_code,
               payload->>'category' AS category
        FROM events
        WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND occurred_at >= @from AND occurred_at <= @to
          AND (
            (@sid::text IS NOT NULL AND session_id = @sid::text)
            OR (
              @sid::text IS NULL
              AND (
                (@uid::text IS NOT NULL AND user_id = @uid::text)
                OR (@iid::text IS NOT NULL AND install_id = @iid::text)
              )
            )
          )
        ORDER BY occurred_at ASC
        LIMIT @lim
      '''),
      parameters: {
        'pid': projectId,
        'sid': hasSession ? sessionId : null,
        'uid': hasSession ? null : (hasUser ? userId : null),
        'iid': hasSession ? null : (hasInstall ? installId : null),
        'from': from,
        'to': to,
        'lim': limit,
      },
    );

    return rows
        .map((r) => _compactEventRow(r, highlightId: eventId))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listSessionEvents(
    String projectId,
    String sessionId, {
    int limit = 200,
  }) async {
    if (sessionId.isEmpty) return [];
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT id, type, occurred_at, message, country,
               payload->>'level' AS level,
               payload->'screen'->>'currentRoute' AS route,
               payload->'network'->>'url' AS network_url,
               payload->'network'->>'statusCode' AS status_code,
               payload->>'category' AS category
        FROM events
        WHERE project_id = @pid AND session_id = @sid AND $sqlHideSessionHeartbeat
        ORDER BY occurred_at ASC
        LIMIT @lim
      '''),
      parameters: {'pid': projectId, 'sid': sessionId, 'lim': limit.clamp(1, 500)},
    );
    return rows.map((r) => _compactEventRow(r)).toList();
  }

  Future<Map<String, dynamic>> sdkHealth(String projectId, {TimeWindow? window}) async {
    final conn = await db.connect();
    final w = window ?? TimeWindow.lastDays(7);
    // Full SDK health scans JSON on every event — too slow for Overview. Use a cheap signal.
    if (preferIdentityRollups(w)) {
      // Skip expensive JSON coverage scan on Overview (was a major wait).
      return const <String, dynamic>{};
    }
    final tp = timeParams(w);

    final totals = await conn.execute(
      Sql.named('''
        SELECT
          COUNT(*)::int,
          COUNT(*) FILTER (WHERE session_id IS NOT NULL AND session_id <> '')::int,
          COUNT(*) FILTER (WHERE install_id IS NOT NULL AND install_id <> '')::int,
          COUNT(*) FILTER (
            WHERE jsonb_array_length(COALESCE(payload->'screenTrail', payload->'breadcrumbs', '[]'::jsonb)) > 0
          )::int,
          COUNT(*) FILTER (
            WHERE EXISTS (
              SELECT 1
              FROM jsonb_array_elements(COALESCE(payload->'screenTrail', payload->'breadcrumbs', '[]'::jsonb)) elem
              WHERE COALESCE(elem->>'navigationType', elem->>'navType', elem->>'transition', elem->>'action') IS NOT NULL
            )
          )::int
        FROM events
        WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
      '''),
      parameters: {'pid': projectId, ...tp},
    );

    final levels = await conn.execute(
      Sql.named('''
        SELECT
          LOWER(COALESCE(NULLIF(payload->>'level', ''),
            CASE type WHEN 'log' THEN 'info' WHEN 'span' THEN 'info' ELSE 'error' END
          )) AS level,
          COUNT(*)::int
        FROM events
        WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY 1 ORDER BY 2 DESC
      '''),
      parameters: {'pid': projectId, ...tp},
    );

    final types = await conn.execute(
      Sql.named('''
        SELECT type, COUNT(*)::int
        FROM events
        WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY type ORDER BY 2 DESC
      '''),
      parameters: {'pid': projectId, ...tp},
    );

    int n(dynamic v) => v == null ? 0 : (v is int ? v : (v as num).toInt());
    double pct(int part, int total) => total == 0 ? 100 : (part * 1000 / total).round() / 10;

    final t = totals.first;
    final total = n(t[0]);
    final withSession = n(t[1]);
    final withInstall = n(t[2]);
    final withTrail = n(t[3]);
    final withNav = n(t[4]);

    final hints = <String>[];
    if (total == 0) {
      hints.add('No events in this period — verify the app DSN and ingest key.');
    } else {
      if (pct(withSession, total) < 80) {
        hints.add('${pct(withSession, total)}% of events have session_id — SDK should attach sessionId on every event.');
      }
      if (pct(withInstall, total) < 80) {
        hints.add('${pct(withInstall, total)}% of events have install_id — needed for guest → logged-in merge.');
      }
      if (pct(withTrail, total) < 50) {
        hints.add('${pct(withTrail, total)}% include screenTrail — enable navigation tracking in SDK settings.');
      }
      if (pct(withNav, total) < 40 && withTrail > 0) {
        hints.add('${pct(withNav, total)}% of trails include navigationType — update SDK screenTrail steps.');
      }
      final byLevel = {for (final r in levels) r[0] as String: n(r[1])};
      if ((byLevel['success'] ?? 0) == 0 && (byLevel['info'] ?? 0) == 0) {
        hints.add('No info/success logs — check enabledLevels and networkLogScope in project settings.');
      }
    }

    return {
      'total': total,
      'withSession': withSession,
      'withInstall': withInstall,
      'withScreenTrail': withTrail,
      'withNavigationType': withNav,
      'withSessionPct': pct(withSession, total),
      'withInstallPct': pct(withInstall, total),
      'withScreenTrailPct': pct(withTrail, total),
      'withNavigationTypePct': pct(withNav, total),
      'byLevel': {for (final r in levels) r[0] as String: n(r[1])},
      'byType': {for (final r in types) r[0] as String: n(r[1])},
      'hints': hints,
    };
  }

  Map<String, dynamic> _compactEventRow(ResultRow r, {String? highlightId}) => {
        'id': r[0],
        'type': r[1],
        'occurredAt': (r[2] as DateTime).toUtc().toIso8601String(),
        'message': r[3],
        'country': r[4],
        'level': r[5],
        'route': r[6],
        'networkUrl': r[7],
        'statusCode': r[8]?.toString(),
        'category': r[9],
        if (highlightId != null) 'isCurrent': r[0] == highlightId,
      };

  Future<Map<String, dynamic>> listEvents(
    String projectId, {
    int limit = 50,
    int offset = 0,
    String? type,
    String? level,
    String? category,
    String? q,
    String? country,
    String? environment,
    String? appVersion,
    String? deviceName,
    int? days,
    TimeWindow? window,
  }) async {
    final conn = await db.connect();
    final w = window ?? (days == null ? TimeWindow.all : TimeWindow.lastDays(days));
    final kind = type;
    final lim = limit.clamp(1, 100);
    final off = offset < 0 ? 0 : offset;
    final filters = '''
        FROM events WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND (
            @kind::text IS NULL
            OR (@kind::text = 'errors' AND ${sqlIsErrorEvent()})
            OR (@kind::text <> 'errors' AND type = @kind::text)
          )
          AND (
            @level::text IS NULL
            OR LOWER(COALESCE(NULLIF(payload->>'level', ''),
                CASE type WHEN 'log' THEN 'info' WHEN 'span' THEN 'info' ELSE 'error' END
              )) = LOWER(@level::text)
          )
          AND (@category::text IS NULL OR payload->>'category' = @category::text)
          AND (
            @q::text IS NULL
            OR message ILIKE '%' || @q::text || '%'
            OR user_id ILIKE '%' || @q::text || '%'
            OR session_id ILIKE '%' || @q::text || '%'
            OR payload->'network'->>'traceId' ILIKE '%' || @q::text || '%'
            OR payload->'network'->>'url' ILIKE '%' || @q::text || '%'
            OR payload->>'stack' ILIKE '%' || @q::text || '%'
            OR payload->>'stackTrace' ILIKE '%' || @q::text || '%'
            OR ${sqlDeviceNameExpr()} ILIKE '%' || @q::text || '%'
          )
          AND (@country::text IS NULL OR country = @country::text)
          ${sqlEventFacetFilters()}
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
    ''';
    final params = {
      'pid': projectId,
      'kind': kind,
      'level': level,
      'category': category,
      'q': q,
      'country': country,
      'env': environment,
      'ver': appVersion,
      'device': deviceName,
      ...timeParams(w),
    };
    final total = (await conn.execute(Sql.named('SELECT COUNT(*)::int $filters'), parameters: params)).first[0] as int;
    final rows = await conn.execute(
      Sql.named('''
        SELECT id, type, occurred_at, issue_id, user_id, release, country, message,
               platform, environment, app_version,
               payload->'screen'->>'currentRoute' AS route,
               COALESCE(payload->'device'->>'deviceName', payload->'device'->>'model') AS device_name,
               payload->'network'->>'url' AS network_url,
               payload->'network'->>'statusCode' AS status_code,
               payload->>'category' AS category,
               payload->>'level' AS level,
               payload->'device'->>'buildNumber' AS build_number
        $filters
        ORDER BY occurred_at DESC LIMIT @lim OFFSET @off
      '''),
      parameters: {...params, 'lim': lim, 'off': off},
    );
    final events = rows
        .map((r) {
          final ver = r[10] as String?;
          final build = r[17]?.toString();
          return {
              'id': r[0],
              'type': r[1],
              'occurredAt': (r[2] as DateTime).toUtc().toIso8601String(),
              'issueId': r[3],
              'userId': r[4],
              'release': r[5],
              'country': r[6],
              'message': r[7],
              'platform': r[8],
              'environment': r[9],
              'appVersion': composeAppVersion(appVersion: ver, buildNumber: build) ?? ver,
              if (build != null && build.isNotEmpty) 'buildNumber': build,
              'route': r[11],
              'deviceName': r[12],
              'networkUrl': r[13],
              'statusCode': r[14]?.toString(),
              'category': r[15],
              'level': r[16],
            };
        })
        .toList();
    return {
      'events': events,
      'total': total,
      'limit': lim,
      'offset': off,
      'hasMore': off + events.length < total,
    };
  }

  Future<Map<String, dynamic>> projectOverview(String projectId, {int days = 1, TimeWindow? window, bool includeTrend = true}) async {
    final conn = await db.connect();
    await closeStaleSessions(projectId: projectId, conn: conn);
    final project = await fetchProjectById(projectId);
    if (project == null) throw ArgumentError('Project not found');

    final w = window ?? TimeWindow.lastDays(days);
    final tp = timeParams(w);
    final dp = dateParams(w);
    final periodDays = w.approximateDays;
    final useRollups = preferIdentityRollups(w);

    final stats = useRollups
        ? await conn.execute(
            Sql.named('''
              SELECT
                COALESCE(SUM(events_total), 0)::int,
                COALESCE(SUM(errors), 0)::int,
                COALESCE(SUM(crashes), 0)::int
              FROM daily_stats
              WHERE project_id = @pid
                AND (@fromDate::date IS NULL OR date >= @fromDate::date)
                AND (@untilDate::date IS NULL OR date < @untilDate::date)
            '''),
            parameters: {'pid': projectId, ...dp},
          )
        : await conn.execute(
            Sql.named('''
              SELECT
                COUNT(*)::int,
                COUNT(*) FILTER (WHERE ${sqlIsErrorEvent()})::int,
                COUNT(*) FILTER (WHERE type = 'crash')::int
              FROM events
              WHERE project_id = @pid
                AND $sqlHideSessionHeartbeat
                AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
                AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
            '''),
            parameters: {'pid': projectId, ...tp},
          );

    final uniqueUsers = useRollups
        ? await conn.execute(
            Sql.named('''
              SELECT COUNT(DISTINCT user_id)::int
              FROM user_daily_stats
              WHERE project_id = @pid
                AND (@fromDate::date IS NULL OR date >= @fromDate::date)
                AND (@untilDate::date IS NULL OR date < @untilDate::date)
            '''),
            parameters: {'pid': projectId, ...dp},
          )
        : await conn.execute(
            Sql.named('''
              SELECT COUNT(DISTINCT user_id) FILTER (WHERE ${identifiedUserSql()})::int
              FROM events
              WHERE project_id = @pid
                AND $sqlHideSessionHeartbeat
                AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
                AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
            '''),
            parameters: {'pid': projectId, ...tp},
          );
    final s = stats.first;
    final uniqueUserCount = uniqueUsers.first[0];

    final openRows = await conn.execute(
      Sql.named("SELECT type, event_count, affected_users, last_seen_at FROM issues WHERE project_id = @pid AND status = 'open'"),
      parameters: {'pid': projectId},
    );
    final nowUtc = DateTime.now().toUtc();
    var openCount = 0;
    var highSeverity = 0;
    for (final r in openRows) {
      openCount++;
      final sev = computeIssueSeverity(
        eventCount: (r[1] as int?) ?? 0,
        affectedUsers: (r[2] as int?) ?? 0,
        hoursSinceLastSeen: nowUtc.difference((r[3] as DateTime).toUtc()).inHours,
        isCrash: r[0] == 'crash',
      );
      if (sev.severity == 'high') highSeverity++;
    }

    final sessions = await conn.execute(
      Sql.named('''
        SELECT
          (SELECT COUNT(*)::int FROM app_sessions
            WHERE project_id = @pid AND ended_at IS NULL
              AND COALESCE(last_seen_at, started_at) >= (now() AT TIME ZONE 'utc') - make_interval(mins => $_sessionIdleMinutes)),
          (SELECT AVG(duration_ms)::int FROM app_sessions
            WHERE project_id = @pid AND ended_at IS NOT NULL
              AND (@since::timestamptz IS NULL OR started_at >= @since::timestamptz)
              AND (@until::timestamptz IS NULL OR started_at < @until::timestamptz)),
          (SELECT COUNT(*)::int FROM app_sessions
            WHERE project_id = @pid AND ended_at IS NOT NULL
              AND (@since::timestamptz IS NULL OR started_at >= @since::timestamptz)
              AND (@until::timestamptz IS NULL OR started_at < @until::timestamptz))
      '''),
      parameters: {'pid': projectId, ...tp},
    );
    final sess = sessions.first;

    final countries = useRollups
        ? await conn.execute(
            Sql.named('''
              SELECT country, SUM(events_total)::int AS c
              FROM daily_stats
              WHERE project_id = @pid AND country <> ''
                AND (@fromDate::date IS NULL OR date >= @fromDate::date)
                AND (@untilDate::date IS NULL OR date < @untilDate::date)
              GROUP BY country ORDER BY c DESC LIMIT 10
            '''),
            parameters: {'pid': projectId, ...dp},
          )
        : await conn.execute(
            Sql.named('''
              SELECT country, COUNT(*)::int AS c
              FROM events
              WHERE project_id = @pid AND country IS NOT NULL
                AND $sqlHideSessionHeartbeat
                AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
                AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
              GROUP BY country ORDER BY c DESC LIMIT 10
            '''),
            parameters: {'pid': projectId, ...tp},
          );

    final releases = await conn.execute(
      Sql.named('''
        SELECT release, environment, event_count, crash_count, last_seen_at
        FROM releases WHERE project_id = @pid ORDER BY last_seen_at DESC LIMIT 10
      '''),
      parameters: {'pid': projectId},
    );

    final trendWindow = w.usesHourlyTrend
        ? w
        : (w.since != null
            ? w
            : TimeWindow(since: '${utcDateDaysAgo((periodDays > 14 ? periodDays : 14) - 1)}T00:00:00.000Z'));
    final trend = includeTrend ? await fetchEventTrend(conn, projectId, trendWindow) : const <Map<String, dynamic>>[];

    return {
      'project': project,
      'days': periodDays,
      'eventsToday': _i(s[0]),
      'errorsToday': _i(s[1]),
      'crashesToday': _i(s[2]),
      'uniqueUsersToday': _i(uniqueUserCount),
      'activeSessions': _i(sess[0]),
      'avgSessionDurationMs': sess[1] == null ? null : _i(sess[1]),
      'sessionsCompletedToday': _i(sess[2]),
      'uniqueUsers7d': _i(uniqueUserCount),
      'openIssues': openCount,
      'highSeverityIssues': highSeverity,
      'topCountries': countries.map((r) => {'country': r[0], 'count': r[1]}).toList(),
      'trendGranularity': trendGranularity(w),
      'dailyTrend': trend,
      'byRelease': releases
          .map((r) => {
                'release': r[0],
                'environment': r[1],
                'eventCount': r[2],
                'crashCount': r[3],
                'lastSeenAt': (r[4] as DateTime).toUtc().toIso8601String(),
              })
          .toList(),
    };
  }

  Future<List<Map<String, dynamic>>> geoBreakdown(String projectId, {int days = 7, TimeWindow? window}) async {
    final conn = await db.connect();
    final w = window ?? TimeWindow.lastDays(days);
    final rows = await conn.execute(
      Sql.named('''
        SELECT country,
               COUNT(*)::int,
               COUNT(DISTINCT user_id) FILTER (WHERE ${identifiedUserSql()} )::int,
               COUNT(*) FILTER (WHERE enrichment->'geo'->>'source' IN ('locale', 'device_locale'))::int,
               COUNT(*) FILTER (WHERE enrichment->'geo'->>'source' IN ('ip', 'local_ip'))::int,
               COUNT(*) FILTER (WHERE enrichment->'geo'->>'source' = 'profile')::int
        FROM events
        WHERE project_id = @pid AND country IS NOT NULL
          AND $sqlHideSessionHeartbeat
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY country
        ORDER BY COUNT(DISTINCT user_id) FILTER (WHERE ${identifiedUserSql()} ) DESC,
                 COUNT(*) DESC
      '''),
      parameters: {'pid': projectId, ...timeParams(w)},
    );
    return rows
        .map((r) {
          final localeEvents = r[3] as int;
          final ipEvents = r[4] as int;
          final profileEvents = r[5] as int;
          return {
            'country': r[0],
            'count': r[1],
            'users': r[2],
            'localeEvents': localeEvents,
            'ipEvents': ipEvents,
            'profileEvents': profileEvents,
            'countrySource': _geoSourceLabel(localeEvents, ipEvents, profileEvents),
          };
        })
        .toList();
  }

  static String _geoSourceLabel(int localeEvents, int ipEvents, int profileEvents) {
    final total = localeEvents + ipEvents + profileEvents;
    if (total == 0) return 'unknown';
    if (profileEvents == total) return 'profile';
    if (ipEvents == total) return 'ip';
    if (localeEvents == total) return 'locale';
    if (ipEvents >= localeEvents && ipEvents >= profileEvents) {
      return ipEvents == total ? 'ip' : 'mostly_ip';
    }
    if (profileEvents >= localeEvents && profileEvents >= ipEvents) {
      return profileEvents == total ? 'profile' : 'mostly_profile';
    }
    return 'mixed';
  }

  Future<List<Map<String, dynamic>>> _issueDevices(Connection conn, String projectId, String issueId) async {
    final rows = await conn.execute(
      Sql.named('''
        SELECT ${sqlDeviceNameExpr(alias: 'e')} AS device,
               COUNT(*)::int,
               COUNT(DISTINCT install_id) FILTER (WHERE install_id IS NOT NULL)::int
        FROM events e
        WHERE project_id = @pid AND issue_id = @iid AND ${sqlIsErrorEvent(alias: 'e')}
          AND ${sqlDeviceNameExpr(alias: 'e')} IS NOT NULL AND ${sqlDeviceNameExpr(alias: 'e')} <> ''
        GROUP BY device ORDER BY COUNT(*) DESC
      '''),
      parameters: {'pid': projectId, 'iid': issueId},
    );
    return rows.map((r) => {'device': r[0], 'count': r[1], 'installs': r[2]}).toList();
  }

  Future<List<Map<String, dynamic>>> _issueGeo(Connection conn, String projectId, String issueId) async {
    final rows = await conn.execute(
      Sql.named('''
        SELECT country, COUNT(*)::int FROM events e
        WHERE project_id = @pid AND issue_id = @iid AND country IS NOT NULL AND ${sqlIsErrorEvent(alias: 'e')}
        GROUP BY country ORDER BY COUNT(*) DESC
      '''),
      parameters: {'pid': projectId, 'iid': issueId},
    );
    return rows.map((r) => {'country': r[0], 'count': r[1]}).toList();
  }

  Map<String, dynamic> _eventRow(ResultRow r) {
    final payload = _jsonField(r[7]);
    final device = payload['device'] is Map ? Map<String, dynamic>.from(payload['device'] as Map) : <String, dynamic>{};
    final deviceName = device['deviceName']?.toString() ?? device['deviceModel']?.toString() ?? device['model']?.toString();
    return {
      'id': r[0],
      'type': r[1],
      'occurredAt': (r[2] as DateTime).toUtc().toIso8601String(),
      'userId': r[3],
      'release': r[4],
      'country': r[5],
      'message': r[6],
      'payload': payload,
      'enrichment': _jsonField(r[8]),
      if (deviceName != null) 'deviceName': deviceName,
      if (device['platform'] != null) 'platform': device['platform'],
    };
  }

  Map<String, dynamic> _eventRowFull(ResultRow r) => {
        'id': r[0],
        'type': r[1],
        'occurredAt': (r[2] as DateTime).toUtc().toIso8601String(),
        'issueId': r[3],
        'userId': r[4],
        'sessionId': r[5],
        'installId': r[6],
        'release': r[7],
        'environment': r[8],
        'platform': r[9],
        'appVersion': r[10],
        'country': r[11],
        'region': r[12],
        'city': r[13],
        'message': r[14],
        'payload': _jsonField(r[15]),
        'enrichment': _jsonField(r[16]),
        'createdAt': (r[17] as DateTime).toUtc().toIso8601String(),
      };

  dynamic _jsonField(dynamic value) {
    if (value is String) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return value;
      }
    }
    return value;
  }

  int _i(dynamic v) => v == null ? 0 : (v is int ? v : (v as num).toInt());

  Future<int> closeStaleSessions({String? projectId, Connection? conn}) async {
    final c = conn ?? await db.connect();
    final rows = await c.execute(
      Sql.named('''
        UPDATE app_sessions SET
          ended_at = COALESCE(last_seen_at, started_at),
          duration_ms = GREATEST(0, EXTRACT(EPOCH FROM (COALESCE(last_seen_at, started_at) - started_at)) * 1000)::int
        WHERE ended_at IS NULL
          AND (@pid::text IS NULL OR project_id = @pid::text)
          AND COALESCE(last_seen_at, started_at) < (now() AT TIME ZONE 'utc') - make_interval(mins => @mins)
        RETURNING id
      '''),
      parameters: {'pid': projectId, 'mins': _sessionIdleMinutes},
    );
    return rows.length;
  }

  Future<void> _trackAppSession(
    Connection conn, {
    required String projectId,
    String? userId,
    required Map<String, dynamic> payload,
    required DateTime occurredAt,
  }) async {
    final action = payload['action']?.toString();
    final sid = payload['sessionId']?.toString();
    if (sid == null || action == null) return;

    if (action == 'start') {
      await conn.execute(
        Sql.named('''
          INSERT INTO app_sessions (id, project_id, user_id, started_at, last_seen_at)
          VALUES (@id, @pid, @uid, @at, @at)
          ON CONFLICT (id) DO UPDATE SET
            last_seen_at = GREATEST(app_sessions.last_seen_at, EXCLUDED.last_seen_at),
            user_id = COALESCE(app_sessions.user_id, EXCLUDED.user_id)
        '''),
        parameters: {'id': sid, 'pid': projectId, 'uid': userId, 'at': occurredAt},
      );
      return;
    }

    if (action == 'heartbeat') {
      await conn.execute(
        Sql.named('''
          UPDATE app_sessions SET
            last_seen_at = @at,
            user_id = COALESCE(user_id, @uid)
          WHERE id = @id AND project_id = @pid AND ended_at IS NULL
        '''),
        parameters: {'id': sid, 'pid': projectId, 'uid': userId, 'at': occurredAt},
      );
      return;
    }

    if (action == 'end') {
      final durationMs = payload['durationMs'] is int
          ? payload['durationMs'] as int
          : int.tryParse('${payload['durationMs']}');
      await conn.execute(
        Sql.named('''
          UPDATE app_sessions SET
            ended_at = @at,
            last_seen_at = @at,
            duration_ms = COALESCE(@dur, EXTRACT(EPOCH FROM (@at - started_at)) * 1000)::int,
            user_id = COALESCE(user_id, @uid)
          WHERE id = @id AND project_id = @pid
        '''),
        parameters: {'id': sid, 'pid': projectId, 'uid': userId, 'at': occurredAt, 'dur': durationMs},
      );
    }
  }

  Future<Map<String, dynamic>> getProjectSettings(String projectId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('SELECT settings FROM projects WHERE id = @id'),
      parameters: {'id': projectId},
    );
    if (rows.isEmpty) throw ArgumentError('Project not found');
    final raw = rows.first[0];
    final settings = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return ProjectRemoteConfig.fromSettings(settings).toClientResponse();
  }

  Future<Map<String, dynamic>> getClientConfig(String projectId) async => getProjectSettings(projectId);

  Future<int> getConfigVersion(String projectId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named("SELECT COALESCE((settings->>'configVersion')::int, 1) FROM projects WHERE id = @id"),
      parameters: {'id': projectId},
    );
    if (rows.isEmpty) return 1;
    return rows.first[0] as int? ?? 1;
  }

  Future<Map<String, dynamic>> updateProjectSettings(String projectId, Map<String, dynamic> patch) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('SELECT settings FROM projects WHERE id = @id FOR UPDATE'),
      parameters: {'id': projectId},
    );
    if (rows.isEmpty) throw ArgumentError('Project not found');
    final raw = rows.first[0];
    final current = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final prev = ProjectRemoteConfig.fromSettings(current);
    final merged = prev.sdk.mergePatch(patch);
    final next = ProjectRemoteConfig(
      configVersion: prev.configVersion + 1,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      sdk: merged,
    );
    await conn.execute(
      Sql.named('UPDATE projects SET settings = @settings::jsonb WHERE id = @id'),
      parameters: {'id': projectId, 'settings': jsonEncode(next.toSettingsJson())},
    );
    return next.toClientResponse();
  }

  Future<void> appendDashboardLog({
    required String projectId,
    String? userId,
    required String level,
    required String message,
    String? route,
    Map<String, dynamic>? context,
  }) async {
    final conn = await db.connect();
    final lvl = {'error', 'warning', 'info'}.contains(level) ? level : 'error';
    await conn.execute(
      Sql.named('''
        INSERT INTO dashboard_logs (id, project_id, user_id, level, message, route, context)
        VALUES (@id, @pid, @uid, @lvl, @msg, @route, @ctx::jsonb)
      '''),
      parameters: {
        'id': newId(),
        'pid': projectId,
        'uid': userId,
        'lvl': lvl,
        'msg': message.length > 4000 ? message.substring(0, 4000) : message,
        'route': route,
        'ctx': jsonEncode(context ?? {}),
      },
    );
  }

  Future<List<Map<String, dynamic>>> listDashboardLogs(
    String projectId, {
    int limit = 100,
    String? level,
  }) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT l.id, l.level, l.message, l.route, l.context, l.created_at, u.email
        FROM dashboard_logs l
        LEFT JOIN dashboard_users u ON u.id = l.user_id
        WHERE l.project_id = @pid
          AND (@lvl::text IS NULL OR l.level = @lvl::text)
        ORDER BY l.created_at DESC
        LIMIT @lim
      '''),
      parameters: {'pid': projectId, 'lvl': level, 'lim': limit.clamp(1, 500)},
    );
    return rows
        .map((r) => {
              'id': r[0],
              'level': r[1],
              'message': r[2],
              'route': r[3],
              'context': r[4] is Map ? Map<String, dynamic>.from(r[4] as Map) : <String, dynamic>{},
              'createdAt': (r[5] as DateTime).toUtc().toIso8601String(),
              'userEmail': r[6],
            })
        .toList();
  }

  Future<String?> projectDisplayName(String projectId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('SELECT name FROM projects WHERE id = @pid'),
      parameters: {'pid': projectId},
    );
    if (rows.isEmpty) return null;
    return rows.first[0] as String;
  }

  Future<Map<String, dynamic>?> createShareToken({
    required String projectId,
    required String resourceType,
    required String resourceId,
    String? createdBy,
    int expiresInDays = 30,
  }) async {
    if (!{'event', 'issue'}.contains(resourceType)) throw ArgumentError('Invalid resource type');

    if (resourceType == 'event') {
      if (await getEvent(projectId, resourceId) == null) return null;
    } else if (await getIssue(projectId, resourceId) == null) {
      return null;
    }

    final token = newToken();
    final expiresAt = DateTime.now().toUtc().add(Duration(days: expiresInDays.clamp(1, 365)));
    final conn = await db.connect();
    await conn.execute(
      Sql.named('''
        INSERT INTO share_tokens (id, project_id, resource_type, resource_id, token_hash, expires_at, created_by)
        VALUES (@id, @pid, @type, @rid, @hash, @exp, @uid)
      '''),
      parameters: {
        'id': newId(),
        'pid': projectId,
        'type': resourceType,
        'rid': resourceId,
        'hash': hashToken(token),
        'exp': expiresAt,
        'uid': createdBy,
      },
    );
    return {
      'token': token,
      'expiresAt': expiresAt.toIso8601String(),
      'resourceType': resourceType,
      'resourceId': resourceId,
    };
  }

  /// Read-only notification link — filters live in [payload], not the URL.
  Future<Map<String, dynamic>?> createAlertShareToken({
    required String projectId,
    required String dedupKey,
    required Map<String, dynamic> payload,
    int expiresInHours = 168,
  }) async {
    final token = newToken();
    final expiresAt = DateTime.now().toUtc().add(Duration(hours: expiresInHours.clamp(1, 8760)));
    final conn = await db.connect();
    await conn.execute(
      Sql.named('''
        INSERT INTO share_tokens (id, project_id, resource_type, resource_id, token_hash, expires_at, payload)
        VALUES (@id, @pid, 'alert', @rid, @hash, @exp, @payload::jsonb)
      '''),
      parameters: {
        'id': newId(),
        'pid': projectId,
        'rid': dedupKey,
        'hash': hashToken(token),
        'exp': expiresAt,
        'payload': jsonEncode(payload),
      },
    );
    return {'token': token, 'expiresAt': expiresAt.toIso8601String()};
  }

  Future<Map<String, dynamic>> createReportShareToken({
    required String projectId,
    required Map<String, dynamic> payload,
    String? createdBy,
    int expiresInDays = 30,
  }) async {
    final token = newToken();
    final expiresAt = DateTime.now().toUtc().add(Duration(days: expiresInDays.clamp(1, 365)));
    final conn = await db.connect();
    await conn.execute(
      Sql.named('''
        INSERT INTO share_tokens (id, project_id, resource_type, resource_id, token_hash, expires_at, created_by, payload)
        VALUES (@id, @pid, 'report', @pid, @hash, @exp, @uid, @payload::jsonb)
      '''),
      parameters: {
        'id': newId(),
        'pid': projectId,
        'hash': hashToken(token),
        'exp': expiresAt,
        'uid': createdBy,
        'payload': jsonEncode(payload),
      },
    );
    return {'token': token, 'expiresAt': expiresAt.toIso8601String()};
  }

  Future<Map<String, dynamic>?> resolveShareToken(String rawToken) async {
    if (rawToken.isEmpty || rawToken.length > 128) return null;
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT project_id, resource_type, resource_id, expires_at, payload
        FROM share_tokens
        WHERE token_hash = @hash AND revoked_at IS NULL AND expires_at > now()
        LIMIT 1
      '''),
      parameters: {'hash': hashToken(rawToken)},
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {
      'projectId': r[0],
      'resourceType': r[1],
      'resourceId': r[2],
      'expiresAt': (r[3] as DateTime).toUtc().toIso8601String(),
      if (r[4] != null) 'payload': r[4],
    };
  }
}
