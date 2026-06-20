# scout-logger server

Dart Shelf API for event ingest and dashboard reads. See the [platform README](../README.md).

## Run

From repo root (uses root `.env`):

```bash
./dev server
```

## Layout

| Path | Purpose |
|------|---------|
| `bin/server.dart` | Entry point |
| `lib/routes/ingest_routes.dart` | `POST /v1/events/batch` |
| `lib/routes/api_routes.dart` | Dashboard `/api/*` |
| `lib/store/scout_store.dart` | Ingest, issues, events |
| `lib/store/analytics_store.dart` | Funnels, retention, sessions |
| `lib/db/migrations/` | Postgres schema |

Uses `packages/scout_models` — same contract as [scout_logger_plus](https://github.com/YOUR_ORG/scout_logger_plus).

Migrations run automatically on startup.
