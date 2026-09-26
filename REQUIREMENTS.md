# Sherry Hackathon Requirements

Version: 1.0  
Priority vocabulary: P0 = demo-critical, P1 = important, P2 = stretch

## 1. Functional requirements

### Identity and workspace

- **FR-001 · P0:** The system shall provide a demo user and one private workspace.
- **FR-002 · P1:** The system should support email-based authentication if it can be completed without risking the golden path.
- **FR-003 · P0:** All clients shall operate on the same workspace dataset.

### Memory creation

- **FR-010 · P0:** A user shall create a text memory from web, desktop, and mobile.
- **FR-011 · P0:** The create request shall include content, source platform, source type, and client-generated idempotency key.
- **FR-012 · P1:** A user should add zero or more tags.
- **FR-013 · P0:** The client shall display `Saving`, `Synced`, `Offline`, or `Failed` status.
- **FR-014 · P1:** An offline mobile or desktop creation should queue locally and retry when connectivity returns.

### Library and detail

- **FR-020 · P0:** Every client shall show memories in reverse chronological order.
- **FR-021 · P0:** Each list item shall show a content preview, source platform/type, and timestamp.
- **FR-022 · P0:** A user shall open a detail view containing the full memory and provenance.
- **FR-023 · P1:** Pagination or cursor loading should prevent the client from assuming an unbounded list.

### Search

- **FR-030 · P0:** A user shall search memory content with case-insensitive text matching.
- **FR-031 · P0:** Search results shall use the same provenance display as the library.
- **FR-032 · P1:** Search should match tags and source labels.
- **FR-033 · P2:** Search may use semantic ranking after deterministic search passes acceptance tests.

### Synchronization

- **FR-040 · P0:** A memory created on one surface shall become visible on the others after refresh or realtime synchronization.
- **FR-041 · P0:** Duplicate requests with the same idempotency key shall not create duplicate memories.
- **FR-042 · P1:** Clients should subscribe to realtime changes; timed refresh is an acceptable fallback.
- **FR-043 · P0:** Each client shall provide a manual retry or refresh action.

### Delete

- **FR-050 · P0:** A user shall delete a memory after confirmation.
- **FR-051 · P0:** Deletion shall be reflected on all clients.
- **FR-052 · P1:** The system should use soft deletion during the hackathon to allow recovery from demo mistakes.

### Demo and diagnostics

- **FR-060 · P0:** The repository shall include deterministic seed data.
- **FR-061 · P0:** The team shall be able to reset the demo workspace to its seed state.
- **FR-062 · P0:** User-facing errors shall contain a useful recovery action without exposing secrets.
- **FR-063 · P1:** A hidden or development-only diagnostics view should show API reachability and last sync time.

## 2. Platform requirements

### Web

- **WEB-001 · P0:** Support current Chrome/Chromium at desktop width.
- **WEB-002 · P0:** Provide responsive layouts down to 360 px width.
- **WEB-003 · P0:** Implement create, list, search, detail, and delete.
- **WEB-004 · P1:** Support keyboard navigation and visible focus.

### Desktop

- **DESK-001 · P0:** Run locally on the primary demo operating system using Tauri or equivalent shell.
- **DESK-002 · P0:** Display the shared library and search.
- **DESK-003 · P0:** Provide a quick-capture entry point.
- **DESK-004 · P1:** Preserve a locally queued capture through an app restart.
- **DESK-005 · P2:** Add a global shortcut only after the basic window flow is stable.

### Mobile

- **MOB-001 · P0:** Run through Expo Go or a development build on one physical Android or iOS device.
- **MOB-002 · P0:** Implement list, create, search, detail, and sync status.
- **MOB-003 · P1:** Queue a new memory while offline and retry later.
- **MOB-004 · P1:** Respect safe areas and the on-screen keyboard.
- **MOB-005 · P2:** Add Share Sheet intake only if the core flow is complete.

## 3. API contract

Canonical schemas live in `packages/contracts`. Only User 1, the backend owner, merges contract changes after the affected platform owners approve them.

### Memory

```ts
type Memory = {
  id: string;
  workspaceId: string;
  content: string;
  tags: string[];
  source: {
    type: "manual_note" | "conversation_excerpt" | "import";
    platform: "web" | "desktop" | "mobile" | "chatgpt" | "claude" | "gemini";
    label?: string;
    url?: string;
  };
  syncState?: "saving" | "synced" | "offline" | "failed";
  createdAt: string;
  updatedAt: string;
  deletedAt?: string;
};
```

### Minimum endpoints

```text
GET    /health
GET    /v1/memories?query=&cursor=&limit=
POST   /v1/memories
GET    /v1/memories/:id
DELETE /v1/memories/:id
POST   /v1/demo/reset
```

### Error shape

```ts
type ApiError = {
  code: "VALIDATION" | "UNAUTHORIZED" | "NOT_FOUND" | "CONFLICT" | "RATE_LIMITED" | "INTERNAL";
  message: string;
  retryable: boolean;
  requestId: string;
};
```

## 4. Non-functional requirements

- **NFR-001 · P0:** TypeScript strict mode shall be enabled across shared contracts and clients.
- **NFR-002 · P0:** API inputs shall be validated at runtime.
- **NFR-003 · P0:** Secrets shall not be committed, logged, or sent to clients.
- **NFR-004 · P0:** A workspace identifier shall scope every read and write.
- **NFR-005 · P0:** The P95 list/search API response should be below 750 ms for the demo dataset.
- **NFR-006 · P0:** The UI shall remain functional when realtime updates fail by supporting refresh.
- **NFR-007 · P1:** Create/delete operations should be traceable by request ID.
- **NFR-008 · P1:** Interactive controls shall have accessible names and adequate contrast.
- **NFR-009 · P0:** Each app shall expose a documented one-command development start.
- **NFR-010 · P0:** Continuous integration shall run type-checks and tests for affected packages.

## 5. Acceptance tests

### AT-01 Cross-surface creation

Given the web and mobile clients use the same demo workspace, when a user creates a memory on mobile, then the memory appears on web after realtime delivery or manual refresh and retains `source.platform = mobile`.

### AT-02 Search

Given a seeded memory contains a unique phrase, when the user searches that phrase on web or desktop, then the correct memory is returned with its source and timestamp.

### AT-03 Idempotency

Given a client retries the same create request, when the server receives the same idempotency key twice, then only one memory exists.

### AT-04 Offline recovery

Given the mobile client is offline, when the user saves a memory, then it is visibly queued; when connectivity returns and retry runs, then it becomes synced exactly once.

### AT-05 Delete propagation

Given a memory exists on all clients, when the user confirms deletion on web, then it no longer appears on desktop or mobile after synchronization or refresh.

### AT-06 Failure clarity

Given the API is unavailable, when a client attempts to load or save, then the UI shows an understandable error and a retry action without discarding entered text.

## 6. Definition of release candidate

- All P0 requirements pass.
- The golden-path acceptance test passes twice from a reset dataset.
- No secret exists in Git history or client bundles.
- CI is green on `main`.
- Each platform has a short runbook and known-limitations section.
- P1/P2 omissions are recorded rather than hidden.
