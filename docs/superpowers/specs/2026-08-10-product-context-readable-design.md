# Product context readable panel

## Goal
Make event **Product context** scannable: human sentences + chips, with raw key/value under Technical details.

## UX
Same layout as Network:
1. Readable panel (title, chips, “What this means” lines) when fields exist
2. Technical details → existing `FieldGrid`
3. Empty: `No extra context`

## Humanization
- Keys: split `_` / camelCase; alias map (`sec`→Security, `hw`→Hardware, `vpn`→VPN, `auth`→Auth, …)
- Bools: `{Label} is enabled` / `{Label} is disabled`
- Other scalars: `{Label}: {prettified value}`
- Maps/lists: technical details only

## Data
Sources unchanged: unknown payload keys + `custom` + `context`.

Pure helper `productReadableFrom(Map)` → `{ title, chips, lines }`.

## Out of scope
SDK payload changes, LLM summaries.
