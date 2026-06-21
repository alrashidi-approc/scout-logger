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

Dashboard project DSN format: `{PUBLIC_URL}/v1/events/batch` with ingest key `sk_live_...`.

```dart
await Scout.initFromEnv(); // reads SCOUT_DSN from .env
// or
await Scout.init(dsn: 'http://localhost:8080/v1/events/batch?key=sk_live_...');
```

Optional: `ScoutEnv` / flush interval / enable in debug.

---

## 11. Package file checklist

Suggested layout in **scout_logger_plus**:

| File | Responsibility |
|------|----------------|
| `lib/scout.dart` | Public API: init, captureException, log, setUser, setContext |
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
3. **Network interceptor** — network tab + issues  
4. **Session heartbeats + summary** — analytics sessions  
5. **Crash binding + queue** — reliability  

---

## 15. Related platform files

| Area | Path |
|------|------|
| Navigation contract | `packages/scout_models/lib/src/navigation.dart` |
| Event types / levels | `packages/scout_models/lib/src/taxonomy.dart` |
| Dashboard payload parser | `apps/dashboard/lib/utils/event_view.dart` |
| Timeline UI | `apps/dashboard/lib/widgets/event_detail_widgets.dart` → `BreadcrumbTrail` |
| Session timeline merge | `apps/server/lib/store/analytics_store.dart` → `_mergeTrail` |
| Export SDK to own repo | `scripts/export-sdk-repo.sh` |

When `scout_models` changes, bump the git ref in **scout_logger_plus** `pubspec.yaml` and re-export the SDK repo.
