# How we work (Scout Logger)

Use these Cursor skills in order for non-trivial features. Global rules still apply: confirm before structural changes; keep code short and idiomatic.

## Flow

```
idea → /grill-me (or /grill-with-docs)
     → /to-spec
     → /to-tickets
     → /implement  (one ticket at a time)
     → /code-review
```

| Step | Skill | Output |
|------|--------|--------|
| Pressure-test design | `/grill-me` | Decisions + open risks (no code) |
| Same + write docs | `/grill-with-docs` | + ADRs in `docs/adr/`, terms in `docs/agents/glossary.md` |
| Capture the plan | `/to-spec` | Spec under `.scratch/<feature>/` or linked issue |
| Slice work | `/to-tickets` | Vertical tickets with blockers (see [issue-tracker.md](./issue-tracker.md)) |
| Build | `/implement` | Code + tests; commit on current branch |
| Review | `/code-review` | Standards + Spec axes since a fixed point |

Small bugs / one-file fixes: skip grilling — just fix and keep diffs tight.

## Tracker

Default publisher: **local files** under `.scratch/` (gitignored). Details: [issue-tracker.md](./issue-tracker.md).

## Flutter / layout

- Widget tests → `/flutter-add-widget-test`
- Integration tests → `/flutter-add-integration-test`
- Responsive layout → `/flutter-build-responsive-layout`
- Overflows → `/flutter-fix-layout-issues`
