# Glossary (Scout Logger)

Domain terms for specs, tickets, and ADRs. Keep entries short.

| Term | Meaning |
|------|---------|
| **Project** | Tenant in Scout; owns ingest key, settings, health-check script |
| **Ingest key** | `sk_live_…` Bearer token for `/v1/events/*` (not the dashboard admin key) |
| **Event** | Single logged payload (error, crash, network, product, …) |
| **Issue** | Grouped fingerprint of similar errors |
| **Session** | Device/user session spanning events |
| **Server health** | Dashboard feature that runs a per-project Dart smoke script |
| **SCOUT_REPORT** | Stdout line prefix `SCOUT_REPORT:{json}` for incremental health reports |
| **Network probe** | Scout-server reachability check (DNS + HTTP) per host in the script |
| **Auth chain** | Independent login path (e.g. citizen `auth.login` vs `eprocess.login`) — do not mix `depends_on` |
| **scout_models** | Shared Dart package: event taxonomy + health-check report types |
| **scout_logger_plus** | Flutter SDK (separate repo) |
| **Share snapshot** | Public read-only link for a health-check (or other) report |
| **WAF learning** | Optional OpenAPI/observations block attached to a health report |
| **WAF rejects** | Dashboard page listing network events that look like edge/WAF HTML blocks (`text/html` instead of JSON); filters + PDF export from project `settings.waf` |
| **Alert** | Outbound notification for a signal that matched project notification policy |
| **Signal** | Something that may become an alert: ingested event, issue regression, spike, health-check failure |
| **Alert preset** | Quiet / Normal / Urgent — named mapping onto notification config (rules, dedup, spikes, health notify) |
| **Emergency** | Highest urgency: new crash/crash regression, health-check fail/timeout, or spike over threshold (prod only) |
| **Alert channel** | Slack, WhatsApp, or email sink; people are targeted by being on that channel (not by Scout roles in Phase 1) |
| **Uptime monitor** | Light automatic URL ping every 10 minutes from Scout (not the full health script); down → emergency alert |

Add terms when `/grill-with-docs` locks a new domain word.
