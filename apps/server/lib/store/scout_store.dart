import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:scout_models/scout_models.dart';

import '../db/scout_db.dart';
import '../services/geo_enricher.dart';
import '../util/dates.dart';
import '../util/ids.dart';

class ScoutStore {
  ScoutStore(this.db);

  final ScoutDb db;

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

    await conn.execute(
      Sql.named('INSERT INTO projects (id, name, slug) VALUES (@id, @name, @slug)'),
      parameters: {'id': id, 'name': name, 'slug': slug.isEmpty ? id.substring(0, 8) : slug},
    );
    await conn.execute(
      Sql.named('''
        INSERT INTO ingest_keys (id, project_id, key_hash, label)
        VALUES (@kid, @pid, @hash, @label)
      '''),
      parameters: {'kid': keyId, 'pid': id, 'hash': hashIngestKey(rawKey), 'label': 'default'},
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

  Future<List<Map<String, dynamic>>> listProjects() async {
    final conn = await db.connect();
    final rows = await conn.execute('''
      SELECT p.id, p.name, p.slug, p.created_at,
             (SELECT COUNT(*)::int FROM events e WHERE e.project_id = p.id),
             (SELECT COUNT(*)::int FROM issues i WHERE i.project_id = p.id),
             (SELECT MAX(occurred_at) FROM events e WHERE e.project_id = p.id)
      FROM projects p
      ORDER BY p.created_at DESC
    ''');
    return rows
        .map((r) => {
              'id': r[0],
              'name': r[1],
              'slug': r[2],
              'createdAt': (r[3] as DateTime).toUtc().toIso8601String(),
              'eventCount': r[4],
              'issueCount': r[5],
              'lastEventAt': r[6] != null ? (r[6] as DateTime).toUtc().toIso8601String() : null,
            })
        .toList();
  }

  Future<Map<String, dynamic>?> getProject(String projectId) async {
    for (final p in await listProjects()) {
      if (p['id'] == projectId) return p;
    }
    return null;
  }

  Future<Map<String, dynamic>> ingestBatch({
    required String projectId,
    required String keyId,
    required List<IngestEvent> events,
    required Map<String, dynamic> enrichment,
  }) async {
    final conn = await db.connect();
    var accepted = 0;
    for (final event in events) {
      if (!isKnownEventType(event.type)) continue;
      await _ingestOne(conn, projectId: projectId, keyId: keyId, event: event, enrichment: enrichment);
      accepted++;
    }
    return {'accepted': accepted, 'total': events.length};
  }

  Future<void> _ingestOne(
    Connection conn, {
    required String projectId,
    required String keyId,
    required IngestEvent event,
    required Map<String, dynamic> enrichment,
  }) async {
    final payload = event.payload;
    final occurredAt = DateTime.tryParse(event.timestamp)?.toUtc() ?? DateTime.now().toUtc();
    final user = payload['user'] is Map ? Map<String, dynamic>.from(payload['user'] as Map) : <String, dynamic>{};
    final device = payload['device'] is Map ? Map<String, dynamic>.from(payload['device'] as Map) : <String, dynamic>{};
    final userId = user['id']?.toString() ?? user['userId']?.toString();
    final sessionId = user['sessionId']?.toString() ??
        payload['sessionId']?.toString() ??
        (payload['session'] is Map ? (payload['session'] as Map)['id']?.toString() : null);
    final release = releaseFromPayload(payload);
    final environment = payload['environment']?.toString() ??
        (payload['release'] is Map ? (payload['release'] as Map)['environment']?.toString() : null) ??
        'production';
    final platform = device['platform']?.toString();
    final appVersion = device['appVersion']?.toString() ?? device['version']?.toString();
    final message = payload['message']?.toString() ??
        (event.type == 'session' ? 'session ${payload['action'] ?? ''}'.trim() : null);
    final ipGeo = GeoLookup.fromJson(enrichment['geo']);
    final resolved = GeoEnricher.resolveForEvent(device, ipGeo);
    final fromDevice = device['countryCode']?.toString().trim().isNotEmpty == true;
    final country = resolved.country;
    final region = fromDevice ? null : resolved.region;
    final city = fromDevice ? null : resolved.city;
    final eventEnrichment = {
      ...enrichment,
      'geo': {
        ...resolved.toJson(),
        'source': fromDevice ? 'device_locale' : (ipGeo.country == 'LO' ? 'local_ip' : 'ip'),
        if (fromDevice && ipGeo.country != null) 'ipGeo': ipGeo.toJson(),
      },
    };

    String? issueId;
    if (groupsIntoIssue(event.type)) {
      final fingerprint = eventFingerprint(event.type, payload);
      issueId = await _upsertIssue(
        conn,
        projectId: projectId,
        fingerprint: fingerprint,
        type: event.type,
        title: eventTitle(event.type, payload),
        occurredAt: occurredAt,
        userId: userId,
        country: country,
      );
    }

    final eventId = newId();
    await conn.execute(
      Sql.named('''
        INSERT INTO events (
          id, project_id, issue_id, type, occurred_at,
          user_id, session_id, release, environment, platform, app_version,
          country, region, city, message, payload, enrichment
        ) VALUES (
          @id, @pid, @iid, @type, @at,
          @uid, @sid, @rel, @env, @plat, @aver,
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

    if (event.type == 'session') {
      await _trackAppSession(
        conn,
        projectId: projectId,
        userId: userId,
        payload: payload,
        occurredAt: occurredAt,
      );
    }

    if (userId != null) {
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
        'err': event.type == 'error' || event.type == 'network' ? 1 : 0,
        'crash': event.type == 'crash' ? 1 : 0,
        'uu': 0,
      },
    );
  }

  Future<String> _upsertIssue(
    Connection conn, {
    required String projectId,
    required String fingerprint,
    required String type,
    required String title,
    required DateTime occurredAt,
    String? userId,
    String? country,
  }) async {
    final existing = await conn.execute(
      Sql.named('SELECT id, affected_users, top_country FROM issues WHERE project_id = @pid AND fingerprint = @fp'),
      parameters: {'pid': projectId, 'fp': fingerprint},
    );

    if (existing.isNotEmpty) {
      final id = existing.first[0] as String;
      await conn.execute(
        Sql.named('''
          UPDATE issues SET
            last_seen_at = GREATEST(last_seen_at, @at),
            event_count = event_count + 1,
            title = COALESCE(NULLIF(@title, ''), title),
            top_country = COALESCE(top_country, @country)
          WHERE id = @id
        '''),
        parameters: {'id': id, 'at': occurredAt, 'title': title, 'country': country},
      );
      return id;
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
        'au': userId != null ? 1 : 0,
        'country': country,
      },
    );
    return id;
  }

  Future<List<Map<String, dynamic>>> listIssues(
    String projectId, {
    int limit = 100,
    String? type,
    String? status,
    String? q,
    int? days,
  }) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT id, fingerprint, type, title, status, event_count, affected_users,
               first_seen_at, last_seen_at, top_country
        FROM issues WHERE project_id = @pid
          AND (@type::text IS NULL OR type = @type::text)
          AND (@status::text IS NULL OR status = @status::text)
          AND (@q::text IS NULL OR title ILIKE '%' || @q::text || '%')
          AND (@since::timestamptz IS NULL OR last_seen_at >= @since::timestamptz)
        ORDER BY last_seen_at DESC LIMIT @lim
      '''),
      parameters: {'pid': projectId, 'lim': limit, 'type': type, 'status': status, 'q': q, 'since': sinceTimestamp(days)},
    );
    return rows
        .map((r) => {
              'id': r[0],
              'fingerprint': r[1],
              'type': r[2],
              'title': r[3],
              'status': r[4],
              'eventCount': r[5],
              'affectedUsers': r[6],
              'firstSeenAt': (r[7] as DateTime).toUtc().toIso8601String(),
              'lastSeenAt': (r[8] as DateTime).toUtc().toIso8601String(),
              'topCountry': r[9],
            })
        .toList();
  }

  Future<Map<String, dynamic>?> getIssue(String projectId, String issueId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT id, project_id, fingerprint, type, title, status, first_seen_at, last_seen_at,
               event_count, affected_users, top_country
        FROM issues WHERE project_id = @pid AND id = @id
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
    };
    final events = await conn.execute(
      Sql.named('''
        SELECT id, type, occurred_at, user_id, release, country, message, payload, enrichment
        FROM events WHERE project_id = @pid AND issue_id = @iid
        ORDER BY occurred_at DESC LIMIT 20
      '''),
      parameters: {'pid': projectId, 'iid': issueId},
    );
    issue['events'] = events.map(_eventRow).toList();
    issue['geoBreakdown'] = await _issueGeo(conn, projectId, issueId);
    return issue;
  }

  Future<Map<String, dynamic>?> getEvent(String projectId, String eventId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT id, type, occurred_at, issue_id, user_id, session_id, release, environment,
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
    return event;
  }

  Future<List<Map<String, dynamic>>> listEvents(
    String projectId, {
    int limit = 100,
    String? type,
    String? q,
    String? country,
    int? days,
  }) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT id, type, occurred_at, issue_id, user_id, release, country, message,
               platform, environment, app_version,
               payload->'screen'->>'currentRoute' AS route,
               COALESCE(payload->'device'->>'deviceName', payload->'device'->>'model') AS device_name,
               payload->'network'->>'url' AS network_url,
               payload->'network'->>'statusCode' AS status_code,
               payload->>'category' AS category,
               payload->>'level' AS level
        FROM events WHERE project_id = @pid
          AND (
            @type::text IS NULL
            OR (@type::text = 'errors' AND type IN ('error', 'network'))
            OR (@type::text <> 'errors' AND type = @type::text)
          )
          AND (@q::text IS NULL OR message ILIKE '%' || @q::text || '%')
          AND (@country::text IS NULL OR country = @country::text)
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
        ORDER BY occurred_at DESC LIMIT @lim
      '''),
      parameters: {'pid': projectId, 'lim': limit, 'type': type, 'q': q, 'country': country, 'since': sinceTimestamp(days)},
    );
    return rows
        .map((r) => {
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
              'appVersion': r[10],
              'route': r[11],
              'deviceName': r[12],
              'networkUrl': r[13],
              'statusCode': r[14]?.toString(),
              'category': r[15],
              'level': r[16],
            })
        .toList();
  }

  Future<Map<String, dynamic>> projectOverview(String projectId, {int days = 1}) async {
    final conn = await db.connect();
    final project = await getProject(projectId);
    if (project == null) throw ArgumentError('Project not found');

    final since = utcTimestampDaysAgo(days);

    final stats = await conn.execute(
      Sql.named('''
        SELECT
          COUNT(*)::int,
          COUNT(*) FILTER (WHERE type IN ('error','network'))::int,
          COUNT(*) FILTER (WHERE type = 'crash')::int,
          COUNT(DISTINCT user_id) FILTER (WHERE user_id IS NOT NULL)::int
        FROM events
        WHERE project_id = @pid
          AND occurred_at >= @since::timestamptz
      '''),
      parameters: {'pid': projectId, 'since': since},
    );
    final s = stats.first;

    final openIssues = await conn.execute(
      Sql.named('SELECT COUNT(*)::int FROM issues WHERE project_id = @pid AND status = \'open\''),
      parameters: {'pid': projectId},
    );

    final sessions = await conn.execute(
      Sql.named('''
        SELECT
          (SELECT COUNT(*)::int FROM app_sessions
            WHERE project_id = @pid AND ended_at IS NULL
              AND started_at >= (now() AT TIME ZONE 'utc') - interval '30 minutes'),
          (SELECT AVG(duration_ms)::int FROM app_sessions
            WHERE project_id = @pid AND ended_at IS NOT NULL
              AND started_at >= @since::timestamptz),
          (SELECT COUNT(*)::int FROM app_sessions
            WHERE project_id = @pid AND ended_at IS NOT NULL
              AND started_at >= @since::timestamptz),
          COUNT(DISTINCT user_id) FILTER (
            WHERE user_id IS NOT NULL
              AND occurred_at >= @since::timestamptz
          )::int
        FROM events WHERE project_id = @pid
      '''),
      parameters: {'pid': projectId, 'since': since},
    );
    final sess = sessions.first;

    final countries = await conn.execute(
      Sql.named('''
        SELECT country, COUNT(*)::int AS c
        FROM events
        WHERE project_id = @pid AND country IS NOT NULL
          AND occurred_at >= @since::timestamptz
        GROUP BY country ORDER BY c DESC LIMIT 10
      '''),
      parameters: {'pid': projectId, 'since': since},
    );

    final releases = await conn.execute(
      Sql.named('''
        SELECT release, environment, event_count, crash_count, last_seen_at
        FROM releases WHERE project_id = @pid ORDER BY last_seen_at DESC LIMIT 10
      '''),
      parameters: {'pid': projectId},
    );

    final trendDays = days > 14 ? days : 14;
    final trend = await conn.execute(
      Sql.named('''
        SELECT date, SUM(events_total)::int, SUM(errors)::int, SUM(crashes)::int
        FROM daily_stats
        WHERE project_id = @pid AND date >= @fromDate::date
        GROUP BY date ORDER BY date
      '''),
      parameters: {'pid': projectId, 'fromDate': utcDateDaysAgo(trendDays - 1)},
    );

    return {
      'project': project,
      'days': days,
      'eventsToday': _i(s[0]),
      'errorsToday': _i(s[1]),
      'crashesToday': _i(s[2]),
      'uniqueUsersToday': _i(s[3]),
      'activeSessions': _i(sess[0]),
      'avgSessionDurationMs': sess[1] == null ? null : _i(sess[1]),
      'sessionsCompletedToday': _i(sess[2]),
      'uniqueUsers7d': _i(sess[3]),
      'openIssues': _i(openIssues.first[0]),
      'topCountries': countries.map((r) => {'country': r[0], 'count': r[1]}).toList(),
      'dailyTrend': trend
          .map((r) => {
                'date': (r[0] as DateTime).toIso8601String().substring(0, 10),
                'events': r[1],
                'errors': r[2],
                'crashes': r[3],
              })
          .toList(),
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

  Future<List<Map<String, dynamic>>> geoBreakdown(String projectId, {int days = 7}) async {
    final conn = await db.connect();
    final since = utcTimestampDaysAgo(days);
    final rows = await conn.execute(
      Sql.named('''
        SELECT country,
               COUNT(*)::int,
               COUNT(DISTINCT user_id) FILTER (WHERE user_id IS NOT NULL AND user_id <> '')::int
        FROM events
        WHERE project_id = @pid AND country IS NOT NULL
          AND occurred_at >= @since::timestamptz
        GROUP BY country
        ORDER BY COUNT(DISTINCT user_id) FILTER (WHERE user_id IS NOT NULL AND user_id <> '') DESC,
                 COUNT(*) DESC
      '''),
      parameters: {'pid': projectId, 'since': since},
    );
    return rows.map((r) => {'country': r[0], 'count': r[1], 'users': r[2]}).toList();
  }

  Future<List<Map<String, dynamic>>> _issueGeo(Connection conn, String projectId, String issueId) async {
    final rows = await conn.execute(
      Sql.named('''
        SELECT country, COUNT(*)::int FROM events
        WHERE project_id = @pid AND issue_id = @iid AND country IS NOT NULL
        GROUP BY country ORDER BY COUNT(*) DESC
      '''),
      parameters: {'pid': projectId, 'iid': issueId},
    );
    return rows.map((r) => {'country': r[0], 'count': r[1]}).toList();
  }

  Map<String, dynamic> _eventRow(ResultRow r) => {
        'id': r[0],
        'type': r[1],
        'occurredAt': (r[2] as DateTime).toUtc().toIso8601String(),
        'userId': r[3],
        'release': r[4],
        'country': r[5],
        'message': r[6],
        'payload': _jsonField(r[7]),
        'enrichment': _jsonField(r[8]),
      };

  Map<String, dynamic> _eventRowFull(ResultRow r) => {
        'id': r[0],
        'type': r[1],
        'occurredAt': (r[2] as DateTime).toUtc().toIso8601String(),
        'issueId': r[3],
        'userId': r[4],
        'sessionId': r[5],
        'release': r[6],
        'environment': r[7],
        'platform': r[8],
        'appVersion': r[9],
        'country': r[10],
        'region': r[11],
        'city': r[12],
        'message': r[13],
        'payload': _jsonField(r[14]),
        'enrichment': _jsonField(r[15]),
        'createdAt': (r[16] as DateTime).toUtc().toIso8601String(),
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
          INSERT INTO app_sessions (id, project_id, user_id, started_at)
          VALUES (@id, @pid, @uid, @at)
          ON CONFLICT (id) DO NOTHING
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
            duration_ms = COALESCE(@dur, EXTRACT(EPOCH FROM (@at - started_at)) * 1000)::int,
            user_id = COALESCE(user_id, @uid)
          WHERE id = @id AND project_id = @pid
        '''),
        parameters: {'id': sid, 'pid': projectId, 'uid': userId, 'at': occurredAt, 'dur': durationMs},
      );
    }
  }
}
