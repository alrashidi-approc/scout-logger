# Smart issue / event summaries

Short **agent brief** on issue/event detail (client-side, no LLM).

## Output shape

```md
## Smart summary

**Where:** `/splash` · `device_bootstrap_launch-auth-retry`
**Failed at:** device_guard · `registration_failed`
**Why:** … (diagnosis prose if present, else heuristic)
**Next:** … · …
**Meta:** app@version · platform · env/release · events=N
```

## Priority of signals

1. `payload.diagnosis` (summary, likelyCause, stage, nextSteps)
2. `payload.context.failure_layer` / structured keys
3. Breadcrumb + message heuristics

## Host-app context keys

```json
{
  "entrypoint": "launch-auth-retry",
  "step": "2_device_guard",
  "failure_layer": "device_guard",
  "platform_code": "registration_failed",
  "app_check_provider": "play_integrity",
  "kDebugMode": "false",
  "attempt": "retry",
  "outcome": "failed_final",
  "identity_state": "fresh",
  "has_hw_key": "false",
  "operation": "device_bootstrap_launch-auth-retry"
}
```

See also [SCOUT-DIAGNOSIS.md](./SCOUT-DIAGNOSIS.md).

Tests: `apps/dashboard/test/smart_issue_summary_test.dart`.
