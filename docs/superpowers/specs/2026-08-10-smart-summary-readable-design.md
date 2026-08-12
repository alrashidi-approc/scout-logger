# Smart summary — humanize + structured UI

## Goal
Make Smart summary scannable in the dashboard and human-readable when copied.

## Changes
1. Humanize Where / Failed at / Why extras / Next / Meta tokens via `product_readable` helpers (routes/`@` kept raw).
2. `SmartIssueSummary.fromEvent` / `fromIssue` return `SmartSummary` `{ where, failedAt, why, next, meta, markdown }`.
3. `SmartSummaryCard` shows labeled rows + Next bullets; Copy still uses `markdown`.

## Out of scope
New heuristics, LLM, broader signal expansion.
