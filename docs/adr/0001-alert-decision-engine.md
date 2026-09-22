# 0001. Alert decision engine (Phase 1)

## Status
Accepted

## Context
Scout already ingests events and can notify via Slack / WhatsApp / email with category rules, dedup, spikes, and digests. The next product step is deciding *when* something is worth alerting (including emergencies) without making the dashboard feel complex. Channel membership (who is on Slack/WhatsApp/email) is how people are targeted — not in-app role routing.

## Decision
1. **Emergency** = new crash / crash regression, **or** health-check failed/timeout, **or** error/crash spike above the project threshold (existing spike monitor).
2. **Routing audience** = project notification channels only (v1). No role/assignee targeting; ops put the right people on those channels.
3. **Environments** = keep hard rule: automatic alerts only for production / prod / release.
4. **UI** = restructure Project Notifications into **Simple** (presets + channels) and **Advanced** (existing knobs). Prefer progressive disclosure over new surfaces.
5. **Presets** (Quiet / Normal / Urgent) map to existing config fields (`rules`, `dedupMinutes`, `groupMinutes`, `threshold`, health-check notify). Users pick a mode; Advanced still editable.
6. Wire existing signals (`alertWorthy`, issue severity heuristics) into routing quietly where they reduce noise without new UI.
7. Defer: custom filter rules, generic webhooks, ack/snooze UI, PagerDuty, per-role routing, AI auto-page.

## Consequences
- Easier: one coherent “how loud” story; health outages finally page; settings feel calmer.
- Harder: presets must stay in sync with Advanced edits (last-write or “custom” when user leaves preset).
- Follow-ups: Phase 2 filter-based rules / webhooks only after Quiet/Normal/Urgent feels good in production.
