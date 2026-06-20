# scout-logger (platform)

Dart server + PostgreSQL + Flutter Web dashboard for mobile observability.

**Flutter SDK:** separate repo — [`scout_logger_plus`](https://github.com/YOUR_ORG/scout_logger_plus) (not in this git tree). See [docs/REPOS.md](docs/REPOS.md).

**One config file:** copy `.env.example` → `.env` at the repo root. No `--dart-define`.

## Stack

- **Server:** Dart Shelf (`apps/server`) — reads root `.env` on startup
- **Dashboard:** Flutter Web — loads API settings from `GET /api/dashboard/config`
- **Shared models:** `packages/scout_models` — ingest event taxonomy (server + SDK)
- **DB:** PostgreSQL 16
- **Mobile SDK:** [`scout_logger_plus`](https://github.com/YOUR_ORG/scout_logger_plus) — separate GitHub repo

## Local dev (no upload)

Use a **local** `.env` (different from server if you want):

```env
PORT=8080
PUBLIC_URL=http://localhost:8080
DATABASE_URL=postgres://scout:YOUR_PASSWORD@localhost:5433/scout
DASHBOARD_API_KEY=dev-key
POSTGRES_USER=scout
POSTGRES_PASSWORD=YOUR_PASSWORD
POSTGRES_DB=scout
DB_PORT=5433
```

### Fast loop (recommended)

**Terminal 1 — DB + API:**

```bash
./dev server
```

**One-time — build dashboard static files for the server:**

```bash
cd apps/dashboard && flutter build web
```

Open **http://localhost:8080/scout/dashboard/**

**Terminal 2 — hot reload UI (optional):**

```bash
./dev dashboard
```

**Test ingest without the mobile app:**

```bash
./dev test
# paste sk_live_... from dashboard after creating a project
```

### Full stack like production (Docker)

```bash
./dev docker
```

Same as Hetzner: Postgres + server in containers. Dashboard at `http://localhost:8080/scout/dashboard/` after `flutter build web`.

### What to run before `./deploy`

Only when local looks good:

```bash
./dev server          # verify API + dashboard
./dev test            # verify ingest → Issues appear
./deploy              # ship to Hetzner
```

Skip dashboard rebuild on deploy if unchanged: `SKIP_DASHBOARD_BUILD=1 ./deploy`

---

## Environment (`.env`)

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | Postgres connection for the server |
| `DASHBOARD_API_KEY` | Protects `/api/*` (dashboard uses this via `/api/dashboard/config`) |
| `PUBLIC_URL` | DSN host + dashboard bootstrap for `flutter run` |
| `PORT` / `HOST` | HTTP bind |
| `POSTGRES_*` / `DB_PORT` | Docker Compose database service |

## API

| Auth | Endpoint | Purpose |
|------|----------|---------|
| Bearer ingest key | `POST /v1/events/batch` | Client ingest |
| `X-API-Key` | `GET/POST /api/projects` | Admin |
| none | `GET /api/dashboard/config` | Dashboard bootstrap |
| `X-API-Key` | `GET /api/projects/:id/*` | Dashboard reads |

## DSN

After creating a project in the dashboard:

`https://<ingest_key>@<host>:<port>/<project_id>`

### Flutter app (`scout_logger_plus`)

Published from a **separate repository**. Add to your app:

```yaml
dependencies:
  scout_logger_plus:
    git:
      url: https://github.com/YOUR_ORG/scout_logger_plus.git
  dio: ^5.9.0
  flutter_dotenv: ^5.1.0
```

Quick start:

```dart
import 'package:scout_logger_plus/scout_logger_plus.dart';

await Scout.init(dotenv.env['SCOUT_DSN']!);
apiDio.attachScout();
runApp(ScoutApp(builder: (observers) => MaterialApp(
  navigatorObservers: observers,
  home: HomeScreen(),
)));
```

Full integration guide: [scout_logger_plus README](https://github.com/YOUR_ORG/scout_logger_plus/blob/main/README.md)

**Export SDK repo from this tree** (if you still have `packages/scout_logger_plus` locally):

```bash
./scripts/export-sdk-repo.sh ../scout_logger_plus
```

See [docs/REPOS.md](docs/REPOS.md) for two-repo setup.

---

## Deploy to Hetzner (one command)

Add to `.env`:

```env
HETZNER_HOST=root@46.62.217.25
HETZNER_DIR=/opt/scout-logger
PUBLIC_URL=https://logs.yourdomain.com
```

First time on the server (once): SSH in and ensure Podman works:

```bash
ssh root@YOUR_IP
apt update && apt install -y podman podman-compose
systemctl enable --now podman.socket
```

From your Mac (SSH key recommended — run once: `ssh-copy-id root@YOUR_IP`):

```bash
./deploy
```

If manual SSH works but deploy fails, your key may not be on the server yet. The old script used `BatchMode=yes` (no password prompts). Fix:

```bash
ssh-copy-id root@46.62.217.25
./deploy
```

Or set `HETZNER_SSH_KEY=~/.ssh/your_key` in `.env` if you use a different private key.

This will:

1. Build Flutter dashboard
2. `rsync` the project to `HETZNER_DIR`
3. Upload `.env`
4. Run `podman compose up -d --build` on the server
5. Smoke-test `/health` and `/scout/dashboard/`

**Skip dashboard rebuild:** `SKIP_DASHBOARD_BUILD=1 ./deploy`

**Server logs:**

```bash
ssh root@YOUR_IP 'cd /opt/scout-logger && bash scripts/compose.sh logs -f server'
```

**Firewall:** open TCP `22` (SSH) and `${PORT}` (default **8081** while old logplatform uses 8080), or use Cloudflare Tunnel.

**Port 8080 busy?** Old logplatform still runs there. Use `PORT=8081` in `.env` until cutover, then stop `/opt/logplatform` and switch to `8080`.
