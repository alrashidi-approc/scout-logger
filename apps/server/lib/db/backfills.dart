import 'package:postgres/postgres.dart';

import '../services/geo_enricher.dart';
import '../util/user_identity.dart';
import 'scout_db.dart';

/// One-time data backfills, recorded in `backfills`. Run once the new server is
/// live (`bin/migrate.dart --backfills`): they rely on its ingest keeping the
/// new columns up to date from then on.
Future<void> runBackfills(ScoutDb db) async {
  await _once(db, 'daily_stats_geo_sources', _geoSources);
  await _once(db, 'issues_affected_users', _affectedUsers);
}

Future<void> _once(ScoutDb db, String name, Future<void> Function(ScoutDb db) run) async {
  final done = await db.pool.execute(Sql.named('SELECT 1 FROM backfills WHERE name = @n'), parameters: {'n': name});
  if (done.isNotEmpty) return;
  await run(db);
  await db.pool.execute(Sql.named('INSERT INTO backfills (name) VALUES (@n)'), parameters: {'n': name});
}

/// Raise `issues.affected_users` (insert-time 0/1 before ingest counted new users)
/// to the identified users in retained events. GREATEST keeps history whose
/// events retention already purged. Locking the issue first makes concurrent
/// ingest either visible to the recount or wait for it.
Future<void> _affectedUsers(ScoutDb db) async {
  final issues = await db.pool.execute('SELECT project_id, id FROM issues ORDER BY 1, 2');
  for (final issue in issues) {
    final params = {'pid': issue[0], 'id': issue[1]};
    await db.pool.runTx((tx) async {
      await tx.execute(Sql.named('SELECT 1 FROM issues WHERE id = @id FOR UPDATE'), parameters: {'id': issue[1]});
      await tx.execute(
        Sql.named('''
          UPDATE issues SET affected_users = GREATEST(affected_users, (
            SELECT COUNT(DISTINCT user_id) FILTER (WHERE ${identifiedUserSql()})::int
            FROM events WHERE project_id = @pid AND issue_id = @id
          ))
          WHERE id = @id
        '''),
        parameters: params,
      );
    });
  }
}

/// Recount `daily_stats.geo_*` from raw events still in retention, one short
/// transaction per project-day. Locking that day's rows first (in ingest's key
/// order) makes concurrent ingest either visible to the recount or wait for it.
Future<void> _geoSources(ScoutDb db) async {
  final days = await db.pool.execute('SELECT DISTINCT project_id, date::text FROM daily_stats ORDER BY 1, 2');
  for (final day in days) {
    final params = {'pid': day[0], 'day': day[1]};
    await db.pool.runTx((tx) async {
      await tx.execute(
        Sql.named('''
          SELECT 1 FROM daily_stats WHERE project_id = @pid AND date = @day::date
          ORDER BY country COLLATE "C" FOR UPDATE
        '''),
        parameters: params,
      );
      await tx.execute(
        Sql.named('''
          UPDATE daily_stats d SET geo_locale = a.loc, geo_ip = a.ip, geo_profile = a.prof
          FROM (
            SELECT COALESCE(country, '') AS country,
                   COUNT(*) FILTER (WHERE ${sqlGeoSourceIn('locale')})::int AS loc,
                   COUNT(*) FILTER (WHERE ${sqlGeoSourceIn('ip')})::int AS ip,
                   COUNT(*) FILTER (WHERE ${sqlGeoSourceIn('profile')})::int AS prof
            FROM events
            WHERE project_id = @pid AND NOT is_heartbeat
              AND occurred_at >= @day::date::timestamp AT TIME ZONE 'UTC'
              AND occurred_at < (@day::date + 1)::timestamp AT TIME ZONE 'UTC'
            GROUP BY 1
          ) a
          WHERE d.project_id = @pid AND d.date = @day::date AND d.country = a.country
        '''),
        parameters: params,
      );
    });
  }
}
