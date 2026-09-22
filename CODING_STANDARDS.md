# Coding standards (Scout Logger)

Used by `/code-review` (Standards axis). Prefer judgement over checklist theater.

## Source of truth

1. Global rules: human-like simplicity (short, idiomatic, no AI wrappers).
2. Project rules in `.cursor/rules/`.
3. Existing code in the area you touch — match local style.

## Must

- Shared event/health JSON shapes live in `packages/scout_models`.
- Do not invent layers (services wrapping services) without clear duplication.
- Health scripts: `SCOUT_REPORT` + flush; no stdout noise; separate auth chains.
- Secrets stay out of git (`.env` local only).

## Prefer

- Small PRs / vertical tickets (see `docs/agents/HOW-WE-WORK.md`).
- Focused tests beside the change; full suite once at the end of `/implement`.

## Smell baseline

`/code-review` also applies the Fowler smell heuristics from the skill (mysterious names, duplication, feature envy, …). Repo docs above win when they conflict.
