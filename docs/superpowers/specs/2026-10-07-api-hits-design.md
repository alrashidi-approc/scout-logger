# API hits analytics — design

**Date:** 2026-10-07
**Status:** Approved (design), pending spec review

## Goal

Show how many times the app hits each API over 1 / 7 / 30 days, with charts, on a dedicated
dashboard page that can be enabled or disabled per project in settings (same pattern as WAF rejects).

Example: `GET https://falcon.epa.gov.kw/epa_bridge/api/ssn-details?serial=…&ssn=…` counts as
`GET falcon.epa.gov.kw/epa_bridge/api/ssn-details`. Query parameters and bodies are ignored.

## Non-goals

- History beyond 30 days (raw routine events are purged at `routineDays`, default 30).
- Per-endpoint rollup table, latency analytics, alerts/rate-limit thresholds.
- Query/body inspection.

## Data source

Existing `events` rows with `type = 'network'`; URL at `payload->'network'->>'url'`, method at
`payload->'network'->>'method'`. Success/error via existing `sqlIsSuccessEvent()` / `sqlIsErrorEvent()`.
No migration.

## Endpoint key

`METHOD host/path`, built from the URL:

1. Drop everything from `?` or `#` onward.
2. Drop scheme; keep host (with port if present).
3. Collapse path segments that are all digits, or UUIDs, into `:id`.
4. Trim trailing `/` (except root). Method upper-cased; missing method → `REQUEST`.

Implemented once in `scout_models` (`apiEndpointKey(method, url)`) for the dashboard input box, and
mirrored in SQL (`regexp_replace`) for server-side grouping. Both are covered by tests with the same cases.

## Settings

- `scout_models`: `ApiHitsConfig { bool? visible }`, `defaultVisible = false`, `fromJson` / `toJson` / `resolved()`.
- Server: project settings merge accepts an `apiHits` patch alongside `waf` (`scout_store.dart` settings update).
- Dashboard: toggle in `project_settings_screen.dart`; `shell.dart` shows the "API hits" nav item when
  `apiHits.visible` resolves true (mirrors `_wafVisible` load + refresh).

## Server API

`GET /projects/:id/api-hits?days=1|7|30&endpoint=<optional key or URL>`

- `days` clamped to {1, 7, 30}; default 7.
- `endpoint` normalized server-side with the same key rules; when present, filters everything.

Response:

```json
{
  "days": 7,
  "bucket": "day",
  "endpoint": "GET falcon.epa.gov.kw/epa_bridge/api/ssn-details",
  "totals": { "hits": 1234, "success": 1200, "error": 34 },
  "endpoints": [
    { "key": "GET falcon.epa.gov.kw/epa_bridge/api/ssn-details", "method": "GET",
      "host": "falcon.epa.gov.kw", "path": "/epa_bridge/api/ssn-details",
      "hits": 1234, "success": 1200, "error": 34 }
  ],
  "series": [ { "t": "2026-10-01T00:00:00Z", "hits": 180, "error": 4 } ]
}
```

- `bucket`: `hour` when `days = 1`, else `day` (UTC). Empty buckets filled with zeros.
- `endpoints`: ranked by hits, top 100.
- SQL lives in `analytics_store.dart`; route handler stays thin and uses existing project auth.

## Dashboard screen

Route `/p/:projectId/api-hits` → `api_hits_screen.dart`, following existing screen patterns
(`PageHeader`, `AppTheme`, `pageInsets`).

- Period selector: 1d / 7d / 30d.
- API input: paste URL or path; query stripped; filters the page. Clear button resets.
- Summary cards: total hits, avg per day (or per hour for 1d), peak bucket, error rate.
- Charts (`fl_chart`): line chart of hits over time; horizontal bar chart of top 10 endpoints split
  success / error (hidden when an endpoint is selected).
- Ranked endpoint table; tapping a row sets the API input.
- Empty state when no network events in range. If the page is disabled, route is hidden from nav.

## Error handling

- Invalid `days` → clamped; unparseable `endpoint` → treated as a path-only key.
- API failure → existing dashboard error state with retry.

## Testing

- `scout_models`: `apiEndpointKey` cases (query stripped, method kept, numeric/UUID → `:id`, trailing slash,
  missing method); `ApiHitsConfig` JSON round-trip and default.
- Server: store test for grouping, filter, totals, and hour/day bucket zero-fill.
- Dashboard: widget test for screen render with stubbed data and endpoint filter.
