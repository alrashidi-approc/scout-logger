# Two GitHub repositories

This project is split into **two repos**:

| Repo | Contents | GitHub (set yours) |
|------|----------|-------------------|
| **scout-logger** | Server, dashboard, deploy, `packages/scout_models` | See [README.md](../README.md) and [apps/server/README.md](../apps/server/README.md) |
| **scout_logger_plus** | Flutter SDK + example app | `github.com/YOUR_ORG/scout_logger_plus` |

The platform repo **does not track** `packages/scout_logger_plus/` (see root `.gitignore`). The SDK is published from its own repository.

---

## 1. Platform repo (this tree)

From the repo root (without `packages/scout_logger_plus` in git):

```bash
git init
git add .
git commit -m "Initial scout-logger platform"
git remote add origin git@github.com:YOUR_ORG/scout-logger.git
git push -u origin main
```

What gets committed:

- `apps/server` — ingest API + Postgres
- `apps/dashboard` — Flutter Web UI
- `packages/scout_models` — shared event taxonomy (server + SDK)
- `scripts/`, `compose.yaml`, `.env.example`, deploy tooling

---

## 2. SDK repo (`scout_logger_plus`)

Export a clean copy for GitHub:

```bash
# optional: set your platform repo URL (for scout_models git dependency)
export SCOUT_PLATFORM_REPO=https://github.com/YOUR_ORG/scout-logger.git

./scripts/export-sdk-repo.sh ../scout_logger_plus
cd ../scout_logger_plus
git init
git add .
git commit -m "Initial scout_logger_plus SDK"
git remote add origin git@github.com:YOUR_ORG/scout_logger_plus.git
git push -u origin main
```

The SDK depends on `scout_models` from the **platform** repo via git:

```yaml
scout_models:
  git:
    url: https://github.com/YOUR_ORG/scout-logger.git
    path: packages/scout_models
```

---

## 3. Flutter app integration

```yaml
dependencies:
  scout_logger_plus:
    git:
      url: https://github.com/YOUR_ORG/scout_logger_plus.git
  dio: ^5.9.0
  flutter_dotenv: ^5.1.0
```

Docs: [scout_logger_plus README](https://github.com/YOUR_ORG/scout_logger_plus/blob/main/README.md)

---

## Local development (both repos on disk)

Keep both folders side by side:

```
~/work/scout-logger/          # platform — ./dev server
~/work/scout_logger_plus/     # SDK — flutter test / example
```

In `scout_logger_plus/pubspec.yaml` for local work, override:

```yaml
dependency_overrides:
  scout_models:
    path: ../scout-logger/packages/scout_models
```

Or keep the SDK export’s git `scout_models` dep and run `flutter pub get` (needs network).

---

## Keeping `scout_models` in sync

Event types and ingest DTOs live in **platform** `packages/scout_models`. When you change taxonomy:

1. Commit + push **scout-logger**
2. In **scout_logger_plus**, run `flutter pub upgrade scout_models` (or pin `ref:` in pubspec)
