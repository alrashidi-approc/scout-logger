/// Copy-paste agent prompts for the Server health dashboard.
abstract final class HealthCheckPrompts {
  static const prompt1GenerateApiReference = '''
You are analyzing a mobile app codebase to produce a **machine-readable API reference markdown file** for building an automated smoke-test / health-check script later.

## Your task

Scan the repo and write **one markdown document** titled:

`{APP_NAME} — API Calls Reference`

Subtitle: `Grouped by scenario for building an API smoke-test / health-check script.`

State the **source of truth** paths you used (e.g. `lib/core/api/end_points.dart`, `lib/features/*/data/*_datasource.dart`, OpenAPI specs, Retrofit interfaces, etc.).

## Required document structure

Follow this structure exactly. Use the EPA example below as the format reference — same sections, tables, and field names.

### Top matter

1. Title + subtitle + source-of-truth line
2. **Script control fields** — table explaining each column used in API entry tables
3. **Base URLs** table — named keys → env/config source → what they are used for
4. **Auth modes** table — mode name → headers/params → when to use
5. **Common headers** — bullets for shared headers on JSON calls

### Script control fields (must appear as a table)

| Field | Description |
|-------|-------------|
| `id` | Stable slug for enable/disable in script — **becomes `checks[].name` in Scout dashboard** (filters, cURL, copy URL) |
| `method` | GET | POST | PUT | PATCH | DELETE | POST_BYTES | POST_FORM | PUT_FORM | DOWNLOAD |
| `path` | Relative path or full URL pattern (`{{var}}` = runtime placeholder) |
| `base` | Named base URL key from Base URLs table |
| `client` | Client profile if app uses multiple API clients (e.g. citizen | app | raw) |
| `auth` | Auth mode from Auth modes table |
| `body` | JSON template, form notes, or entity reference |
| `depends_on` | Prerequisite call IDs (comma-separated, e.g. `auth.login`) |
| `safe` | `read` = safe to call repeatedly; `write` = creates/modifies data |

### Per-scenario sections

For each feature/scenario (Auth, Home, Payments, …):

- `## N. {Scenario name}`
- One markdown table with columns: `id`, `method`, `path`, `base`, `client`, `auth`, `body`, `depends_on`, `safe`
- Optional **Notes** bullets (token storage, retry behavior, special headers)
- `Source: {file path(s)}` line

Group endpoints logically (same as app features). Include **external** third-party URLs in their own section.

### Closing sections (required)

1. **Suggested script execution order** — numbered list of **every `id`** that the health script should run (read checks first, then optional write). Scout uses this order for progress UI.
2. **Skip in automated checks** — list `safe: write` endpoints to skip unless test accounts exist
3. **Unused endpoint constants** — constants defined but never called (if any)
4. **Features with no API implementation** — stubs with no real calls (if any)

## Rules

- Every real network call in the app must appear exactly once with a unique `id` (dot-separated slug, e.g. `auth.login`, `home.applications`).
- IDs must be stable across releases — Scout history compares runs by `id`.
- Use `{{placeholder}}` for runtime values (civilId, tokens, userId, etc.) — do not invent real secrets in the MD.
- Map `base` to keys in the Base URLs table, not raw URLs in the path column (unless `external`).
- Infer auth from interceptors/Dio providers/API clients — document how tokens/keys are attached.
- Mark `safe: read` for GET/list/lookup/smoke calls; `safe: write` for create/update/delete/pay/vote.
- If method is not plain GET/POST, use extended method names (POST_FORM, DOWNLOAD, etc.).
- Do **not** write Dart code in this step — **markdown only**.
- Be exhaustive: datasources, repositories, API services, generated clients, env config files.

## Source hints for this project

{SOURCE_HINTS}

Example: `lib/core/api/end_points.dart`, `lib/features/*/data/*datasource*.dart`, `.env`, `lib/core/network/`

## Format reference (match this style)

Use the same tone, table layout, and section numbering as this excerpt:

```markdown
# EPA App — API Calls Reference
Grouped by scenario for building an API smoke-test / health-check script.

Source of truth: lib/core/api/end_points.dart + feature datasources under lib/features/*/data/.

## Script control fields
| Field | Description |
| id | Stable slug for enable/disable in script |
| method | GET | POST | PUT | ... |
...

## 1. Auth
| id | method | path | base | client | auth | body | depends_on | safe |
| auth.login | POST | /mob/auth | citizen | citizen | app_key | "{{civilId}}" | — | write |
...

## Suggested script execution order
1. auth.login → store token
2. home.applications
...

Skip safe: write endpoints in automated health checks unless using test accounts.
```

## Output

Return the **complete markdown file** only. No preamble, no "here is your file". Start with `# {APP_NAME} — API Calls Reference`.
''';

  static const prompt2ConvertToDartScript = '''
You are converting an **API Calls Reference** markdown file into a **single Dart health-check script** that runs on Scout Logger (no pubspec, no external packages).

The script must emit **incremental `SCOUT_REPORT:` lines** so the Scout dashboard shows live progress, per-check URLs, HTTP codes, latency, cURL copy, and issue filters — same UX for every project.

## Input

Paste the full API reference MD below:

---BEGIN API REFERENCE MD---
{PASTE YOUR docs/API-HEALTH-REFERENCE.md CONTENT HERE}
---END API REFERENCE MD---

## Scout dashboard contract (mandatory — all projects)

Scout reads **stdout line by line**. Each line must be either:
- `SCOUT_REPORT:{json}` — progress + final report (required), or
- nothing else on stdout (no debug prints on stdout).

Human logs go to **stderr only**: `stderr.writeln('→ auth.login');`

After **every** `stdout.writeln('SCOUT_REPORT:...')` call **`stdout.flush()`** (Scout runs the script in a pipe).

### JSON shape (emit after each check + before starting next)

```json
{
  "verdict": "degraded",
  "summary": "3/22 done — running home.applications (0 fail, 1 timeout)",
  "checks": [
    {
      "name": "auth.login",
      "status": "ok",
      "url": "https://api.example.com/mob/auth",
      "latencyMs": 811,
      "detail": "HTTP 200"
    },
    {
      "name": "falcon.list",
      "status": "timeout",
      "url": "https://api.example.com/apirouter/app/falcon/list",
      "latencyMs": 10000,
      "detail": "TimeoutException after 10s"
    }
  ],
  "stats": {
    "total": 22,
    "completed": 2,
    "ok": 1,
    "fail": 0,
    "timeout": 1,
    "skipped": 0,
    "pending": 19
  },
  "current": "home.applications",
  "pending": ["jahra.visit.list", "john.ships"]
}
```

| Field | Rule |
|-------|------|
| `verdict` | `healthy` if 0 fail/timeout and 0 pending · `degraded` if some ok but any fail/timeout/pending · `unhealthy` if auth prerequisite failed or 0 ok with failures |
| `summary` | Counts always: in-progress `"N/total done — running {id}"` · final `"N/total ok, F fail, T timeout"` |
| `checks[].name` | **Exact** MD table `id` (e.g. `auth.login`) |
| `checks[].status` | `ok` · `fail` · `timeout` · `skipped` |
| `checks[].url` | **Full URL** attempted (required whenever URL is known — dashboard Copy URL / Open / cURL) |
| `checks[].latencyMs` | Round-trip ms (use ~10000 on timeout) |
| `checks[].detail` | **Strict format** — see below (dashboard parses HTTP code) |
| `stats` | **Required** on every emit — running totals |
| `current` | Set **before** HTTP call; omit on final emit when done |
| `pending` | IDs not started yet (after `current`) |

### `detail` field format (required for dashboard)

| Situation | `detail` value |
|-----------|----------------|
| HTTP response | `HTTP {statusCode}` e.g. `HTTP 200`, `HTTP 404` |
| Timeout | `TimeoutException after 10s` |
| Skipped write | `skipped: write endpoint` |
| Skipped download | `skipped: download endpoint` |
| Other error | Short exception: `SocketException: ...` |

Never use vague details like `"OK"` or `"failed"` — always include HTTP code or exception name.

## Critical: incremental progress

1. Build `allIds` from **Suggested script execution order** (read checks; include write only if `includeWrite`).
2. **Before** each HTTP call: set `current`, compute `pending`, call `emitReport(checks, allIds, current: id, pending: pending)`.
3. **After** each call: append check map to `checks`, call `emitReport` again with `current: null` for that step (or set next `current` before next call).
4. Per-check timeout: **10 seconds** on connect + response (never 15+).
5. Global deadline: **280 seconds** — then mark remaining IDs as `skipped` with `detail: "skipped: global deadline"` and emit final report.
6. On timeout/fail for one check: **continue** to next (do not exit early).
7. If a **direct** `depends_on` prerequisite failed: skip with `status: skipped`, `detail: "skipped: depends on {id}"` — **only the IDs listed in that row's `depends_on` column**, never unrelated auth chains.

## Auth chains — do not mix (critical)

Apps often have **separate** API backends. `depends_on` must reflect **only direct** prerequisites:

| Chain | Login check | Endpoints | depends_on |
|-------|-------------|-----------|------------|
| Citizen / mobapp | `auth.login` | `home.*`, `falcon.*`, `jahra.*`, … | `auth.login` only |
| E-process | `eprocess.login` | `eprocess.*` (inbox, lookups, site_allowance, …) | `eprocess.login` only — **never `auth.login`** |
| External | none | `news.*`, `config.github_*` | `—` |

**Wrong:** `eprocess.site_allowance.query` skipped because `auth.login` timed out.
**Right:** run `eprocess.site_allowance.query` when `eprocess.login` is `ok`, even if `auth.login` failed.

```dart
bool prereqFailed(String depId, List<Map<String, dynamic>> checks) {
  final row = checks.cast<Map<String, dynamic>?>().whereType<Map<String, dynamic>>().where((c) => c['name'] == depId);
  if (row.isEmpty) return true;
  return row.first['status'] != 'ok';
}

// For each endpoint, read depends_on from MD (comma-separated) — skip only if ANY *listed* dep failed:
bool shouldSkip(List<String> deps, List<Map<String, dynamic>> checks) =>
    deps.any((d) => d.isNotEmpty && prereqFailed(d.trim(), checks));
```

Do **not** use a global "if auth.login failed skip everything" guard.

## Required helpers (copy verbatim into script)

```dart
import 'dart:convert';
import 'dart:io';

const globalDeadline = Duration(seconds: 280);
const checkTimeout = Duration(seconds: 10);

bool pastDeadline(Stopwatch sw) => sw.elapsed >= globalDeadline;

void emitReport({
  required List<Map<String, dynamic>> checks,
  required List<String> allIds,
  String? current,
  List<String> pending = const [],
}) {
  final ok = checks.where((c) => c['status'] == 'ok').length;
  final fail = checks.where((c) => c['status'] == 'fail').length;
  final timeout = checks.where((c) => c['status'] == 'timeout').length;
  final skipped = checks.where((c) => c['status'] == 'skipped').length;
  final completed = checks.length;
  final total = allIds.length;
  final pendingN = pending.isNotEmpty ? pending.length : total - completed - (current == null ? 0 : 1);
  final verdict = fail + timeout == 0 && pendingN == 0
      ? 'healthy'
      : ok > 0
          ? 'degraded'
          : 'unhealthy';
  final summary = current == null
      ? '\$ok/\$total ok\${fail > 0 ? ', \$fail fail' : ''}\${timeout > 0 ? ', \$timeout timeout' : ''}\${skipped > 0 ? ', \$skipped skipped' : ''}'
      : '\$completed/\$total done — running \$current\${fail + timeout > 0 ? ' (\$fail fail, \$timeout timeout)' : ''}';
  stdout.writeln('SCOUT_REPORT:\${jsonEncode({
    'verdict': verdict,
    'summary': summary,
    'checks': checks,
    'stats': {
      'total': total,
      'completed': completed,
      'ok': ok,
      'fail': fail,
      'timeout': timeout,
      'skipped': skipped,
      'pending': pendingN,
    },
    if (current != null) 'current': current,
    if (pending.isNotEmpty) 'pending': pending,
  })}');
  stdout.flush();
}

Map<String, dynamic> checkResult({
  required String name,
  required String status,
  required String url,
  required int latencyMs,
  required String detail,
}) => {
      'name': name,
      'status': status,
      'url': url,
      'latencyMs': latencyMs,
      'detail': detail,
    };
```

## Per-check runner pattern (required)

Use one async function per MD row. Always capture URL **before** the request so timeouts still have a URL:

```dart
Future<Map<String, dynamic>> runGet(String id, String url, {Map<String, String>? headers}) async {
  final sw = Stopwatch()..start();
  stderr.writeln('→ \$id');
  try {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(url)).timeout(checkTimeout);
    if (headers != null) headers.forEach(req.headers.set);
    final res = await req.close().timeout(checkTimeout);
    sw.stop();
    final code = res.statusCode;
    await res.drain();
    client.close(force: true);
    final ok = code >= 200 && code < 300;
    return checkResult(
      name: id,
      status: ok ? 'ok' : 'fail',
      url: url,
      latencyMs: sw.elapsedMilliseconds,
      detail: 'HTTP \$code',
    );
  } on TimeoutException {
    sw.stop();
    return checkResult(name: id, status: 'timeout', url: url, latencyMs: sw.elapsedMilliseconds, detail: 'TimeoutException after 10s');
  } catch (e) {
    sw.stop();
    return checkResult(name: id, status: 'fail', url: url, latencyMs: sw.elapsedMilliseconds, detail: '\$e');
  }
}
```

Adapt for POST/POST_FORM using the same `checkResult` + `detail: 'HTTP \$code'` pattern.

## Dart script rules

- Single file, `Future<void> main() async`, imports: `dart:convert`, `dart:io` only.
- Use `HttpClient` (no dio/http package).
- **All config as Dart constants at the top** — base URLs, test civilId, API keys, credentials. Do **not** use `Platform.environment` or server `.env`.
- `const includeWrite = false;` · `const includeDownload = false;` by default.
- **By default only run `safe: read`** endpoints from the MD.
- Follow **Suggested script execution order**; honor `depends_on`.
- Implement auth modes from the MD (`none`, `app_key`, `citizen_token`, `eprocess_creds`, `github_token`).
- Skip `safe: write` unless `includeWrite == true` — emit skipped check with `detail: "skipped: write endpoint"`.
- Skip DOWNLOAD unless `includeDownload == true` — `detail: "skipped: download endpoint"`.

## main() loop (required structure)

```dart
Future<void> main() async {
  final sw = Stopwatch()..start();
  final checks = <Map<String, dynamic>>[];
  final allIds = ['auth.login', 'home.applications', /* every id in execution order */];

  for (var i = 0; i < allIds.length; i++) {
    if (pastDeadline(sw)) break;
    final id = allIds[i];
    final pending = allIds.sublist(i + 1);

    if (!includeWrite && /* id is write-only from MD */) {
      checks.add(checkResult(name: id, status: 'skipped', url: '', latencyMs: 0, detail: 'skipped: write endpoint'));
      emitReport(checks: checks, allIds: allIds);
      continue;
    }

    emitReport(checks: checks, allIds: allIds, current: id, pending: pending);
    checks.add(await /* run check for id */);
    emitReport(checks: checks, allIds: allIds);
  }

  // Mark any not-run ids after deadline
  for (final id in allIds) {
    if (checks.any((c) => c['name'] == id)) continue;
    checks.add(checkResult(name: id, status: 'skipped', url: '', latencyMs: 0, detail: 'skipped: global deadline'));
  }
  emitReport(checks: checks, allIds: allIds);
}
```

## Mapping MD → code

- `base` → lookup in `Map<String, String> bases` from config constants
- `path` with `{{var}}` → replace from config / tokens from login
- `checks[].name` **must equal** MD `id` exactly
- `allIds.length` must match `stats.total` in every emit

## Validation checklist (before returning code)

- [ ] Every emit uses `SCOUT_REPORT:` prefix + `stdout.flush()`
- [ ] No stdout debug prints — stderr only for `→ id` lines
- [ ] Every check has `name`, `status`, `url`, `latencyMs`, `detail`
- [ ] Success/fail use `detail: "HTTP {code}"`
- [ ] Timeouts use `detail: "TimeoutException after 10s"`
- [ ] `stats` on every line; `current`/`pending` while running
- [ ] `depends_on` uses **direct** deps only — eprocess.* never depends on auth.login
- [ ] Scout attaches `networkProbe` automatically — script URLs in config are used for host probes

## Output

Return **only the Dart source code** — one ```dart block or raw source. Ready to paste into Scout **Server health** script editor.
''';
}
