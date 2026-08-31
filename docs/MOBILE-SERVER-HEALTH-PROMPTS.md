# Mobile server health — agent prompts

Copy these prompts into any AI agent (Cursor, ChatGPT, Claude, etc.) to build a **standard API reference MD** from your mobile app, then convert it into a **Scout-compatible Dart health-check script**.

**Workflow**

1. Run **Prompt 1** in your app repo → save output as `docs/API-HEALTH-REFERENCE.md` (or similar).
2. Run **Prompt 2** with that MD file → paste the Dart script into Scout dashboard **Server health**.
3. Save once, re-run after every deploy.

See also: [MOBILE-SERVER-HEALTH.md](./MOBILE-SERVER-HEALTH.md) for Scout script contract and dashboard usage.

---

## Prompt 1 — Generate the API reference MD

Copy everything inside the block below. Replace `{APP_NAME}` and `{SOURCE_HINTS}` before sending.

````
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
| `method` | GET \| POST \| PUT \| PATCH \| DELETE \| POST_BYTES \| POST_FORM \| PUT_FORM \| DOWNLOAD |
| `path` | Relative path or full URL pattern (`{{var}}` = runtime placeholder) |
| `base` | Named base URL key from Base URLs table |
| `client` | Client profile if app uses multiple API clients (e.g. citizen \| app \| raw) |
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
````

---

## Prompt 2 — Convert MD → Scout Dart script

After Prompt 1 produces your MD file, copy the block below. Attach or paste the full MD content where indicated.

````
You are converting an **API Calls Reference** markdown file into a **single Dart health-check script** that runs on Scout Logger (no pubspec, no external packages).

## Input

Paste the full API reference MD below:

---BEGIN API REFERENCE MD---
{PASTE YOUR docs/API-HEALTH-REFERENCE.md CONTENT HERE}
---END API REFERENCE MD---

## Scout output contract (mandatory)

The script's **last stdout line** must be exactly one JSON object:

```json
{
  "verdict": "healthy",
  "summary": "Human one-liner",
  "checks": [
    {
      "name": "auth.login",
      "status": "ok",
      "url": "https://full-url-called",
      "latencyMs": 142,
      "detail": "HTTP 200"
    }
  ]
}
```

| Field | Rule |
|-------|------|
| `verdict` | `healthy` if 0 failures; `degraded` if some but not all failed; `unhealthy` if all failed or auth prerequisite failed |
| `summary` | Short sentence, e.g. `"12/14 read checks passed"` |
| `checks[].name` | Use the `id` from the MD table |
| `checks[].status` | `ok` if HTTP 2xx (or expected success); else `fail` |
| `checks[].url` | Full URL that was requested |
| `checks[].latencyMs` | Round-trip milliseconds |
| `checks[].detail` | `HTTP {code}` or exception message |

## Dart script rules

- Single file, `Future<void> main() async`, imports: `dart:convert`, `dart:io` only.
- Use `HttpClient` (no dio/http package).
- Put **all config as Dart constants at the top** of the script (base URLs, civilId, API keys, credentials). Do **not** use `Platform.environment` or server `.env`.
- Example: `const citizenBaseUrl = '...';`, `const testCivilId = '...';`, `const includeWrite = false;`
- At top of file: a `const _enabledIds = {...}` or `skipWrite = true` flag — **by default only run `safe: read` endpoints** listed in the MD.
- Follow **Suggested script execution order** from the MD.
- Honor `depends_on`: run prerequisites first; store tokens/ids in local variables (e.g. after `auth.login` store JWT for `citizen_token` calls).
- Implement auth modes from the MD:
  - `none` — no extra headers
  - `app_key` — header from env
  - `citizen_token` — `epamobkey` or equivalent from login response
  - `eprocess_creds` — securUser/securPass in URL or body per MD
  - `github_token` — `Authorization: token {env}`
- Set headers from **Common headers** + per-client headers (`x-epa-system`, etc.) as documented.
- Replace `{{placeholders}}` with env vars or dummy test values (document required env vars in a comment block at top).
- Timeout per request: 10 seconds. Overall script must finish within 280 seconds (Scout run limit 300s).
- On each check, append to a `checks` list; never exit early without printing final JSON.
- Skip `safe: write` endpoints unless `includeWrite == true` in script config.
- Skip `DOWNLOAD` / binary endpoints unless `includeDownload == true` — mark as skipped in summary, not fail.
- For external/HTML scraping endpoints, optionally skip or do HEAD/GET with short timeout and accept 200/301/302 as ok.

## Code structure (required)

```dart
// --- Config ---
const citizenBaseUrl = 'https://staging-api.example.com';
const testCivilId = '123456789012';

import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final checks = <Map<String, dynamic>>[];
  final bases = {'citizen': citizenBaseUrl};
  // run ordered ids, respect depends_on, collect checks
  stdout.writeln(jsonEncode({...})); // MUST be last line
}
```

## Mapping MD → code

- `base` column → lookup in a `Map<String, String> bases` built from env
- `path` with `{{var}}` → string replace from runtime vars / env
- `method` POST_FORM / PUT_FORM → multipart or application/x-www-form-urlencoded as app does (simplify if unknown; note in detail)
- Each table row with `safe: read` and in execution order → one check function returning a check map
- `checks[].name` **must equal** the row's `id` so Scout report matches the MD

## Output

Return **only the Dart source code** — no markdown fence explanation before/after unless one ```dart block. Ready to paste into Scout dashboard **Server health** script editor.
````

---

## Quick copy — EPA App example

For the EPA app specifically:

**Prompt 1** — set:
- `{APP_NAME}` → `EPA App`
- `{SOURCE_HINTS}` → `lib/core/api/end_points.dart`, `lib/features/*/data/*datasource*.dart`, `lib/core/network/dio_provider.dart`, `lib/core/services/remote_config_service.dart`, env in `lib/core/env/`

**Prompt 2** — paste the generated MD (same structure as the EPA API Calls Reference you already maintain).

---

## Checklist before saving in Scout

- [ ] Script ends with single `stdout.writeln(jsonEncode({...}))`
- [ ] Every executed check uses `name` = MD `id`
- [ ] Only `safe: read` by default
- [ ] Config is Dart constants at top of script (not `.env`)
- [ ] Auth flow runs first (`depends_on` satisfied)
- [ ] Test locally: `dart run health_check.dart` and validate JSON
