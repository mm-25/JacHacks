# Sherry Hackathon Build Plan

Status: ready to execute  
Team: 3 developers / AI agents  
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

Use a monorepo so contracts and UI primitives stay shared, but give each agent exclusive ownership of a small set of top-level paths.

```text
apps/
  web/                 # Agent 2
  desktop/             # Agent 3
  mobile/              # Agent 3
packages/
  contracts/           # Agent 1; other agents consume only
  api-client/          # Agent 1
  ui/                  # Agent 2
  config/              # Agent 1
services/
  api/                  # Agent 1
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

## 5. Agent ownership

### Agent 1 — Platform and data

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

Must not edit `apps/web`, `apps/desktop`, or `apps/mobile` except through a separately reviewed integration PR.

### Agent 2 — Web and shared visual system

Owns:

- `apps/web/**`
- `packages/ui/**`

Delivers:

- Responsive memory list, search, create, detail, and delete flows.
- Shared visual tokens and reusable web components.
- Demo seed-state presentation.
- Browser-level happy-path tests.

Must consume the API through `packages/api-client`; must not create direct database queries.

### Agent 3 — Desktop and mobile

Owns:

- `apps/desktop/**`
- `apps/mobile/**`

Delivers:

- Desktop packaging and quick capture.
- Mobile memory list, create, search, and sync status.
- Platform build/run documentation.

Must consume `packages/contracts` and `packages/api-client` without changing them directly. Contract changes are requested through an issue or a small PR assigned to Agent 1.

## 6. Git protocol for zero-surprise collaboration

### Branches

- Protected integration branch: `main`.
- One long-lived branch per agent: `agent/platform`, `agent/web`, `agent/clients`.
- Short task branches from the agent branch when helpful: `agent/web/memory-list`.
- Never let two agents implement the same file or migration.

### Pull requests

- Keep PRs small and single-purpose.
- Rebase on current `main` before requesting merge.
- Squash merge to keep rollback simple.
- Every PR states: owned paths changed, contract impact, migration impact, and verification performed.
- Only the designated integrator merges to `main` during integration windows.

### Shared-file rules

- Root config, lockfile, shared contracts, and migrations have one owner: Agent 1.
- Agent 1 lands dependency/config changes early; other agents rebase afterward.
- No drive-by formatting or repository-wide refactors during the hackathon.
- Additive contract changes are preferred. Breaking changes require all three agents to acknowledge the change before merge.
- Database migrations are immutable after merge. Fixes use a new migration.

### Integration rhythm

- Start of block: pull/rebase and post the files each agent expects to touch.
- Every 2–3 hours: merge one tested vertical increment per active agent.
- Before sleep or handoff: push all useful work, update the PR description, and record blockers.
- Final 4 hours: feature freeze; only integration, demo reliability, and critical bug fixes.

## 7. Interface-first sequence

1. Agent 1 defines `Memory`, `MemorySource`, request/response schemas, and error shapes.
2. All agents approve fixtures before implementation diverges.
3. Agent 1 publishes a mocked API client immediately.
4. Agents 2 and 3 build against fixtures while Agent 1 implements the real backend.
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

