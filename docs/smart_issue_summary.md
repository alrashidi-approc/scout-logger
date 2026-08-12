# Smart issue / event summaries

Short **agent brief** on issue/event detail (client-side, no LLM).

## UI

Structured card: **Where** / **Failed at** / **Why** / **Next** (bullets) / **Meta** (chips).  
**Copy** still pastes markdown for agents.

Tokens are humanized (`device_guard` → Device Guard) via `product_readable` helpers.

## Output shape (markdown copy)

```md
## Smart summary

**Where:** `/splash` · Device Bootstrap Launch Auth Retry
**Failed at:** Device Guard · Registration Failed
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
