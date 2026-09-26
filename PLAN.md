# Sherry Hackathon Build Plan

Status: ready to execute  
Team: 3 human builders, each optionally assisted by their own AI tool  
Target: one hackathon demo build across web, desktop, and mobile

## 1. Outcome

Build a convincing vertical slice of Sherry: a user captures or manually adds information on one surface, sees it in a shared memory library, and retrieves it from another surface with source attribution.

The hackathon goal is not production completeness. The goal is one reliable, understandable cross-platform story.

## 2. Demo story

1. The user opens Sherry on web and signs into a demo workspace.
2. The user adds a memory or imports a short conversation.
3. The memory appears in a shared timeline with its source and timestamp.
4. The user opens the desktop app and finds the same memory.
5. The user opens the mobile app, adds a new note, and synchronizes it.
6. Web search returns both items and shows where each came from.
7. The user deletes one item and the deletion is reflected on all surfaces.

This is the golden path. Every implementation decision should protect it.

## 3. Scope strategy

### Must build

- One shared backend and data contract.
- Web app with memory list, add, search, detail, and delete.
- Desktop shell that reuses the web UI and adds a simple quick-capture action.
- Mobile app with list, add, search, and sync status.
- Source attribution on every memory.
- Seed/demo mode so the presentation does not depend on external providers.
- Basic loading, empty, offline, and error states.

### Build only if the golden path is stable

- Browser conversation capture.
- AI-generated summaries.
- Provider OAuth or live MCP integration.
- Semantic/vector search.
- Attachments.

### Explicitly out of scope

- Automatic capture from every AI provider.
- Background capture from arbitrary desktop/mobile apps.
- Conflict detection and fact reconciliation.
- Team workspaces, billing, complex permissions, and app-store release.
- Production-grade compliance, retention controls, or account recovery.

## 4. Recommended implementation shape

Use a monorepo so contracts stay shared, but give each person exclusive ownership of a platform area. AI tools work inside the lane of the person operating them; they do not own branches, approve contracts, or merge code.

```text
apps/
  web/                 # User 2
  desktop/             # User 2 — thin wrapper around web
  mobile/              # User 3
packages/
  contracts/           # User 1; other users consume only
  api-client/          # User 1
  ui-web/              # User 2
  config/              # User 1
services/
  api/                  # User 1
docs/                   # Product lead / designated integrator
```

Suggested stack:

- Monorepo: pnpm workspaces + Turborepo.
- Web: React + Vite + TypeScript.
- Desktop: Tauri wrapping the shared web application.
- Mobile: Expo React Native.
- Backend: Supabase for auth/database/realtime, or a small Node API with SQLite/Postgres if the team already has deployment infrastructure.
- Validation: Zod schemas exported from `packages/contracts`.
- Styling: shared design tokens; reuse behavior and tokens rather than forcing identical DOM/native components.

Cost-minimizing fallback: use Supabase free tier, deploy web to Vercel/Cloudflare Pages, keep desktop local, and distribute the Expo build through Expo Go.

## 5. Human ownership

There are four technical surfaces and three people. Web and desktop are intentionally paired because the desktop app is a thin Tauri shell around the web product. This keeps each person in a distinct lane without asking two people to edit the same UI.

Replace `User 1`, `User 2`, and `User 3` with actual names before the project begins.

### User 1 — Backend and shared contracts

Owns:

- `services/api/**`
- `packages/contracts/**`
- `packages/api-client/**`
- database migrations and seed data

Delivers:

- Memory CRUD and text search.
- A stable typed contract.
- Demo authentication or a fixed demo identity.
- Realtime or refresh-based synchronization.
- API tests and deployment instructions.

Must not edit `apps/web`, `apps/desktop`, or `apps/mobile` except through a separately reviewed integration PR requested by that platform's owner.

### User 2 — Web and desktop

Owns:

- `apps/web/**`
- `apps/desktop/**`
- `packages/ui-web/**`

Delivers:

- Responsive memory list, search, create, detail, and delete flows.
- Shared visual tokens and reusable web components.
- Tauri desktop wrapper around the web application.
- Desktop quick capture and packaging for the demo machine.
- Demo seed-state presentation.
- Browser-level happy-path tests.

Must consume the API through `packages/api-client`; must not create direct database queries.

### User 3 — Mobile

Owns:

- `apps/mobile/**`

Delivers:

- Mobile memory list, create, search, and sync status.
- Mobile build/run documentation and demo-device preparation.

Must consume `packages/contracts` and `packages/api-client` without changing them directly. Contract changes are requested from User 1 through an issue or documented handoff.

### Human control rule

- Each person is accountable for code produced with their AI tool.
- An AI tool may propose changes only within its user's owned paths.
- No AI tool merges a PR, changes a shared contract, edits another person's lane, or resolves a merge conflict without that human explicitly reviewing the action.
- Cross-platform decisions are made by the three people, then recorded in the contract or integration board.

## 6. Git protocol for zero-surprise collaboration

### Branches

- Protected integration branch: `main`.
- One long-lived branch per person/platform: `backend`, `web-desktop`, `mobile`.
- Short task branches when helpful: `web-desktop/memory-list`.
- Never let two people or their AI tools implement the same file or migration.

### Pull requests

- Keep PRs small and single-purpose.
- Rebase on current `main` before requesting merge.
- Squash merge to keep rollback simple.
- Every PR states: owned paths changed, contract impact, migration impact, and verification performed.
- Only the designated integrator merges to `main` during integration windows.

### Shared-file rules

- Root config, lockfile, shared contracts, and migrations have one owner: User 1.
- User 1 lands dependency/config changes early; Users 2 and 3 rebase afterward.
- No drive-by formatting or repository-wide refactors during the hackathon.
- Additive contract changes are preferred. Breaking changes require all three people to acknowledge the change before merge.
- Database migrations are immutable after merge. Fixes use a new migration.

### Integration rhythm

- Start of block: pull/rebase and post the files each person expects to touch.
- Every 2–3 hours: merge one tested vertical increment per active platform.
- Before sleep or handoff: push all useful work, update the PR description, and record blockers.
- Final 4 hours: feature freeze; only integration, demo reliability, and critical bug fixes.

## 7. Interface-first sequence

1. User 1 drafts `Memory`, `MemorySource`, request/response schemas, and error shapes.
2. All three people approve the fixtures before implementation diverges.
3. User 1 publishes a mocked API client immediately.
4. Users 2 and 3 build against fixtures while User 1 implements the real backend.
5. Replace mock transport with the real API without changing screen code.

Required seed fixture:

```json
{
  "id": "mem_demo_001",
  "content": "Use concise weekly project updates.",
  "source": {
    "type": "manual_note",
    "platform": "web",
    "label": "Quick capture"
  },
  "createdAt": "2026-09-26T18:00:00Z",
  "updatedAt": "2026-09-26T18:00:00Z"
}
```

## 8. Definition of done

- The complete demo works twice in a row from a clean seed state.
- A memory created on one surface becomes visible on another.
- Search returns the expected memory.
- Every result displays source and timestamp.
- Delete is confirmed and synchronized.
- The demo survives a slow or unavailable network with an understandable state.
- Web, desktop, mobile, and API each have a one-command local start path.
- No open P0 or P1 issue remains.

## 9. Demo safety

- Provide a `demo:reset` script or equivalent reset action.
- Keep a prerecorded 60–90 second backup walkthrough.
- Avoid live provider OAuth, paid AI calls, or app-store dependencies in the primary demo.
- Freeze versions and lockfiles before final integration.
- Prepare one laptop with all three clients already authenticated and seeded.
