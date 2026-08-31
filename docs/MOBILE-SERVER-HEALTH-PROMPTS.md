# Mobile server health — agent prompts

Copy these prompts into any AI agent (Cursor, ChatGPT, Claude, etc.) to build a **standard API reference MD** from your mobile app, then convert it into a **Scout-compatible Dart health-check script**.

**Workflow**

1. Run **Prompt 1** in your app repo → save output as `docs/API-HEALTH-REFERENCE.md` (or similar).
2. Run **Prompt 2** with that MD file → paste the Dart script into Scout dashboard **Server health**.
3. Save once, re-run after every deploy.

The dashboard **Server health** page has **Copy prompt** buttons — they match this doc. Prefer copying from the dashboard so you always get the latest contract.

See also: [MOBILE-SERVER-HEALTH.md](./MOBILE-SERVER-HEALTH.md) for Scout script contract and dashboard usage.

---

## Prompt 1 — Generate the API reference MD

Copy from dashboard **Server health → step 1**, or use the block below. Replace `{APP_NAME}` and `{SOURCE_HINTS}`.

Key points for Scout UI:

- Each table `id` becomes `checks[].name` in the report (filters, Copy URL, cURL).
- **Suggested script execution order** must list every check the script will run — Scout progress bar uses `stats.total`.

---

## Prompt 2 — Convert MD → Scout Dart script

Copy from dashboard **Server health → step 2**, or regenerate from `apps/dashboard/lib/utils/health_check_prompts.dart`.

### Contract summary (all projects)

| Requirement | Why |
|-------------|-----|
| `SCOUT_REPORT:{json}` on stdout after each check | Dashboard progress + timeout partial reports |
| `stdout.flush()` after each report | Pipe buffering when Scout runs script |
| stderr only for `→ check.id` logs | Keeps stdout parseable |
| `checks[].url` = full URL | Copy URL, Open, cURL in dashboard |
| `detail: "HTTP {code}"` on success/fail | HTTP column + action hints |
| `detail: "TimeoutException after 10s"` | Timeout badge + hints |
| `stats` on every emit | Stat cards + progress bar |
| `current` + `pending` while running | “Not executed” + timeout location |
| 10s per check, 280s global deadline | Scout run limit 300s |
| `allIds` = execution order from MD | Consistent totals across projects |

### Checklist before saving in Scout

- [ ] `emitReport()` + `stdout.flush()` on every progress line
- [ ] No debug prints on stdout
- [ ] Every check: `name`, `status`, `url`, `latencyMs`, `detail`
- [ ] HTTP results use `detail: "HTTP {code}"`
- [ ] `allIds.length` matches `stats.total`
- [ ] Test locally: `dart run health_check.dart` — lines start with `SCOUT_REPORT:`

---

## Quick copy — EPA App example

**Prompt 1** — set:
- `{APP_NAME}` → `EPA App`
- `{SOURCE_HINTS}` → `lib/core/api/end_points.dart`, `lib/features/*/data/*datasource*.dart`, `lib/core/network/dio_provider.dart`, `lib/core/services/remote_config_service.dart`, env in `lib/core/env/`

**Prompt 2** — paste the generated MD from Prompt 1.

After generating, add `stdout.flush()` to `emitReport` if the agent omitted it, then save in Scout.
