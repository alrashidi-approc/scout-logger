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
| `id` | Stable slug for enable/disable in script |
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

1. **Suggested script execution order** — numbered list of `id` values respecting `depends_on` and auth flow
2. **Skip in automated checks** — list `safe: write` endpoints to skip unless test accounts exist
3. **Unused endpoint constants** — constants defined but never called (if any)
4. **Features with no API implementation** — stubs with no real calls (if any)

## Rules

- Every real network call in the app must appear exactly once with a unique `id` (dot-separated slug, e.g. `auth.login`, `home.applications`).
- Use `{{placeholder}}` for runtime values (civilId, tokens, userId, etc.) — do not invent real secrets.
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

## Input

Paste the full API reference MD below:

---BEGIN API REFERENCE MD---
{PASTE YOUR docs/API-HEALTH-REFERENCE.md CONTENT HERE}
---END API REFERENCE MD---

## Scout output contract (mandatory)

Scout reads **every stdout line**. After **each check** (and before starting the next), print a full progress report so timeouts still show what finished.

Prefix each line with `SCOUT_REPORT:` or print raw JSON (one object per line):

```
SCOUT_REPORT:{"verdict":"degraded","summary":"3/20 — auth.login ok, home.applications running","checks":[...],"stats":{...},"current":"home.applications","pending":["falcon.list",...]}
```

### Final JSON shape

```json
{
  "verdict": "healthy",
  "summary": "12/14 read checks passed",
  "checks": [
    {
      "name": "auth.login",
      "status": "ok",
      "url": "https://full-url-called",
      "latencyMs": 142,
      "detail": "HTTP 200"
    },
    {
      "name": "home.applications",
      "status": "timeout",
      "url": "https://...",
      "latencyMs": 10001,
      "detail": "TimeoutException after 10s"
    }
  ],
  "stats": {
    "total": 14,
    "completed": 8,
    "ok": 7,
    "fail": 0,
    "timeout": 1,
    "skipped": 2,
    "pending": 4
  },
  "current": "falcon.list",
  "pending": ["falcon.list", "john.ships"]
}
```

| Field | Rule |
|-------|------|
| `verdict` | `healthy` (0 fail/timeout) · `degraded` (some failed/timed out) · `unhealthy` (auth failed or all failed) |
| `summary` | Always include counts, e.g. `"8/14 ok — 1 timeout at home.applications"` |
| `checks[].name` | MD table `id` |
| `checks[].status` | `ok` · `fail` · `timeout` · `skipped` |
| `checks[].url` | Full URL requested |
| `checks[].latencyMs` | Round-trip ms |
| `checks[].detail` | `HTTP {code}`, exception, or `skipped: write endpoint` |
| `stats` | **Required** — running totals after each check |
| `current` | ID about to run (set **before** the HTTP call) |
| `pending` | IDs not started yet |

## Critical: incremental progress (prevents empty timeout reports)

1. Build ordered list of check IDs from MD (read-only by default).
2. Before each HTTP call: set `current`, update `pending`, call `emitReport(...)`.
3. After each HTTP call: append to `checks`, update `stats`, call `emitReport(...)` again.
4. Per-check HTTP timeout: **10 seconds** (never 15+). Use `.timeout(const Duration(seconds: 10))` on connect + response.
5. Global deadline: stop before **280s**; emit final report with remaining `pending` marked as skipped.
6. Log human-readable lines to **stderr** only (`stderr.writeln('→ auth.login ...')`).
7. After each `SCOUT_REPORT` line call **`stdout.flush()`** (required when Scout runs the script in a pipe).

## Required helper (include in generated script)

```dart
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
      ? '\$ok/\$total ok\${fail > 0 ? ', \$fail fail' : ''}\${timeout > 0 ? ', \$timeout timeout' : ''}'
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
```

## Dart script rules

- Single file, `Future<void> main() async`, imports: `dart:convert`, `dart:io` only.
- Use `HttpClient` (no dio/http package).
- **All config as Dart variables at the top of the script** — base URLs, test civilId, API keys, credentials. Do **not** use `Platform.environment` or server `.env` (script is saved in Scout and edited in the dashboard).
- Group config in a clear block, e.g. `const citizenBaseUrl = '...';`, `const testCivilId = '...';`, `const includeWrite = false;`.
- **By default only run `safe: read`** endpoints from the MD.
- Follow **Suggested script execution order**; honor `depends_on`.
- Implement auth modes from the MD (`none`, `app_key`, `citizen_token`, `eprocess_creds`, `github_token`).
- On single-check timeout: record `status: timeout` for that check, **continue** to next check.
- Skip `safe: write` unless `includeWrite == true` — add check with `status: skipped`.
- Skip DOWNLOAD/binary unless `includeDownload == true`.

## Code structure (required)

```dart
import 'dart:convert';
import 'dart:io';

// --- Config ---
const citizenBaseUrl = 'https://staging-api.example.com';
const eprocessBaseUrl = 'https://eprocess.example.com';
const testCivilId = '123456789012';
const appApiKey = 'your-app-key';
const includeWrite = false;
const includeDownload = false;

void emitReport({...}) { ... }

Future<void> main() async {
  final bases = {'citizen': citizenBaseUrl, 'eprocess': eprocessBaseUrl};
  final allIds = ['auth.login', 'home.applications', ...];
  ...
}
```

## Mapping MD → code

- `base` column → lookup in a `Map<String, String> bases` built from **config constants**
- `path` with `{{var}}` → string replace from config vars (`testCivilId`, tokens from login response, etc.)
- `method` POST_FORM / PUT_FORM → multipart or application/x-www-form-urlencoded as app does (simplify if unknown; note in detail)
- Each table row with `safe: read` and in execution order → one check function returning a check map
- `checks[].name` **must equal** the row's `id` so Scout report matches the MD

## Output

Return **only the Dart source code** — no markdown fence explanation before/after unless one ```dart block. Ready to paste into Scout dashboard **Server health** script editor.
''';
}
