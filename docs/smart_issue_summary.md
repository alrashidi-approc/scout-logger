# Smart issue / event summaries

Dashboard generates a copy-pasteable **Smart summary** on issue and event detail pages (client-side, no API).

## UI

- **Event inspector** — card under Quick facts; **Copy ticket** still dumps raw JSON.
- **Issue detail** — card under stats; uses the newest member event + issue aggregates.

## Host-app context keys (preferred)

When present on `payload.context`, these beat breadcrumb regex:

```json
{
  "entrypoint": "launch-auth-retry",
  "step": "2_device_guard",
  "failure_layer": "device_guard",
  "platform_code": "registration_failed",
  "platform_message": "null",
  "app_check_provider": "play_integrity",
  "flavor": "dev",
  "kDebugMode": "false",
  "attempt": "retry",
  "outcome": "failed_final",
  "identity_state": "fresh",
  "has_hw_key": "false",
  "operation": "device_bootstrap_launch-auth-retry"
}
```

Also set `payload.context.operation` (or keep it where the SDK already puts it).

## Generator

`SmartIssueSummary.fromEvent(EventView)` / `fromIssue(issue, events)` → markdown.

Tests: `apps/dashboard/test/smart_issue_summary_test.dart`.
