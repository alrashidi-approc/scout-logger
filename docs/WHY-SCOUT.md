# Scout Logger — why teams choose us

**One platform for mobile crashes, errors, sessions, and product analytics — self-hosted, Flutter-first, and controlled from your dashboard.**

---

## The short pitch

Sentry tells you *what broke*. Firebase tells you *what users did*. Scout does **both** — in one place, on **your infrastructure**, with a mobile SDK you can **reconfigure live** without shipping a new app build.

---

## Scout vs Sentry vs Firebase

| | **Scout** | **Sentry** | **Firebase (Crashlytics + Analytics)** |
|---|-----------|------------|----------------------------------------|
| **Self-hosted** | Yes — your VPS + Postgres | SaaS (self-host is complex / limited) | Google cloud only |
| **Flutter-native** | Built for Flutter from day one | General-purpose, Flutter is one of many | Flutter supported, not Flutter-centric |
| **Screen journey** | Push / pop / replace trail with timings | Breadcrumbs (generic) | Screen views (basic) |
| **Errors + analytics** | Issues, funnels, retention, releases in one UI | Strong errors; analytics is separate products | Analytics strong; crashes are separate |
| **Control SDK from dashboard** | Yes — remote config on every app open | Mostly code / project settings in Sentry UI | Remote Config exists, not tied to observability |
| **Guest → logged-in users** | Merges pre-login activity by install ID | User context, less guest merge story | User ID based |
| **Share a single event/issue** | Expiring public link, no account needed | Project access required | No equivalent |
| **Data ownership** | Your database, your rules | Their servers | Google’s servers |
| **Pricing model** | You pay for your server | Per-event SaaS pricing | Free tier + Google lock-in |

**Bottom line:** Sentry is excellent at deep error debugging for large orgs. Firebase is excellent if you already live in Google’s ecosystem. **Scout is for teams that want mobile observability + product insight on their own terms — especially Flutter teams.**

---

## What Scout captures (mobile SDK)

The Flutter SDK (`scout_logger_plus`) sends rich, structured events in batches:

- **Crashes & errors** — stack traces, categories (network, logic, UI, system, crashing)
- **Network** — method, URL, status, duration, slow requests, optional bodies (with redaction)
- **Sessions** — visit length, screens visited, errors and network counts
- **Navigation** — current screen, full screen trail with **push / pop / replace** steps and dwell time
- **Device context** — platform, OS, app version, battery, connectivity, locale, timezone
- **Users** — logged-in ID + email, or anonymous guest until login
- **Custom context** — your own key/value product fields

**Offline-first:** events queue on device and flush when back online.

**One-line setup:** DSN init + optional Dio interceptor — no heavy native wiring.

---

## Control the mobile SDK from the dashboard

This is a major differentiator. Change behavior **without an app store release**:

| Setting | What it does |
|---------|----------------|
| **Enabled log levels** | Turn error / warning / info / success on or off |
| **Flutter crash hooks** | Enable or disable automatic crash capture |
| **Track navigation** | Toggle screen trail / breadcrumb collection |
| **Network bodies** | Capture request/response bodies or headers only |
| **Slow threshold** | Mark requests slower than X ms |
| **Ignore status codes** | Skip noisy 401/404/etc. |
| **Network log scope** | All traffic, errors only, or slow only |

The app fetches config on **init and resume**. You flip a switch in **Project Settings** → production apps pick it up on next launch.

*Sentry and Firebase require code changes or their own separate remote-config products — Scout ties observability and runtime control together.*

---

## Dashboard — everything in one place

### Fix problems faster
- **Issues** — grouped errors with fingerprinting, open/resolved workflow, event counts
- **Event inspector** — stack trace, network panel, device fields, full JSON, copy bug report
- **Share link** — send one event or issue to backend/QA (1 day / 1 week / 1 month, no login)

### Understand users
- **Users** — logged-in profiles; guest activity merged when they sign up
- **Sessions** — replay screen trails and timelines
- **Geography** — world map + country table with **source transparency** (IP vs locale vs profile)

### Ship with confidence
- **Overview** — crash-free rate, error rate, peak hours, live sessions, period comparison
- **Analytics** — funnels (route steps), retention cohorts, release comparison
- **Releases** — crashes and errors per build
- **Filters** — environment, app version, country, custom date ranges (hourly for single-day views)

### Operate the platform
- **Team roles** — owner, admin, member, viewer, QA, developer, support, PM
- **Project credentials** — ingest keys + DSN for mobile apps
- **Danger zone** — purge data by date range or delete project

---

## Security & privacy

Built for teams who care where data lives:

| Layer | How Scout handles it |
|-------|----------------------|
| **Hosting** | Self-hosted on your VPS — not a multi-tenant SaaS black box |
| **Ingest keys** | Stored as hash + AES-encrypted ciphertext; revocable per project |
| **Dashboard auth** | JWT sessions, bcrypt passwords, optional email verification |
| **Project isolation** | Users only see projects they belong to; role-based write/delete |
| **IP privacy** | Client IPs truncated and hashed — not stored in plain text |
| **Share links** | Random token, hash-only in DB, expires automatically |
| **Client redaction** | SDK strips sensitive keys before events leave the device |
| **Public share scope** | Link exposes **one** event or issue — nothing else in the project |

---

## Why mobile teams love Scout

1. **See the full story** — not just “Exception on line 42”, but *which screens* the user visited, *which API* failed, and *which release* they were on.

2. **Debug with backend in seconds** — share an expiring link; they see the exact payload, no dashboard account.

3. **Tune production without redeploying** — turn down network logging during an incident, ignore 404s, raise slow threshold — from the dashboard.

4. **Own your data** — Postgres on your server. Export, purge, comply — on your schedule.

5. **Flutter-first UX** — navigation types, GoRouter support, session replay that matches how Flutter apps actually move.

6. **One stack, one deploy** — `./deploy` pushes server + dashboard + migrations. No vendor billing surprises.

---

## The stack (simple)

```
Flutter app  →  Scout SDK  →  Your Scout server  →  PostgreSQL
                                    ↓
                            Flutter Web dashboard
```

- **Server:** Dart (Shelf)
- **Database:** PostgreSQL 16 with automatic migrations
- **Dashboard:** Flutter Web (same language as your app)
- **SDK:** `scout_logger_plus` (separate repo, pairs with this platform)

---

## Who Scout is for

- **Flutter / mobile product teams** who outgrew `print()` and scattered crash reports
- **Startups** who want Sentry-level insight without Sentry-level bills
- **Companies with data residency requirements** who cannot send PII to US SaaS by default
- **Teams tired of juggling** Crashlytics + Analytics + a third tool for session replay

---

## Honest limits (we don’t oversell)

- **Not a replacement for Firebase Auth, FCM, or Firestore** — Scout observes your app; it doesn’t run your backend
- **No native symbolication pipeline** like mature Sentry — you get stack traces as the app reports them
- **Flutter-first today** — best experience is Flutter; other platforms are not the focus

---

## Get started

1. Deploy Scout on your server (`./deploy`)
2. Create a project in the dashboard
3. Add the SDK to your Flutter app with the project DSN
4. Ship — watch issues, sessions, and funnels fill in

**Scout Logger:** your mobile app’s nervous system — crashes, context, analytics, and control — under your roof.
