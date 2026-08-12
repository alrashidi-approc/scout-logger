# Product Context Readable Implementation Plan

> **For agentic workers:** Implement task-by-task. Steps use checkbox syntax.

**Goal:** Readable Product context panel with humanized keys/values, mirroring Network.

**Architecture:** Pure `productReadableFrom` in dashboard utils; `ProductReadablePanel` widget; wire in event detail above `FieldGrid`.

**Tech Stack:** Flutter dashboard, Dart unit tests

## Global Constraints
- Booleans → “is enabled” / “is disabled”
- Keep raw FieldGrid under Technical details
- No SDK payload changes

---

### Task 1: `productReadableFrom` + tests
- [x] Add `apps/dashboard/lib/utils/product_readable.dart`
- [x] Add `apps/dashboard/test/product_readable_test.dart`
- [x] Cover aliases, bools, title/chips, empty

### Task 2: UI + wire-up
- [x] Add `ProductReadablePanel` in `event_detail_widgets.dart`
- [x] Expose `productReadable` on `EventView`
- [x] Update Product context section in `event_detail_screen.dart`
- [x] Run tests
