# scout_logger_plus — dashboard compatibility

Checklist of changes required in **`scout_logger_plus`** so events render correctly in the Scout dashboard (event inspector, timeline, analytics, sessions, issues).

**Source of truth for shared types:** `packages/scout_models` in the **scout-logger** platform repo.

**Dashboard reads:** `payload` JSON stored in Postgres (plus server geo enrichment). No special client fields outside this doc are required.

---

## 1. Dependencies

```yaml
dependencies:
  scout_models:
    git:
      url: https://github.com/YOUR_ORG/scout-logger.git
      path: packages/scout_models
```

Import taxonomy + navigation helpers:

```dart
import 'package:scout_models/scout_models.dart';
```

| Module | Use in SDK |
|--------|------------|
| `taxonomy.dart` | `ingestTypeFor`, `kEventLevels`, `kErrorCategories` |
| `navigation.dart` | `NavTransition`, `screenTrailStep`, `parseNavTransition` |
| `ingest.dart` | `IngestEvent`, `BatchIngestRequest` |
| `sdk_config.dart` | `ProjectSdkConfig`, `ProjectRemoteConfig`, `normalizeStatusCodes` |

---

## 2. Ingest wire format

**Endpoint:** `POST {DSN}/v1/events/batch`  
**Auth:** `Authorization: Bearer sk_live_...`  
**Body:**

```json
{
  "events": [
    {
      "type": "error",
      "timestamp": "2026-06-20T14:19:54.000Z",
      "payload": { }
    }
  ]
}
```

### Event `type` (transport)

Set using `ingestTypeFor(level:, category:)` from `scout_models`:

| `level` | `category` | ingest `type` | Dashboard |
|---------|------------|---------------|-----------|
| `error` | `crashing` | `crash` | Crashes, issue grouping |
| `error` | `network` | `network` | Network issues |
| `error` | *(other)* | `error` | Issues / Events |
| `info` / `warning` / `success` | * | `log` | Logs, overview stats |

Allowed types: `error`, `crash`, `network`, `span`, `session`, `log` (`kEventTypes`).

---

## 3. Payload envelope (every event)

Attach these top-level keys inside **`payload`** on every error/crash/log (and session/network when relevant):

```json
{
  "message": "Payment failed: card declined",
  "stack": "Exception at ...",
  "level": "error",
  "category": "logic",
  "environment": "production",
  "release": "com.demo.app@2.1.0+42",

  "user": { "id": "user-101", "sessionId": "sess-abc" },
  "device": { "platform": "ios", "version": "2.1.0", "appVersion": "2.1.0+42" },
  "screen": { "currentRoute": "/checkout", "currentScreenMs": 4200 },
  "screenTrail": [ ],
  "custom": { },
  "context": { }
}
```

### Required for a useful dashboard

| Field | Path | Dashboard use |
|-------|------|----------------|
| Message | `payload.message` | Event header, issues title |
| Stack | `payload.stack` | Technical tab |
| Level | `payload.level` | Badges (`error` / `info` / `warning` / `success`) |
| Category | `payload.category` | Badges + issue grouping |
| Environment | `payload.environment` | Quick facts, filters |
| Release | `payload.release` or `release.name` | Release comparison, header chips |
| User ID | `payload.user.id` | Users, geo, filters |
| Session ID | `payload.user.sessionId` | Sessions, timeline |
| Platform | `payload.device.platform` | Device tab, cards |
| Current screen | `payload.screen.currentRoute` | Event header, screen fields |

### Recommended (rich UI)

| Field | Path | Dashboard use |
|-------|------|----------------|
| Screen trail | `payload.screenTrail` | Timeline → User journey |
| Breadcrumbs alias | `payload.breadcrumbs` | Same as `screenTrail` (fallback) |
| Network block | `payload.network` | Technical + Raw tabs, network readable panel |
| Overview | `payload.overview.title` | Fallback message |
| Custom context | `payload.custom` | Product context section |
| Device detail | `device.deviceName`, `osVersion`, `manufacturer`, `deviceModel`, `darkMode`, `timezone`, `languageCode`, `countryCode`, `batteryLevel`, `isOnline` | Device & connectivity |
| Session summary | `payload.summary` on `type: session` | Analytics → Sessions |

---

## 4. Screen trail & navigation type (Timeline tab)

**Status today:** Dashboard shows **NO NAV** if steps lack navigation type. Demo seed data often has no trail at all.

Each step in `payload.screenTrail` (or `breadcrumbs` / `userFlow`) must include **`navigationType`**.

### Canonical step shape

Use `screenTrailStep()` from `scout_models`:

```dart
screenTrailStep(
  route: '/checkout',
  screenName: 'Checkout',
  navigationType: NavTransition.push,
  at: DateTime.now().toUtc(),
  durationMs: 4200,
);
```

JSON:

```json
{
  "route": "/checkout",
  "screenName": "Checkout",
  "navigationType": "push",
  "at": "2026-06-20T14:19:50.000Z",
  "durationMs": 4200
}
```

### `navigationType` values

| Value | When to use (GoRouter / Navigator) |
|-------|-------------------------------------|
| `push` | New route pushed on stack |
| `pop` | User went back |
| `replace` | Route replaced (replace, replaceAll) |
| `remove` | Route removed from stack |
| `go` | Declarative go / goNamed (no stack push) |

Dashboard also accepts legacy aliases: `navType`, `transition`, `navAction`, `action` — prefer **`navigationType`** for new SDK code.

### SDK implementation checklist

- [ ] **`ScreenTrail` collector** — ring buffer of last N steps (e.g. 30)
- [ ] **Route observer** — hook `NavigatorObserver` and/or GoRouter delegate notifications
- [ ] **Map transitions** — push/pop/replace/go → `NavTransition`
- [ ] **Duration** — time on previous screen → `durationMs` on the *next* step
- [ ] **Attach to events** — copy trail into `payload.screenTrail` on `captureException`, crashes, and optionally every batch flush
- [ ] **Do not strip fields** — send full step maps; server stores payload as JSONB

### Verify in dashboard

1. Open **Events** → event detail → **Timeline** group → **User journey**
2. Each step shows badge: **PUSH**, **POP**, etc.
3. Yellow warning absent when all steps have `navigationType`

---

## 5. `screen` block (current location)

```json
"screen": {
  "currentRoute": "/checkout",
  "currentScreenMs": 8400
}
```

Dashboard resolves route as: `screen.currentRoute` → `payload.route` → `payload.screen` (string).

---

## 6. Network events (Dio interceptor)

For failed/slow HTTP calls, send `type: network` (or `level: error`, `category: network`) with:

```json
"network": {
  "method": "POST",
  "url": "https://api.example.com/pay",
  "statusCode": "402",
  "durationMs": 1200,
  "error": "Payment declined",
  "errorType": "HttpException",
  "hasResponse": true,
  "slow": false,
  "slowThresholdMs": 3000,
  "traceId": "optional-correlation-id",
  "curl": "curl -X POST ..."
}
```

Dashboard builds human-readable network summary from this block.

### Ignore HTTP status codes

Skip expected failures (e.g. **401** on token refresh) — no network event and no breadcrumb:

```dart
await Scout.init(dsn, options: const ScoutOptions(
  networkIgnoreStatusCodes: {401, 403},
));
```

Or configure remotely in dashboard **Settings → Ignore HTTP status codes** (see §16). Valid codes: `100–599`.

When a response status matches the ignore list, `recordNetwork()` returns early before enqueue.

---

## 7. Session events

Send periodic or lifecycle `type: session` events:

```json
{
  "type": "session",
  "timestamp": "...",
  "payload": {
    "action": "heartbeat",
    "durationMs": 120000,
    "environment": "production",
    "user": { "id": "...", "sessionId": "..." },
    "screen": { "currentRoute": "/home" },
    "screenTrail": [ ],
    "summary": {
      "screensVisited": 4,
      "networkCalls": 12,
      "errors": 1,
      "actions": 8,
      "longestScreen": "/checkout",
      "longestScreenMs": 45000
    }
  }
}
```

Powers **Analytics → Sessions** and session detail timeline.

---

## 8. User & device collectors

### `user`

```json
"user": {
  "id": "user-101",
  "sessionId": "sess-uuid",
  "email": "optional",
  "name": "optional"
}
```

Call `Scout.setUser(...)` when auth state changes; persist `sessionId` per app visit.

### `device`

Collect once at init + refresh on connectivity/battery changes:

```json
"device": {
  "platform": "ios",
  "version": "17.4",
  "appVersion": "2.1.0+42",
  "deviceName": "iPhone 15",
  "manufacturer": "Apple",
  "deviceModel": "iPhone15,2",
  "osVersion": "17.4",
  "darkMode": true,
  "timezone": "Asia/Kuwait",
  "languageCode": "en",
  "countryCode": "KW",
  "isOnline": true,
  "batteryLevel": "0.82"
}
```

---

## 9. Levels & categories

From `scout_models` / `taxonomy.dart`:

**Levels:** `error`, `info`, `warning`, `success`  
**Categories:** `network`, `system`, `crashing`, `logic`, `ui`

Example:

```dart
await Scout.captureException(
  e,
  stackTrace: st,
  level: ScoutLevel.error,
  category: ScoutCategory.logic,
);
```

Map to payload:

```dart
'level': level.name,
'category': category.name,
'type': ingestTypeFor(level: level.name, category: category.name),
```

---

## 10. Init & DSN

Dashboard DSN format (copy as-is from **Projects → DSN**):

```
https://sk_live_...@your-host:8080/project_id
```

Parsed into: ingest key, base URL, project id. Batch path is always `/v1/events/batch`.

```dart
await Scout.initFromEnv(); // reads SCOUT_DSN from .env
// or
await Scout.init('https://sk_live_...@localhost:8080/your_project_id');
```

DSN is **identity + auth only** — runtime knobs (log levels, network ignore codes, etc.) come from remote config (§16) or local `ScoutOptions`.

```dart
const ScoutOptions(
  environment: 'production',       // or SCOUT_ENVIRONMENT in .env
  useRemoteConfig: true,           // fetch dashboard Settings on init / resume (default)
  enabledLevels: {ScoutLevel.error, ScoutLevel.warning},
  networkIgnoreStatusCodes: {401},
  networkSlowThresholdMs: 3000,    // null = disable slow flag
  networkCaptureBodies: true,
  trackNavigation: true,
  enableFlutterHooks: true,
  debug: false,
);
```

Opt out of remote config:

```dart
ScoutOptions(useRemoteConfig: false)
```

---

## 11. Package file checklist

Suggested layout in **scout_logger_plus**:

| File | Responsibility |
|------|----------------|
| `lib/scout.dart` | Public API: init, captureException, log, setUser, setContext |
| `lib/scout_options.dart` | Local options + `withRemote()` merge |
| `lib/remote_config_client.dart` | `GET /v1/client/config` |
| `lib/screen_trail.dart` | Trail buffer + **navigationType** on each step |
| `lib/session_tracker.dart` | Session id, heartbeats, summary counts |
| `lib/device_collector.dart` | Device map for payload |
| `lib/ingest_client.dart` | Batch POST to `/v1/events/batch` |
| `lib/event_queue.dart` | Offline queue + flush |
| `lib/dio_interceptor.dart` | Network events |
| `lib/flutter_binding.dart` | `FlutterError.onError`, `PlatformDispatcher` crashes |
| `lib/enums.dart` | `ScoutLevel`, `ScoutCategory` → scout_models |

---

## 12. Compatibility matrix

| Dashboard feature | Needs from SDK |
|-------------------|----------------|
| Events list / cards | `message`, `type`, `user`, `release`, `screen.currentRoute` |
| Event inspector header | `level`, `category`, `environment`, `device.platform`, `release` |
| Timeline → User journey | `screenTrail[]` with **`navigationType`** on every step |
| Timeline → Screens & trail | `screen` fields + trail routes |
| Technical → Stack | `stack` |
| Technical → Network | `network` object |
| Technical → Device | `device` object |
| Raw data tab | Full payload (automatic if you send rich payload) |
| Issues grouping | `type` error/crash/network + stack/message fingerprint |
| Analytics funnels | Distinct `screenTrail[].route` values across sessions |
| Sessions replay | `type: session` + `screenTrail` + `summary` |
| Users / Geo | `user.id`, optional `device.countryCode`; server adds IP geo |
| Project Settings (SDK tab) | Remote config via `GET /v1/client/config` (§16) |

---

## 13. Local verification

**Platform repo:**

```bash
./dev server
./dev test                    # sends sample event (set INGEST_KEY)
cd apps/dashboard && flutter build web
```

**From Flutter app with SDK:**

1. Integrate package, set `SCOUT_DSN`
2. Navigate: Home → push → Checkout → pop → trigger test error
3. Dashboard → Events → open event
4. Confirm Timeline shows steps with **PUSH** / **POP** badges
5. Analytics → Sessions shows visit; funnel routes populate after several sessions

---

## 14. Priority order (recommended)

1. **Payload envelope** — user, device, screen, message, stack, level, category, release  
2. **screenTrail + navigationType** — timeline navigation badges  
3. **Network interceptor** — network tab + issues (+ ignore status codes)  
4. **Remote SDK config** — fetch + merge on init/resume (§16)  
5. **Session heartbeats + summary** — analytics sessions  
6. **Crash binding + queue** — reliability  

---

## 15. Related platform files

| Area | Path |
|------|------|
| Navigation contract | `packages/scout_models/lib/src/navigation.dart` |
| Event types / levels | `packages/scout_models/lib/src/taxonomy.dart` |
| Remote SDK config schema | `packages/scout_models/lib/src/sdk_config.dart` |
| Client config route | `apps/server/lib/routes/client_config_routes.dart` |
| Project settings store | `apps/server/lib/store/scout_store.dart` → `getProjectSettings`, `updateProjectSettings` |
| Dashboard settings UI | `apps/dashboard/lib/screens/project_settings_screen.dart` |
| Dashboard payload parser | `apps/dashboard/lib/utils/event_view.dart` |
| Timeline UI | `apps/dashboard/lib/widgets/event_detail_widgets.dart` → `BreadcrumbTrail` |
| Session timeline merge | `apps/server/lib/store/analytics_store.dart` → `_mergeTrail` |
| Export SDK to own repo | `scripts/export-sdk-repo.sh` |

When `scout_models` changes, bump the git ref in **scout_logger_plus** `pubspec.yaml` and re-export the SDK repo.

---

## 16. Remote SDK config (dashboard-controlled)

Ops can tune SDK behavior per project from the dashboard without shipping a new app build. Settings are stored in `projects.settings` (JSONB) and fetched by the mobile client using the same ingest key as the DSN.

### Architecture

```
Dashboard  →  PATCH /api/projects/:id/settings   (JWT auth)
Mobile SDK →  GET  /v1/client/config             (Bearer sk_live_…)
Server     →  projects.settings JSONB
```

DSN does **not** embed config — only server URL, project id, and ingest key.

### Client endpoint

**`GET /v1/client/config`**  
**Auth:** `Authorization: Bearer sk_live_...`

Response:

```json
{
  "ok": true,
  "configVersion": 3,
  "updatedAt": "2026-06-21T20:00:00Z",
  "sdk": {
    "enabledLevels": ["error", "warning"],
    "enableFlutterHooks": true,
    "trackNavigation": true,
    "networkCaptureBodies": false,
    "networkSlowThresholdMs": 3000,
    "networkIgnoreStatusCodes": [401, 403]
  }
}
```

Ingest `202` responses also include `configVersion` so the SDK can detect changes later.

### Dashboard endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| `GET` | `/api/projects/:id/settings` | JWT | Read current config |
| `PATCH` | `/api/projects/:id/settings` | JWT (write) | Update config, bumps `configVersion` |

PATCH body:

```json
{
  "sdk": {
    "enabledLevels": ["error", "warning"],
    "enableFlutterHooks": true,
    "trackNavigation": true,
    "networkCaptureBodies": false,
    "networkSlowThresholdMs": 3000,
    "networkIgnoreStatusCodes": [401]
  }
}
```

Dashboard UI: project sidebar → **Settings** (`/p/:projectId/settings`).

### Shared schema (`scout_models`)

Types: `ProjectSdkConfig`, `ProjectRemoteConfig` in `sdk_config.dart`.

| Field | Type | Default | SDK effect |
|-------|------|---------|------------|
| `enabledLevels` | `string[]` | all four levels | Drop events below unchecked levels in `_record()` |
| `enableFlutterHooks` | `bool` | `true` | `FlutterError.onError` + platform crash handler |
| `trackNavigation` | `bool` | `true` | Screen trail + nav observer |
| `networkCaptureBodies` | `bool` | `true` | Request/response bodies in network events |
| `networkSlowThresholdMs` | `int` | `3000` | Flag slow requests (`500–60000`) |
| `networkIgnoreStatusCodes` | `int[]` | `[]` | Skip network logging for these HTTP codes |

Validation helpers: `normalizeEnabledLevels`, `normalizeStatusCodes`, `clampSlowThreshold`.

### SDK implementation checklist

- [ ] **`RemoteConfigClient`** — `GET /v1/client/config` via private ingest Dio
- [ ] **Fetch on init** — before queue starts, merge into `ScoutOptions` via `withRemote()`
- [ ] **Refresh on resume** — compare `configVersion`, re-merge when newer
- [ ] **`useRemoteConfig`** — local opt-out (`false` skips fetch)
- [ ] **Fail-open** — if fetch fails, use local/code defaults; do not disable Scout
- [ ] **`enabledLevels`** — honor in `_record()` (already gates log/capture calls)
- [ ] **`networkIgnoreStatusCodes`** — early return in `recordNetwork()` when status matches

### Merge precedence

| Layer | Source |
|-------|--------|
| 1 | Code defaults (`ScoutOptions` const) |
| 2 | Remote config from dashboard (when `useRemoteConfig: true`) |
| 3 | Local-only fields always stay local: `environment`, `release`, redaction lists, `flushInterval`, DSN |

Remote wins for the six `sdk` fields above. Local `useRemoteConfig: false` disables remote entirely.

### Local override example

```dart
await Scout.init(dsn, options: const ScoutOptions(
  useRemoteConfig: true,
  networkIgnoreStatusCodes: {401}, // used until remote loads; then remote wins
));
```

### Verify remote config

1. Dashboard → project → **Settings**
2. Uncheck **INFO** log level, add **401** to ignore codes → **Save**
3. Relaunch app (or background → foreground)
4. `Scout.instance.options.enabledLevels` should exclude `info`
5. API call returning 401 should not appear under **Events**

### Export note

When exporting **scout_logger_plus** to its own repo, ensure `pubspec.yaml` pins a `scout_models` ref that includes `sdk_config.dart`, and document §16 in the exported README (or link back to this file).
