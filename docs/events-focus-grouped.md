# Events Focus + Grouped views

Dashboard Events screen supports three modes (API rollups, no new tables):

| View | Query | Behavior |
|------|--------|----------|
| **Focus** (default UI) | `?view=focus` | Hides routine lifecycle noise (`session_start` / `session_end` / app background-foreground logs). Heartbeats already hidden. |
| **All** | `?view=all` | Flat chronological feed (previous default). |
| **Grouped** | `?view=grouped` | Buckets by type+action/message (or issue / network route). Tap → members via `?view=all&group=<key>`. |

## Group key examples

- `log|session_start`
- `network|GET|/api/users`
- `issue|<issueId>` → opens Issue detail

## Server helpers

`apps/server/lib/util/event_filters.dart`

- `sqlFocusWorthyEvent` / `isRoutineEvent`
- `sqlEventGroupKey` / `eventGroupKey`
