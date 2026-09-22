# Issue tracker (Scout Logger)

Used by `/to-spec`, `/to-tickets`, and `/code-review`.

## Publisher

**Local files** (default).

| Kind | Path |
|------|------|
| Spec | `.scratch/<feature-slug>/spec.md` |
| Tickets | `.scratch/<feature-slug>/issues/<NN>-<slug>.md` |
| Scratch notes | `.scratch/<feature-slug>/notes.md` |

`.scratch/` is gitignored. Commit specs you want to keep by copying into `docs/superpowers/specs/` (or open a GitHub issue).

### Optional: GitHub Issues

If the user says “publish to GitHub”:

1. Create issues with `gh issue create` on this repo.
2. Put blocking references in each issue body (`Blocked by: #N`).
3. Label agent-ready work: `ready-for-agent`.
4. Spec can live as the parent issue body or a linked `docs/…` file.

## Status vocabulary

| Status | Meaning |
|--------|---------|
| `ready-for-agent` | Approved; agent may implement |
| `blocked` | Waiting on another ticket |
| `in-progress` | Someone is implementing |
| `done` | Acceptance criteria met |
| `cancelled` | Won’t do |

## Fetching a task for `/code-review`

1. Prefer issue refs in commits (`#123`) → `gh issue view 123`.
2. Else path under `.scratch/<feature>/spec.md` or `issues/*.md`.
3. Else ask the user for the spec path or issue URL.
