# scout-logger — Review Findings & Fix Checklist

Living checklist from Scout Engineer's reviews (started 2026-10-05). Fix in one pass later.
Baseline: `main` @ `77f7a8c`. Severity: Critical > High > Medium > Low > Info.

---

## 1. Security — public ingest API & dashboard auth

### Critical
- [ ] **S1. Hardcoded JWT / encryption secret fallbacks** — `apps/server/lib/config/server_config.dart` (`ServerConfig.load`): `jwtSecret = JWT_SECRET ?? DASHBOARD_API_KEY ?? 'dev-jwt-secret-change-me'`; `encryptionKey = ENCRYPTION_KEY ?? jwtSecret`. Missing env → forgeable admin JWTs + decryptable ingest/notification secrets.
  **Fix:** fail boot if secrets missing/weak; separate strong `JWT_SECRET` and `ENCRYPTION_KEY`; no fixed-string fallback.

### High
- [ ] **S2. Any project member can read live ingest key / DSN** — `auth_principal.dart` `canViewCredentials = membershipRole != null`; `GET /api/projects/<id>/credentials` (`api_routes.dart`) returns decrypted key. `support` role included → can forge events into the project.
  **Fix:** owner/admin only (or a secrets role); one-time reveal + audit log; rotation.
- [ ] **S3. JWT privileges not revalidated / no revocation** — `resolveAuth` trusts token claims (`role`, `canCreate`); demote / `setUnverified` don't invalidate; remember TTL 30d; `/api/*` doesn't recheck `emailVerified`.
  **Fix:** load user per request or add `token_version`; revoke on role/verify/password change; shorter access tokens + refresh.
- [ ] **S4. No rate limiting on auth or ingest** — nothing in `apps/server`, compose, or `infra`. Affects `/api/auth/login|signup|…`, `/v1/events/batch`, `/v1/client/config`.
  **Fix:** per-IP + per-email on auth; per-key + per-IP on ingest; edge (nginx/Cloudflare) + app layer.

### Medium
- [ ] **S5. Open signup + first user becomes admin + auto-verify without SMTP** — `auth_store.dart`, `auth_routes.dart`.
  **Fix:** invite-only / disable signup in prod; require verification; lock first-admin bootstrap.
- [ ] **S6. Unbounded ingest batch / body size** — `ingest_routes.dart`, `BatchIngestRequest`, `readBody`.
  **Fix:** cap bytes + events per batch; 413 on oversize. (Also DB item D1.)
- [ ] **S7. Low-privilege members can create public shares / share notifications** — `POST /projects/<id>/share`, `.../notifications/share` use `_projectGuard` without `write: true`.
  **Fix:** require write or owner/admin.
- [ ] **S8. `DASHBOARD_API_KEY` = unscoped full platform admin** — `AuthPrincipal.apiKey()`.
  **Fix:** scope it, rotate, monitor; prefer short-lived service tokens.

### Low
- [ ] **S9. Non-constant-time API key compare** — `auth_middleware.dart`, `http_utils.dashboardAuth`. **Fix:** reuse `_constantTimeEquals` from `slack_routes.dart`.
- [ ] **S10. CORS `*`** — `http_utils.dart` `_corsHeaders`. **Fix:** allowlist dashboard origins in prod.
- [ ] **S11. `jsonErr` string-interpolated JSON** — `http_utils.dart`. **Fix:** `jsonEncode({'ok': false, 'error': message})`.

### Info
- Share links are public by design (hashed token + expiry) — treat as secrets.
- Default `PLATFORM_OWNER_EMAIL` hardcoded in `server_config.dart`.
- Ingest binds project only from the Bearer key (DSN path not trusted) — good.

### Verify in prod
- Strong unique `JWT_SECRET` / `ENCRYPTION_KEY` / `DASHBOARD_API_KEY` set? Signup intended to be open? Edge rate limits / proxy body limits?

---

## 2. Database performance — event ingest & dashboard queries

Numbers are from a synthetic 1M-event replay (900k in one project) on PG17, not production.

### Critical
- [ ] **D1. Row-at-a-time ingest, no transaction** — `scout_store.dart` `ingestBatch` / `_ingestOne`, `identity_rollups.dart`: ~8–14 auto-committed round trips per event; no multi-row insert; no batch/body cap.
  **Fix:** one transaction per batch on a checked-out connection; multi-row INSERT events; aggregate rollup increments in memory → one upsert per key, sorted to avoid deadlocks; cap batch size.

### High
- [ ] **D2. "Pool" is round-robin shared connections, not checkout** — `scout_db.dart` `connect()` returns `_rr++ % 6`; postgres 3.x runs one op per connection; no `statement_timeout`. Slow dashboard queries stall ingest and vice versa.
  **Fix:** package `Pool` with `withConnection` / `runTx`; `statement_timeout`; consider separate ingest/dashboard pools.
- [ ] **D3. `purgeProjectData` uses raw `BEGIN`/`COMMIT` on a shared connection** — `scout_store.dart` ~256–445; other requests' writes can join/roll back with it; `DELETE … RETURNING id` loads all ids.
  **Fix:** `runTx` on checked-out connection; batched deletes returning counts.
- [ ] **D4. Generated columns & partial indexes unused** — reads use inline JSONB exprs (`sqlIsErrorEvent` ×27, `sqlHideSessionHeartbeat` ×50, `sqlIsSuccessEvent` ×5), so `events_project_error`, `events_project_time_nohb`, `events_project_install_time`, `events_project_user_time_nohb`, `events_project_success` are never chosen. Error list ~88 ms → <1 ms using `is_error`; 30-day error count 0.7–23 s → ~0.23 s.
  **Fix:** use `is_error` / `is_heartbeat` / `is_success` columns; then check `pg_stat_user_indexes` and drop unused + overlapping (`events_project_install` vs `events_user`).
- [ ] **D5. `COUNT(*)` of all project events on every project list / overview / dashboard** — `listProjects`, `fetchProjectById` (~210 ms at 900k, per project).
  **Fix:** sum `daily_stats.events_total` or cached counter; drop heartbeat predicate.
- [ ] **D6. Issue create race + partial batch commits → duplicates on retry** — `_upsertIssue` SELECT then plain INSERT; unique violation 500s mid-batch; server-generated event ids.
  **Fix:** `INSERT … ON CONFLICT (project_id, fingerprint) DO UPDATE … RETURNING`; batch transaction; accept client event id for idempotency.

### Medium
- [ ] **D7. Per-event rollup UPDATEs bloat** — `issues`, `user_stats`, `device_stats`, `user_device_links` update indexed `last_seen_at` (no HOT). **Fix:** in-memory aggregation per batch (with D1).
- [ ] **D8. Unindexed `ILIKE '%q%'` search** — `listEvents`, `listIssues`, `listUsers`, `listDevices`; 6.6–12.9 s no-match over 900k. **Fix:** `pg_trgm` GIN on chosen columns or search column; shorter default window; timeout.
- [ ] **D9. Heavy `listIssues` with search/facets** — 5 correlated subqueries per issue + `EXISTS`; facets drop time filter. **Fix:** pre-filter events, join once, keep time bound.
- [ ] **D10. Issue/event detail over-fetch** — `getIssue` ~9 unbounded queries; `getEvent` calls full `getIssue` for 8 fields. **Fix:** lightweight issue summary for event detail; time-bound analytics.
- [ ] **D11. Analytics on raw events** — `geoBreakdown` ~10 s/30d (country already in `daily_stats`); retention CTE unbounded; funnel 1.9 s/7d; ≤24h dashboard ~15 raw scans; grouped view 6 `ARRAY_AGG`s. **Fix:** hourly + country rollups; bound retention.
- [ ] **D12. Notifications inline in ingest** — `projectName` N+1, dedup, hourly count, `logDelivery`, awaited external sends. **Fix:** load once per batch; background delivery queue.
- [ ] **D13. `reclassifyExpectedNetworkEvents` synchronous in settings PATCH** — up to 5k UPDATEs + rollup rebuilds over 90d. **Fix:** background job.
- [ ] **D14. Migration runner splits on `;` → 016 `DO $$` breaks fresh DBs** — `_executeSqlScript`; migrations at boot, no tx, non-concurrent `CREATE INDEX`, full-table rewrites (007/010/014/018/023) lock `events`.
  **Fix:** dollar-quote-aware runner or per-file execution; `CREATE INDEX CONCURRENTLY`; run migrations outside boot.

### Low / Info
- [ ] **D15.** Every batch runs `closeStaleSessions` + reads `projects.settings` 3–4×; `getConfigVersion` extra read. **Fix:** load once per batch / cache.
- [ ] **D16.** OFFSET pagination (offset 5000 ≈ 19–42 ms) — move to keyset later.
- Info: `(@x IS NULL OR col = @x)` filters fine while unnamed statements; would degrade with named prepared statements.
- [ ] **D17.** `issues.affected_users` set only on insert, never updated.

### Verify in prod
- `events` size, events/day/project, SDK batch size/flush, instance count, notifications enabled.
- `pg_stat_statements` top queries; `pg_stat_user_indexes` for the 5 partial indexes; HOT ratio + autovacuum lag on `issues`, `user_stats`, `device_stats`.
- Is 016 in `schema_migrations` and its indexes present? PG version, `max_connections`, `synchronous_commit`.

---

## 3. Duplicated code

Meaningful duplication in server + dashboard (skip trivial `Map.from` / `jsonDecode` / one-line `_projectGuard` calls). Ranked by consolidation value.

### High value
- [ ] **C1. Error / noise classification logic triplicated (SQL + Dart + issue/notify gates)** — Same rules live in:
  - `apps/server/lib/util/event_filters.dart` → `sqlIsErrorEvent` / `isErrorEvent` / `sqlIsSuccessEvent` / `isSuccessEvent`
  - Generated columns `events.is_error` / `is_success` / `is_heartbeat` (`014_event_outcome_columns.sql`, repaired for `faultKind` in `023_is_error_expected_network.sql`)
  - Issue gate `_qualifiesForIssue` (`scout_store.dart` ~20–40) checking `operationalError` / `issueWorthy` / `faultKind` / `classifyNetworkFault`
  - Alert gates `notification_categories.dart` + `notification_router.dart` `_networkAlertWorthy` (same readable flags again)
  - Dashboard badge: `event_card.dart` `faultKind == 'expected' || operationalError == false`
  Drift already happened once (014 `is_error` omitted `faultKind <> 'expected'` until 023). Reads still paste `sqlIsErrorEvent()` × many call sites instead of `is_error` (see D4).
  **Fix/Proposal:** One shared classifier in `scout_models` (or `event_filters`) exporting: `isErrorEvent`, `qualifiesForIssue`, `alertWorthyNetwork`, plus a single SQL fragment / generated-column definition generated from the same comments/tests. Prefer reading `is_error` column everywhere after D4. Add a goldentest that asserts SQL text, Dart, and migration expression agree on fixtures.

- [ ] **C2. Route normalization duplicated (server vs scout_models)** — `normalizeRoute` + `_isDynamicSegment` in `apps/server/lib/util/ids.dart` (~45–56) is copy-pasted as `normalizeExpectedNetworkPath` + `_isDynamicSegment` in `packages/scout_models/lib/src/expected_network.dart` (~80–93). Comment even says “Same idea as server normalizeRoute”. Used for fingerprints, titles, alert dedup, expected-network matching.
  **Fix/Proposal:** Move canonical `normalizeRoute` / `isDynamicSegment` into `scout_models`; server + expected-network import it. One place to extend (e.g. more id shapes).

- [ ] **C3. `user_identity.dart` copy-pasted server ↔ dashboard** — Nearly identical: `apps/server/lib/util/user_identity.dart` and `apps/dashboard/lib/utils/user_identity.dart` (`installIdFromPayload`, `userEmailFromPayload`, `isIdentifiedAppUser`, `isGuestAppUser`, UUID regex). Server adds SQL helpers; dashboard adds `isGuestEvent` / `userDisplayLabel`.
  **Fix/Proposal:** Put shared Dart helpers in `scout_models` (or a tiny shared util package); keep only SQL (`identifiedUserSql` / `guestUserSql`) on the server and display helpers on the dashboard.

### Medium value
- [ ] **C4. Stack “culprit” vs fingerprint first-frame — two parsers, inconsistent grouping** — Fingerprint (`eventFingerprint` in `ids.dart`) hashes **first non-empty stack line**. Culprit / alerts (`stackCulpritFromTrace` in `insights.dart`) skip `dart:` / `package:flutter*` and pick the first in-app frame. Notifications reuse culprit; grouping does not → same crash can fan out when framework frames reorder, or miss merges when only deep frames differ by params.
  **Fix/Proposal:** Single `stackFrames(trace)` → `fingerprintFrame` (normalized in-app) + `displayCulprit`. Fingerprint and insights both call it (feeds I2).

- [ ] **C5. Expected-network / non-incident skip checks copy-pasted 5×** — Pattern `operationalError == false || issueWorthy == false || faultKind == 'expected'` appears in `_qualifiesForIssue`, `notification_categoriesFor`, `_networkAlertWorthy`, `reclassifyExpectedNetworkEvents` (~2738), and dashboard `EventCard`. Easy to update one path and miss another.
  **Fix/Proposal:** `bool isExpectedOrNonOperationalNetwork(Map readable)` (+ optional `NetworkFaultInfo`) in shared util; all gates call it.

- [ ] **C6. `releaseFromPayload` duplicated** — `ids.dart` `releaseFromPayload` (name/version) vs `notification_router.dart` `_releaseFromPayload` (also checks `app.version` / `app.build`). Ingest uses the first; alerts use the second → release can show in alerts but not in `events.release` / `releases` table.
  **Fix/Proposal:** One richer `releaseFromPayload` in `ids.dart` (or scout_models); delete the router private copy.

- [ ] **C7. Issue list/detail JSON + severity mapping repeated** — `listIssues` lite (~1051–1070), full (~1140–1165), `getIssue` + `_issueInsights` (~1236–1250), and overview open-issue scan (~2274–2282) each: parse row → `computeIssueSeverity(...)` → map of id/fingerprint/title/counts/severity. Same shape, slightly different fields.
  **Fix/Proposal:** `_issueSummaryFromRow(r, {periodOverrides})` + always attach severity/reasons once. Optionally persist severity (see I4) to avoid recomputing on every list.

- [ ] **C8. Events / Issues screen filter + facets boilerplate** — `events_screen.dart` and `issues_screen.dart` both: PeriodPicker, FilterBar, FacetsCache `_loadFacets`, URL sync of env/version/device/search/period, beginScreenLoad. Same pattern also echoes on users/devices/sessions (lighter).
  **Fix/Proposal:** Extract a small `ProjectListController` / mixin (period + facets + query sync) used by Events and Issues; keep type-specific filters local.

### Lower value (still real)
- [ ] **C9. Smart summary diagnosis vs heuristic briefs nearly duplicated** — `smart_issue_summary.dart` `_diagnosisBrief` and `_heuristicBrief` (~112–250) repeat operation/stage/entrypoint/platform_code/layers/storm/where/failedAt assembly; diagnosis only swaps `why`/`next` source.
  **Fix/Proposal:** Shared `_contextBrief(EventView, {why, next})` builder; diagnosis/heuristic supply why/next only.

- [ ] **C10. Intentional SQL ↔ Dart duals for routine / WAF / group keys** — `isRoutineEvent` ↔ `sqlIsRoutineEvent`, `isWafRejectEvent` ↔ `sqlIsWafRejectEvent`, `eventGroupKey` ↔ `sqlEventGroupKey` in `event_filters.dart`. Good for tests, but no automated sync.
  **Fix/Proposal:** Keep duals; add fixture tests (already partially in `event_outcome_test.dart`) covering every dual. Document “edit both + migration if generated column”.

### Skipped as trivial
- Repeated `Map<String, dynamic>.from` / `jsonDecode` in `api_client.dart` (idiomatic Dart without code-gen).
- Dozens of `await _projectGuard(...)` lines in `api_routes.dart` (thin auth wrapper; extract only if adding middleware).
- Dashboard re-export `network_readable.dart` → already correctly delegates to `scout_models`.

---

## 4. Smarter events & issues (dashboard/server-side only, no SDK changes)

Baseline of what exists today, then ranked improvements that use **only data already ingested**. Client SDKs (`scout_logger` / `scout_logger_plus`) are fixed — anything needing new payload fields is marked **out of scope**.

### What exists today (evidence)

| Area | Today | Evidence |
|------|--------|----------|
| Ingest payload | `type` + `payload` JSONB: `message`, `stack`/`stackTrace`, `level`, `category`, `environment`, `release`, `user`, `device`, `screen`, `screenTrail`/`breadcrumbs`, `network` (+ server-enriched `readable`), `diagnosis`, `context`, `custom`, `overview` | `docs/SDK-DASHBOARD-COMPAT.md`, `ingest.dart`, `_ingestOne` |
| Fingerprint | Network: `sha256(network\|METHOD\|normalizeRoute(url))`. Error/crash: `sha256(type\|category\|raw message\|first stack line)` | `ids.dart` `eventFingerprint` |
| Titles | `overview.title` → `message` → `METHOD route` → `category · type` | `eventTitle` |
| Issue gate | level not info/success; network must be issueWorthy + operational + status≥400/error | `_qualifiesForIssue` |
| Noise (network) | `expectedNetworkResponses`, fault overrides, `faultKind=expected` | `scout_models` + settings reclassify |
| Severity | On-read score: eventCount, affectedUsers, recency, isCrash → low/med/high | `insights.dart` `computeIssueSeverity` |
| Culprit | First non-flutter/dart frame (display only) | `stackCulpritFromTrace`, issue insights |
| Regression | Resolved → reopen + `regressed_at`; alert `asRegression()` | `_upsertIssue`, `notification_router` |
| User impact | `affected_users` set **only on insert** (0/1); rebuilt only in purge | `_upsertIssue`; D17 |
| Releases | `releases` table event/crash counts; Analytics Releases tab crash % | ingest + `analytics_store` / `_ReleasesTab` |
| Dedup alerts | issueId / fingerprint / `net\|METHOD\|route` | `alertDedupKey` |
| Smart summary | Client-only Where/Failed/Why/Next from diagnosis → heuristics | `smart_issue_summary.dart` |
| Grouped events | Ephemeral `sqlEventGroupKey` (issue / network route / type+action) | `event_filters`, Events `view=grouped` |
| Lifecycle | open / resolved / ignored; assignee; mark-as-expected; notes | migrations 012/013, issue detail |

### Ranked proposals (server/dashboard only)

- [ ] **I1. Message parameter stripping in fingerprints** — **Today:** raw `payload.message` is hashed (`ids.dart` `eventFingerprint`) so `"User abc-uuid failed"` ≠ `"User def-uuid failed"`. **Gap:** issue explosion from ids/numbers/URLs/emails in messages. **Proposal:** normalize before hash: replace UUIDs, long hex, integers, emails, URLs, and quoted dynamic tokens with placeholders (`<id>`, `<num>`, `<url>`). Keep raw message for display/title. **Data:** `payload.message` (already stored). **Effort:** S. **Impact:** High.

- [ ] **I2. Fingerprint on normalized in-app stack frames (align with culprit)** — **Today:** first stack line (often `package:flutter/...`); culprit skips framework frames but is display-only (C4). **Gap:** unstable grouping when SDK/framework frames shift. **Proposal:** parse frames; drop `dart:` / `package:flutter*`; strip line/column and anonymous closures to `file:Class.method` (or best available); hash top 1–3 in-app frames + normalized message + type/category. Network fingerprint unchanged (already route-normalized). **Data:** `payload.stack` / `stackTrace`. **Effort:** S–M. **Impact:** High.

- [ ] **I3. Keep `affected_users` (and unique devices) accurate on every upsert** — **Today:** insert sets 0/1; updates never increment; severity/user impact wrong until purge rebuild (`scout_store` ~330–348). **Gap:** priority and “users affected” lie. **Proposal:** on `_upsertIssue`, if identified `user_id` new for issue → `affected_users = affected_users + 1` (or maintain `issue_users` set / HyperLogLog later); optionally track `affected_installs` from `install_id`. **Data:** `user_id`, `install_id` columns already written. **Effort:** S. **Impact:** High (also unlocks trustworthy I4).

- [ ] **I4. Priority score: velocity + new-in-release + crash vs handled** — **Today:** `computeIssueSeverity` uses lifetime counts + hours since last seen + crash bit; recomputed on read; overview “High severity” uses that. **Gap:** no rate, no “first seen in this release”, no handled-error discount. **Proposal:** score = f(users, events/hour last 24h vs prior 7d baseline, isCrash, first_seen within current `release`, status). Persist `priority` / `priority_reasons` on issue (or compute in list SQL from stored counters). Surface on Issues sort + triage. **Data:** `event_count`, timestamps, `type`, `release` on events, `releases` table. **Effort:** M. **Impact:** High.

- [ ] **I5. Spike / velocity regression detection (beyond reopen)** — **Today:** “regression” = resolved issue reopened; digests count `regressed_at` / new issues (`digestData`). **Gap:** open issues that suddenly 10× don’t get special treatment. **Proposal:** hourly rollup per `issue_id` (or query last 1h vs median of last 7d same hour); flag `spike: true` when z-score/threshold exceeded; feed notifications (new category `issue_spike`) and Issues badge. **Data:** existing `events` + `issue_id`. **Effort:** M. **Impact:** High.

- [ ] **I6. Noise / flaky auto-classification** — **Today:** expected-network rules + ignore status; Focus hides session lifecycle; no “flaky”/“noise” issue state beyond `ignored`. **Gap:** one-off simulator errors, single-user ghosts, auth noise still clutter open list. **Proposal:** server tags on upsert/recompute: `noise_reason` ∈ {`single_occurrence`, `single_user`, `simulator_only`, `auth_class`, `stale`}; default filter Issues to hide noise; one-click “Ignore similar”. Rules use `device.isSimulator`, `user_id` diversity, `event_count`, `network.readable.faultClass`, `last_seen_at`. **Data:** already in payload/columns. **Effort:** M. **Impact:** High.

- [ ] **I7. Smarter titles (diagnosis / culprit / normalized message)** — **Today:** first event’s `eventTitle` locked in; updates only `COALESCE(NULLIF(@title,''), title)`. **Gap:** titles stay as raw SDK messages with ids. **Proposal:** prefer `payload.diagnosis.summary` → `METHOD route · faultLabel` → `culpritFile: messageNormalized` → clipped message; refresh title when better signal arrives (diagnosis confidence high). Dashboard already renders diagnosis in smart summary — lift into issue title. **Data:** `diagnosis`, `network.readable`, stack, message. **Effort:** S. **Impact:** Medium–High.

- [ ] **I8. Release health tied to issues (“new in this release”)** — **Today:** Analytics Releases shows crash % / sessions; issues don’t annotate “introduced in 2.1.0+42”; digests leave `version` NULL. **Proposal:** on first upsert store `first_release`; listIssues facet “New in release X”; release detail = new issues + regressed + crash-free sessions %. Overview card: “N new issues since last release”. **Data:** `events.release` / `app_version`, `issues.first_seen_at`, `releases`. **Effort:** M. **Impact:** High.

- [ ] **I9. Auto-resolve / auto-ignore rules (project settings)** — **Today:** manual status; mute via ignored; mark-as-expected for network. **Gap:** no “resolve if silent 14d”, no path/message ignore patterns for errors. **Proposal:** settings JSON: `{ autoResolveQuietDays, ignoreMessageRegexes[], ignoreCulpritPrefixes[] }` applied by retention/monitor job; still allow manual reopen (existing regression path). **Data:** issue timestamps + message/culprit already stored. **Effort:** M. **Impact:** Medium.

- [ ] **I10. Related issues + merge candidates** — **Today:** event detail has `relatedEvents` (same issue); no cross-issue links; fingerprints are exact. **Gap:** near-duplicates after I1/I2 still need merge. **Proposal:** (a) suggest related by shared normalized culprit file or same network route different status; (b) optional `POST merge` rewriting `events.issue_id` + fingerprint alias table. Start with read-only “Similar (N)” on issue detail. **Data:** fingerprints, culprit, network route. **Effort:** M–L. **Impact:** High (merge L; suggestions M).

- [ ] **I11. Context / breadcrumb-aware grouping signals** — **Today:** fingerprint ignores `context.failure_layer`, `platform_code`, `operation`, trail. Smart summary uses them for display only. **Gap:** same stack from different product layers looks identical; opposite also true when message differs but layer same. **Proposal:** optional fingerprint component from stable context keys when present (`failure_layer` + `platform_code` + normalized message), or secondary “group hint” for Related (I10) without changing primary fingerprint initially. **Data:** `payload.context`, `custom`, breadcrumbs (already ingested when apps send them). **Effort:** S–M. **Impact:** Medium.

- [ ] **I12. Triage inbox + “what changed” UX** — **Today:** Issues list sorted by last_seen / severity; no inbox metaphor; overview has high-severity count only. **Gap:** “what should I look at now?” and “what changed since yesterday?” are manual. **Proposal:** Dashboard **Inbox** tab: open + not-noise, sorted by I4 priority; sections New / Spikes / Regressions / Waiting; “Since your last visit” using `first_seen_at` / `regressed_at` / spike flags. Reuse IssueCard. **Data:** existing issue fields + I4–I6 flags. **Effort:** M. **Impact:** High (UX).

- [ ] **I13. Server issue summary rollup (diagnosis consensus)** — **Today:** smart summary is client-side from latest events; no stored brief. **Gap:** list cards and Slack digests stay title-only; diagnosis not rolled up. **Proposal:** on upsert, if `diagnosis.summary` present, store `issues.summary` / `likely_cause` (majority or latest high-confidence); expose in listIssues lite + digest bodies. **Data:** `payload.diagnosis.*` when SDK already sends it (no new SDK work). **Effort:** S–M. **Impact:** Medium.

- [ ] **I14. Suggested culprit owner (heuristic, no SCM)** — **Today:** assignee is manual; culprit frame shown. **Gap:** no routing hint. **Proposal:** map culprit path prefixes → team/owner from project settings (`pathPrefixes: [{prefix: 'lib/payments/', assignee}]`); suggest on issue detail. True git-blame needs SCM integration → out of scope. **Data:** stack culprit + settings. **Effort:** S. **Impact:** Medium.

- [ ] **I15. Persist correlations / “suspect release|device|country” on issue** — **Today:** `_issueInsights` computes correlations (≥60% app_version/platform/country/environment) only on getIssue (N queries). **Gap:** list/inbox can’t show “90% on iOS 17”. **Proposal:** maintain cheap counters on upsert or periodic job; show chips on IssueCard. **Data:** event columns already filtered in insights. **Effort:** M. **Impact:** Medium.

### Out of scope (needs SDK / external changes)

- New payload fields (e.g. richer breadcrumbs schema, user “handled vs fatal” flag beyond `type`/`level`, custom fingerprint templates from client).
- Source-map / obfuscation deobfuscation (needs uploaded symbols).
- Git blame / CODEOWNERS from repo (needs SCM token + source link).
- Client-side sampling / before-send hooks (remote config already covers some knobs without SDK code changes — extending those is OK server-side; changing SDK behavior is not).
- LLM-generated summaries that require calling out with PII without a product decision (local heuristic summary I13 is in-scope).

### Suggested implementation order

1. **I1 + I2 + I3** (fingerprint quality + accurate users) — biggest “issues aren’t smart” win, mostly `ids.dart` / `_upsertIssue`.
2. **I4 + I5 + I6 + I12** — priority, spikes, noise, triage UX.
3. **I7 + I8 + I13** — titles, release health, digest/list summaries.
4. **I9 + I10 + I11 + I14 + I15** — rules, merge/related, ownership polish.

