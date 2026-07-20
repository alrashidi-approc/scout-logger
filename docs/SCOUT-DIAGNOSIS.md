# Scout Diagnosis — SDK feature spec

Structured, human-readable failure explanation for crashes and errors.  
The dashboard shows a **Diagnosis** panel when `payload.diagnosis` is present.

**Related:** [SDK ↔ dashboard compatibility](./SDK-DASHBOARD-COMPAT.md) · [Network readable](./SDK-DASHBOARD-COMPAT.md#6-network-events-dio-interceptor)

---

## Goal

Move from “stack trace only” to “what happened, why, and what to try next” — without forcing every app team to hand-write dashboard copy.

| Layer | Responsibility |
|-------|----------------|
| **SDK** | Collect evidence, run classifiers, attach `payload.diagnosis` |
| **App** | Optional override when business context is known |
| **Dashboard** | Render diagnosis first; stack trace stays in Technical |

---

## Payload contract

Attach under **`payload.diagnosis`** on `error`, `crash`, and optionally `network` events.

### Canonical shape

```json
{
  "diagnosis": {
    "summary": "Firebase App Check token fetch failed",
    "likelyCause": "Debug App Check mode is enabled but the debug token is not registered",
    "confidence": "high",
    "category": "auth_security",
    "operation": "device_bootstrap",
    "stage": "app_check",
    "source": "sdk_auto",
    "evidence": [
      { "label": "Provider", "value": "firebase_app_check" },
      { "label": "HTTP status", "value": "403" },
      { "label": "Response code", "value": "permission-denied" },
      { "label": "Debug mode", "value": "enabled" }
    ],
    "nextSteps": [
      "Disable debug App Check for this build",
      "Or register the debug token in Firebase Console"
    ]
  }
}
```

### Field reference

| Field | Type | Required | Dashboard use |
|-------|------|----------|---------------|
| `summary` | `string` | **Yes** (if block present) | Main headline |
| `likelyCause` | `string` | Recommended | “Why it likely failed” |
| `confidence` | `low` \| `medium` \| `high` | Optional | Badge |
| `category` | `string` | Optional | Grouping / filters (future) |
| `operation` | `string` | Optional | Pipeline name (e.g. `device_bootstrap`) |
| `stage` | `string` | Optional | Step within operation (e.g. `app_check`) |
| `source` | `sdk_auto` \| `app_manual` \| `server_enriched` | Optional | Provenance |
| `evidence` | `{ label, value }[]` | Optional | Key facts table |
| `nextSteps` | `string[]` | Optional | Suggested fixes list |

### Evidence item

```json
{ "label": "HTTP status", "value": "403" }
```

`value` may be string, number, or bool — dashboard stringifies for display.

### Optional context block

SDK may also send supporting data (not required for dashboard v1):

```json
"diagnosisContext": {
  "route": "/splash",
  "lastNetworkFailure": {
    "url": "https://…",
    "statusCode": 403
  },
  "recentBreadcrumbs": ["splash pipeline", "device bootstrap", "app check"]
}
```

Dashboard v1 reads **`diagnosis` only**. Context can be folded into `evidence` for now.

---

## SDK public API (proposed)

### Manual — app override

```dart
await Scout.captureException(
  error,
  stackTrace: stackTrace,
  diagnosis: ScoutDiagnosis(
    summary: 'App Check token unavailable',
    likelyCause: 'Debug token not registered for this app',
    confidence: ScoutDiagnosisConfidence.high,
    evidence: {
      'HTTP status': 403,
      'Debug mode': true,
    },
    nextSteps: [
      'Register debug token in Firebase Console',
    ],
    operation: 'device_bootstrap',
    stage: 'app_check',
    source: ScoutDiagnosisSource.appManual,
  ),
);
```

### Automatic — SDK classifiers

If the app does not pass `diagnosis`, SDK runs internal classifiers (network, App Check, auth, timeout, platform exceptions, etc.) and sets `source: sdk_auto`.

**Precedence:** `app_manual` > `sdk_auto` > none (dashboard falls back to stack/breadcrumbs).

### Operation tracing (recommended)

```dart
await Scout.runOperation(
  'device_bootstrap',
  stage: 'app_check',
  fn: () => fetchAppCheckToken(),
);
```

On failure, SDK attaches `operation`, `stage`, route, and recent breadcrumbs into diagnosis automatically.

---

## SDK implementation checklist

| # | Task | File (suggested) |
|---|------|------------------|
| 1 | `ScoutDiagnosis` model + JSON serializer | `lib/diagnosis/diagnosis.dart` |
| 2 | Merge diagnosis into event payload on capture | `lib/scout.dart` |
| 3 | Classifier registry | `lib/diagnosis/diagnosis_engine.dart` |
| 4 | App Check / Firebase classifier | `lib/diagnosis/classifiers/app_check_classifier.dart` |
| 5 | Network / Dio classifier (reuse fault info) | `lib/diagnosis/classifiers/network_classifier.dart` |
| 6 | Auth / 401–403 classifier | `lib/diagnosis/classifiers/auth_classifier.dart` |
| 7 | `runOperation` wrapper | `lib/operation_tracer.dart` |
| 8 | Attach evidence from breadcrumbs + last network failure | `lib/diagnosis/evidence_collector.dart` |
| 9 | Export in `scout_models` (optional shared types) | `packages/scout_models/lib/src/diagnosis.dart` |

### Classifier output

Each classifier returns `ScoutDiagnosis?`. First match with `confidence >= medium` wins, unless app already supplied diagnosis.

Example App Check classifier inputs:
- exception message contains “App Check”
- optional `appCheck` block on payload
- HTTP 403 from token endpoint in same session

Example output:

```dart
ScoutDiagnosis(
  summary: 'Firebase App Check token fetch failed',
  likelyCause: 'Debug App Check mode is enabled',
  confidence: ScoutDiagnosisConfidence.high,
  category: 'auth_security',
  evidence: {'HTTP status': 403, 'Debug mode': true},
  nextSteps: [
    'Disable appCheckDebug for production-like builds',
    'Register debug token in Firebase Console if debug mode is intentional',
  ],
  source: ScoutDiagnosisSource.sdkAuto,
);
```

---

## Dashboard behavior

When `payload.diagnosis.summary` (or `likelyCause`) is non-empty:

1. **Overview** group shows **Diagnosis** card (above “What happened”).
2. Card shows: summary, likely cause, confidence, evidence, next steps.
3. **Technical → Stack trace** unchanged — diagnosis does not replace debugging detail.

Parser: `apps/dashboard/lib/utils/event_view.dart` → `EventView.diagnosis`, `hasDiagnosis`.

UI: `apps/dashboard/lib/widgets/event_detail_widgets.dart` → `DiagnosisPanel`.

---

## Compatibility matrix

| Dashboard feature | Needs from SDK |
|-------------------|----------------|
| Diagnosis card | `payload.diagnosis.summary` or `likelyCause` |
| Evidence table | `payload.diagnosis.evidence[]` |
| Suggested fixes | `payload.diagnosis.nextSteps[]` |
| Operation / stage chips | `operation`, `stage` |
| Confidence badge | `confidence` |

Events without `diagnosis` behave exactly as today.

---

## Example: App Check crash (full event excerpt)

```json
{
  "type": "crash",
  "timestamp": "2026-07-20T07:46:51.820Z",
  "payload": {
    "message": "Firebase App Check token unavailable.",
    "stack": "#0 FirebaseAppCheckAttestationProvider.fetchToken …",
    "level": "error",
    "category": "crashing",
    "screen": { "currentRoute": "/splash" },
    "context": { "operation": "device_bootstrap_launch-auth-retry" },
    "diagnosis": {
      "summary": "Firebase App Check token fetch failed",
      "likelyCause": "App Check debug mode is enabled; debug token is not allowed for this build",
      "confidence": "high",
      "category": "auth_security",
      "operation": "device_bootstrap",
      "stage": "app_check",
      "source": "sdk_auto",
      "evidence": [
        { "label": "Provider", "value": "firebase_app_check" },
        { "label": "HTTP status", "value": "403" },
        { "label": "Route", "value": "/splash" },
        { "label": "Debug mode", "value": "enabled" }
      ],
      "nextSteps": [
        "Disable appCheckDebug for this build",
        "Or register the debug token in Firebase Console"
      ]
    }
  }
}
```

---

## Rollout phases

### Phase 1 — Contract + manual API (ship first)
- [ ] This document + dashboard panel
- [ ] `ScoutDiagnosis` + `captureException(..., diagnosis:)`
- [ ] Apps can opt in per catch site

### Phase 2 — Auto classifiers
- [ ] App Check, network, auth, timeout, platform
- [ ] Evidence from session (breadcrumbs, last network error)

### Phase 3 — Operations
- [ ] `Scout.runOperation` / stage tracing
- [ ] Issue-level diagnosis rollup (same fingerprint → common cause)

### Phase 4 — Platform
- [ ] Server enrichment (`source: server_enriched`)
- [ ] Remote diagnosis playbooks from project settings (future)

---

## Verify

1. Send a test event with `payload.diagnosis` via ingest or SDK.
2. Open **Events** → event detail → **Overview**.
3. Confirm **Diagnosis** card appears with summary, cause, evidence, next steps.
4. Confirm **Technical → Stack trace** still shows below.

---

## Related platform files

| Area | Path |
|------|------|
| This spec | `docs/SCOUT-DIAGNOSIS.md` |
| SDK compat checklist | `docs/SDK-DASHBOARD-COMPAT.md` |
| Dashboard parser | `apps/dashboard/lib/utils/event_view.dart` |
| Dashboard UI | `apps/dashboard/lib/widgets/event_detail_widgets.dart` |
| Event detail screen | `apps/dashboard/lib/screens/event_detail_screen.dart` |
| Network readable (pattern to mirror) | `packages/scout_models/lib/src/network_readable.dart` |

When adding shared types, extend `packages/scout_models` and bump the git ref in **scout_logger_plus**.
