# Sherry Hackathon Roadmap

This roadmap is organized by milestones rather than calendar dates so it can fit a 24-, 36-, or 48-hour hackathon. Use the percentage markers to map milestones to the actual event duration.

## Milestone 0 — Align and scaffold (0–10%)

Goal: all three people can work without touching the same files.

### User 1 — Backend

- Create workspace structure, root scripts, CI, and environment example.
- Define shared schemas, API errors, and seed fixtures.
- Scaffold database and mock API client.

### User 2 — Web and desktop

- Scaffold web app inside its owned path.
- Scaffold the thin Tauri desktop wrapper without duplicating web screens.
- Establish routes, tokens, and fixture-driven screens.
- Build the base shell and empty/loading states.

### User 3 — Mobile

- Scaffold the mobile app inside its owned path.
- Verify it can import shared contracts and call the mock client.
- Prove one screen on the target mobile device.

### Integration checkpoint

- Merge scaffolding in this order: User 1 backend/contracts → User 2 web/desktop → User 3 mobile.
- Freeze root tooling after all three people can start their platform.
- Tag `hackathon-scaffold`.

Exit criteria: CI passes; all apps boot; fixture types compile everywhere.

## Milestone 1 — Vertical slice (10–40%)

Goal: create on one surface and view on another.

### User 1 — Backend

- Implement memory table/model.
- Implement create, list, detail, and idempotency.
- Deploy the first shared API environment.

### User 2 — Web and desktop

- Implement list, create, and detail against fixtures.
- Switch to the real API once the transport is ready.
- Display source, timestamp, and sync/error states.
- Run the same flows inside the desktop wrapper and add quick capture.

### User 3 — Mobile

- Implement mobile list/create.
- Verify mobile against fixtures, then the real API.

### Integration checkpoint

- Run AT-01 cross-surface creation.
- Resolve contract issues through User 1; do not patch around schema differences per client.
- Tag `hackathon-vertical-slice`.

Exit criteria: create on mobile; view on web and desktop.

## Milestone 2 — Find and control (40–65%)

Goal: complete the core product promise.

### User 1 — Backend

- Implement text search, soft delete, reset, and refresh/realtime transport.
- Add API tests for search, duplicate create, and deletion.

### User 2 — Web and desktop

- Implement search, delete confirmation, responsive behavior, and recovery states.
- Add the polished demo dataset and first-run experience.
- Verify search and delete inside the packaged desktop build.

### User 3 — Mobile

- Add search and detail on mobile.
- Add sync indicators and manual retry.
- Add local offline queue if time permits after all P0 flows pass.

### Integration checkpoint

- Run AT-02, AT-03, AT-05, and AT-06.
- Record all defects in one shared board with P0/P1/P2 severity.
- Tag `hackathon-core-complete`.

Exit criteria: the entire golden path works across three surfaces.

## Milestone 3 — Reliability and polish (65–85%)

Goal: make the demo resilient and legible.

### User 1 — Backend

- Add health checks, structured request IDs, seed reset, and deployment notes.
- Review workspace isolation and secret handling.

### User 2 — Web and desktop

- Complete loading, empty, offline, failure, and long-content states.
- Improve keyboard/focus behavior and demo presentation.
- Test the packaged desktop build on the presentation laptop.

### User 3 — Mobile

- Test on the actual demo phone.
- Fix keyboard, safe-area, and restart behavior.
- Validate client recovery after API interruption.

### Integration checkpoint

- Freeze features at 85% of available time.
- Cut an `rc1` tag.
- Run the full demo twice from a clean reset.

Exit criteria: no P0/P1 demo blocker; backup transport and reset paths work.

## Milestone 4 — Demo lock (85–100%)

Goal: protect the presentation.

- Only the integrator merges changes.
- No dependency upgrades, schema redesigns, or visual-system rewrites.
- Fix P0 issues first; accept and document low-impact defects.
- Prepare demo accounts, seed data, devices, chargers, and network fallback.
- Record a backup walkthrough.
- Create `hackathon-demo` tag from the exact demonstrated commit.

Exit criteria: the scripted demo succeeds twice on presentation hardware.

## Stretch lane

Start only after `hackathon-core-complete`:

1. Import a pasted AI conversation as a sourced memory.
2. Generate a short summary with a guarded AI call.
3. Add Share Sheet capture on mobile.
4. Add a desktop global quick-capture shortcut.
5. Add live updates instead of manual refresh.

Each stretch feature must remain behind a feature flag and must not alter the primary data contract during demo lock.

## Shared integration board

Track every cross-user dependency with this shape:

| ID | Owner | Consumer | Interface or file | Needed by | Status |
|---|---|---|---|---|---|
| INT-001 | User 1 | Users 2–3 | `Memory` schema | Milestone 0 | Planned |
| INT-002 | User 1 | Users 2–3 | API base URL and auth mode | Milestone 1 | Planned |
| INT-003 | User 2 | User 3 | Shared visual tokens | Milestone 1 | Planned |
| INT-004 | User 1 | All | Demo reset procedure | Milestone 3 | Planned |

## Merge order at each checkpoint

1. User 1 merges contracts, migrations, and API.
2. User 2 rebases and merges web and desktop changes.
3. User 3 rebases and merges mobile changes.
4. Integrator runs the golden path on `main`.
5. If integration fails, revert the smallest offending PR; do not patch directly on `main` under pressure.

## Go/no-go rules

- If backend deployment is unstable by 40%, switch to Supabase client access or a local demo API and preserve the same contracts.
- If desktop packaging is unstable by 65%, demo the desktop app in development mode.
- If physical mobile builds are unstable by 65%, use Expo Go on the known working device.
- If realtime is unstable, use manual refresh with honest UI.
- If AI summarization is unreliable or slow, disable the feature flag; the core demo does not depend on it.
