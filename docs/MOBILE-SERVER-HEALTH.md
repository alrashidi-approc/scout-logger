# Mobile server health checks

Each Scout project can upload a **Dart script** that probes the backend servers your mobile app depends on. Scout stores the script, runs it on demand, and keeps a history of results.

---

## Workflow

1. **Generate API reference** — use [MOBILE-SERVER-HEALTH-PROMPTS.md](./MOBILE-SERVER-HEALTH-PROMPTS.md) (Prompt 1) in your app repo to produce a standard MD file listing all endpoints.
2. **Convert to script** — use Prompt 2 in the same doc to turn that MD into a Dart script matching the report contract below.
3. **Deploy once** — paste the script in the dashboard (**Server health** tab) and save.
4. **Re-run anytime** — after a deploy or incident, click **Run check**; Scout executes the saved script on the server.
5. **Review report** — Scout parses the script output and shows verdict, summary, and per-check details.

---

## Script contract

- Language: **Dart** (SDK ^3.5).
- Entry: `main()` in a single file named `health_check.dart`.
- Output: print **one JSON object per check** to stdout (prefix `SCOUT_REPORT:`). Scout keeps the latest line — so timeouts still show completed checks.
- Allowed imports: Dart core libraries only (`dart:io`, `dart:convert`, `dart:async`, …). No `pubspec.yaml` — keep checks self-contained with `HttpClient`.
- Max size: **128 KB**.

### Report JSON shape

```json
{
  "verdict": "healthy",
  "summary": "12/14 read checks passed",
  "checks": [
    {
      "name": "Auth API",
      "status": "ok",
      "url": "https://api.example.com/health",
      "latencyMs": 142,
      "detail": "HTTP 200"
    }
  ],
  "stats": { "total": 14, "completed": 12, "ok": 11, "fail": 0, "timeout": 1, "skipped": 2, "pending": 0 },
  "current": "optional — check about to run",
  "pending": ["ids not started yet"],
  "timedOutAt": "optional — set when script or check times out"
}
```

| Field | Required | Values |
|-------|----------|--------|
| `verdict` | Yes | `healthy` · `degraded` · `unhealthy` |
| `summary` | Yes | Include counts, e.g. `8/14 ok — 1 timeout` |
| `checks` | Yes | Array of check results |
| `checks[].name` | Yes | MD `id` slug |
| `checks[].status` | Yes | `ok` · `fail` · `timeout` · `skipped` |
| `stats` | Yes | Running totals (see prompt helper) |
| `current` | Recommended | Check running **before** HTTP call |
| `pending` | Recommended | IDs not started yet |

### Configuration (in the script — not `.env`)

Put all URLs, test IDs, keys, and flags as **Dart constants at the top** of the script. Edit them in the dashboard **Server health** editor and **Save script** — they deploy with the script.

```dart
const citizenBaseUrl = 'https://staging-api.example.com';
const testCivilId = '123456789012';
const appApiKey = 'your-app-key';
const includeWrite = false;
```

Scout may inject `SCOUT_PROJECT_ID` / `SCOUT_PUBLIC_URL` at runtime — optional; do not rely on server `.env` for health checks.

---

## Example script

```dart
import 'dart:convert';
import 'dart:io';

const authHealthUrl = 'https://api.example.com/health';
const gatewayHealthUrl = 'https://gateway.example.com/health';

Future<void> main() async {
  final targets = [
    ('Auth API', authHealthUrl),
    ('Gateway', gatewayHealthUrl),
  ];

  final checks = <Map<String, dynamic>>[];
  var failures = 0;

  for (final (name, url) in targets) {
    final sw = Stopwatch()..start();
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 15));
      final res = await req.close().timeout(const Duration(seconds: 15));
      sw.stop();
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      if (!ok) failures++;
      checks.add({
        'name': name,
        'status': ok ? 'ok' : 'fail',
        'url': url,
        'latencyMs': sw.elapsedMilliseconds,
        'detail': 'HTTP ${res.statusCode}',
      });
      client.close(force: true);
    } catch (e) {
      sw.stop();
      failures++;
      checks.add({
        'name': name,
        'status': 'fail',
        'url': url,
        'latencyMs': sw.elapsedMilliseconds,
        'detail': '$e',
      });
    }
  }

  stdout.writeln(jsonEncode({
    'verdict': failures == 0
        ? 'healthy'
        : failures < targets.length
            ? 'degraded'
            : 'unhealthy',
    'summary': failures == 0
        ? 'All ${targets.length} servers OK'
        : '$failures of ${targets.length} checks failed',
    'checks': checks,
  }));
}
```

Set project-specific URLs in the script config block at the top — save in the dashboard.

---

## API

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/api/projects/:id/health-check` | Script + latest run |
| `PUT` | `/api/projects/:id/health-check/script` | Save script (write access) |
| `POST` | `/api/projects/:id/health-check/run` | Execute saved script |
| `GET` | `/api/projects/:id/health-check/runs` | Run history |
| `GET` | `/api/projects/:id/health-check/runs/:runId` | Single run detail |

---

## Limits

- One run at a time per project.
- Run timeout: **300 seconds** (server bundles Linux Dart SDK at `/opt/dart/bin/dart` for `dart run` scripts).
- Requires project **write** access to save or trigger runs.
