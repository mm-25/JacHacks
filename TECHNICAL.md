# Sherry Hackathon Technical Architecture

Status: implementation contract  
Audience: the three human builders and their AI tools  
Related files: `PLAN.md`, `PRODUCT.md`, `REQUIREMENTS.md`, `ROADMAP.md`

## 1. Non-negotiable technology constraint

**Everything in Sherry must be implemented in Jac.**

This applies regardless of the infrastructure, database, cloud provider, hosting platform, packaging service, or deployment target the team selects.

Jac is the application language for:

- shared domain models
- persistent graph and data behavior
- walkers and application operations
- authentication and authorization logic
- backend/service behavior
- web UI
- desktop UI and packaging
- mobile UI and packaging
- validation, tests, and deployment workflows

Infrastructure may host, store, route, build, or distribute the application, but it must not become a second application stack. Do not independently rebuild Jac application logic in TypeScript, JavaScript, Python, Rust, Kotlin, Swift, Java, or another language.

If Jac generates target-specific artifacts or uses an underlying ecosystem internally, those are compiler outputs—not separately maintained source implementations.

This file supersedes earlier stack suggestions in the hackathon documents that name React, TypeScript, Tauri, Expo, Node, Zod, or a handwritten REST client as the main implementation layer. Such tools may exist beneath a Jac build only when Jac officially generates or invokes them and the team does not maintain duplicate application logic in them.

## 2. Technical decision in one sentence

Sherry is one Jac workspace containing shared memory nodes, edges, walkers, permissions, and Jac-authored interfaces that compile or run as backend, web, desktop, and mobile targets against one persistent graph.

## 3. System layout

```text
                         ONE JAC WORKSPACE

┌───────────────────────────────────────────────────────────────────┐
│ Shared Jac domain                                                 │
│ Memory · User · Workspace · Source · Device                       │
│ Graph edges · permissions · validation · shared semantics         │
│                                                                   │
│ Shared Jac walkers                                                │
│ create_memory · list_memories · search_memories                   │
│ get_memory · delete_memory · sync_status                          │
└───────────────┬──────────────────┬──────────────────┬──────────────┘
                │                  │                  │
                ▼                  ▼                  ▼
       ┌────────────────┐ ┌────────────────┐ ┌────────────────┐
       │ Jac web target │ │ Jac desktop    │ │ Jac mobile     │
       │ Browser UI     │ │ OS webview     │ │ Android / iOS  │
       │ User 2         │ │ User 2         │ │ User 3         │
       └────────┬───────┘ └────────┬───────┘ └────────┬───────┘
                │                  │                  │
                └────────── walker invocations ──────┘
                                   │
                                   ▼
                     ┌────────────────────────┐
                     │ Jac service runtime    │
                     │ Auth + graph + walkers │
                     │ User 1                 │
                     └────────────┬───────────┘
                                  │
                                  ▼
                     ┌────────────────────────┐
                     │ Persistence / infra    │
                     │ selected later         │
                     └────────────────────────┘
```

### Architectural boundary

- UI surfaces invoke Jac walkers rather than maintaining platform-specific business logic.
- Walkers are the authoritative application operations.
- Shared Jac nodes, edges, objects, enums, and abilities are the domain contract.
- Persistence is reached through the Jac runtime and graph model.
- Web, desktop, and mobile must not define separate versions of `Memory` or duplicate CRUD rules.
- Hosting and persistence choices may change without changing product behavior.

## 4. Why Jac changes the architecture

A conventional implementation would define a backend, REST routes, serializers, a TypeScript API client, and separate web/mobile models. That is intentionally not the architecture here.

Jac's official direction is a single language and compiler across browser, cloud, native, desktop, and mobile targets. Its object-spatial model expresses data as nodes and edges, and walkers carry operations through that graph. The compiler/runtime supplies glue that would otherwise be handwritten as route tables, ORM mappings, serializers, and duplicated client contracts.

Therefore:

- The shared Jac program is the source of truth.
- A walker invocation replaces most handwritten CRUD endpoint/client pairs.
- A shared type change should surface incompatible uses across targets.
- Desktop and mobile are Jac build targets, not independent applications that happen to call the same server.
- Infrastructure is an operational choice, not permission to introduce another implementation language.

## 5. Repository layout and ownership

```text
sherry/
├── jac.toml                         # User 1 coordinates shared config
├── core/                            # User 1 owns domain contract
│   ├── models.jac                   # nodes, edges, objects, enums
│   ├── permissions.jac
│   ├── validation.jac
│   └── errors.jac
├── services/                        # User 1 owns backend behavior
│   ├── memory_walkers.jac
│   ├── auth_walkers.jac
│   ├── sync_walkers.jac
│   ├── seed_walkers.jac
│   └── main.jac
├── web/                             # User 2 owns web surface
│   ├── pages/
│   ├── components/
│   ├── state/
│   └── main.jac
├── desktop/                         # User 2 owns desktop surface
│   ├── shell/
│   ├── quick_capture/
│   └── main.jac
├── mobile/                          # User 3 owns mobile surface
│   ├── screens/
│   ├── components/
│   ├── state/
│   └── main.jac
├── tests/
│   ├── core/
│   ├── services/
│   ├── web/
│   ├── desktop/
│   └── mobile/
├── fixtures/
│   └── demo_memory.jac
└── docs/
```

The exact folders may be adjusted to match the installed Jac version and official templates. The ownership boundaries must remain.

| User | Primary area | Owned paths |
|---|---|---|
| User 1 | Jac backend, graph, auth, shared domain | `core/**`, `services/**`, shared `jac.toml` changes |
| User 2 | Jac web and desktop targets | `web/**`, `desktop/**` |
| User 3 | Jac mobile target | `mobile/**` |

User 1 owns shared domain files because every surface imports them. Users 2 and 3 request changes through an integration item. All three people approve breaking changes.

## 6. Jac stack by target

| Layer | Jac implementation | Owner |
|---|---|---|
| Domain | Jac nodes, edges, objects, enums, abilities | User 1 |
| Application operations | Jac walkers | User 1 |
| Authorization | Jac auth/permission logic around walkers and graph access | User 1 |
| Persistence | Jac persistent graph/runtime capabilities | User 1 |
| Backend/service | Jac service target served by the Jac runtime | User 1 |
| Web | Jac web/full-stack UI target | User 2 |
| Desktop | Jac desktop/OS-webview target | User 2 |
| Mobile | Jac mobile target and mobile UI capabilities | User 3 |
| Cross-tier communication | Jac-generated walker invocation | Shared contract |
| Validation | Jac types and explicit validation abilities | User 1 |
| Tests | Jac-authored tests and target smoke tests | Each owner |
| Deployment | `jac run`, `jac build`, and supported `jac scale` workflows | User 1 coordinates |

### Prohibited source-of-truth replacements

Do not maintain:

- a parallel TypeScript `Memory` interface
- a Zod copy of Jac domain types
- a handwritten JavaScript or Python API duplicating walkers
- a separate React business-logic application
- independent Kotlin/Swift mobile domain models
- a Rust desktop business-logic layer
- an ORM schema that competes with the Jac graph
- a second authorization implementation in infrastructure code

Small platform adapters are allowed only when the Jac toolchain requires them and Jac cannot express that boundary. They must contain no product rules, remain minimal, and be documented as exceptions.

## 7. Shared domain model

The exact syntax must follow the installed Jac version's official guide. Conceptually:

```text
root
 └── Workspace
      ├── MEMBER ──> User
      ├── CONTAINS ──> Memory
      └── REGISTERED_DEVICE ──> Device

Memory
 ├── content
 ├── tags
 ├── source_type
 ├── source_platform
 ├── source_label
 ├── source_url
 ├── created_at
 ├── updated_at
 ├── deleted_at
 └── created_by
```

Minimum concepts:

- `User`, `Workspace`, `Memory`, `Device`
- `Membership`, `ContainsMemory`, and `RegisteredDevice` edges
- `MemorySource`, `Platform`, and `AppError`

### Domain invariants

- A memory belongs to exactly one workspace.
- A caller may access it only through an authorized workspace relationship.
- Content is non-empty and limited to 20,000 characters.
- Tags contain at most 20 items of at most 40 characters each.
- Timestamps use UTC.
- Delete is soft delete for the hackathon.
- Active queries exclude deleted memories.
- Every create command includes a workspace-scoped idempotency key.
- Every memory records its source platform.

## 8. Walker contract

Walkers are the integration surface across all targets.

| Walker | Input | Output | Authorization |
|---|---|---|---|
| `health` | none | service/build status | public or development-only |
| `current_workspace` | authenticated caller | workspace summary | member |
| `list_memories` | cursor, limit | memory page | member |
| `search_memories` | query, cursor, limit | memory page | member |
| `get_memory` | memory ID | memory detail | member of owning workspace |
| `create_memory` | content, tags, source, idempotency key | memory | member |
| `delete_memory` | memory ID | deletion result | member with delete permission |
| `sync_status` | device ID | synchronization status | owning user |
| `reset_demo` | reset confirmation | seeded workspace | demo only |

Rules:

- Inputs and reports use shared Jac types.
- Authenticated walkers derive identity from the session, never an untrusted `user_id` parameter.
- Workspace authorization runs before traversal or mutation.
- Walkers return stable, user-safe error codes.
- Walkers never report secrets or internal stack traces.
- Mutation walkers are safe to retry where practical.
- `create_memory` returns the original result for a repeated idempotency key.

## 9. Common connection model

```text
User authenticates through the Jac application
    ↓
Jac runtime establishes an authenticated session
    ↓
Jac UI invokes a named walker with typed input
    ↓
Walker derives identity and checks workspace relationship
    ↓
Walker traverses or mutates the persistent graph
    ↓
Walker reports typed result
    ↓
Jac UI updates its view state
```

There is no independently handwritten API contract for one platform. If deployment exposes HTTP internally, that transport is an implementation detail of the Jac runtime or generated service surface.

## 10. Web-to-backend integration

- Pages and components are authored in Jac using the current Jac web/full-stack model.
- Web code imports the shared Jac domain types.
- User actions invoke shared walkers.
- The Jac compiler/runtime handles the browser/server boundary.
- Web code owns layout, browser navigation, responsive behavior, and interaction state.
- Web code does not own persistence, authorization, or memory rules.

```text
Jac web screen
  → user selects Save
  → invoke create_memory walker
  → Jac runtime transfers typed operation to service side
  → walker validates authenticated workspace
  → walker creates Memory in persistent graph
  → typed result returns
  → web screen refreshes/inserts result
```

Web responsibilities:

- Sign-in/out presentation.
- List, detail, search, create, and delete interactions.
- Loading, empty, offline, permission, and failure states.
- Responsive layout down to 360 px.
- Keyboard navigation and visible focus.
- Refresh/reconnect control.

Integration test: create a uniquely named memory, reload the browser, find it with `search_memories`, and verify `source_platform = web`.

## 11. Desktop-to-backend integration

- Desktop is a Jac desktop build target using the supported OS-webview model.
- It reuses web-oriented Jac components where supported.
- Desktop-only Jac code owns the app window, quick capture, lifecycle, and packaging.
- It invokes the same shared walkers as web and mobile.
- It does not embed a separate backend or access persistence directly.

```text
Jac desktop window
  → user opens Quick Capture
  → invoke create_memory walker
  → shared Jac service performs authorized mutation
  → result returns to desktop view
  → desktop shows Synced or actionable failure
```

Desktop responsibilities:

- Package and open on the demo operating system.
- Present the shared library, search, and detail.
- Provide quick capture.
- Preserve or recover an unsent draft after failure.
- Restore the session for the expected demo lifecycle.

Integration test: create on desktop and find it on web without translating or copying its domain representation.

## 12. Mobile-to-backend integration

- Mobile is authored in Jac using the current Jac mobile UI capability.
- The Jac compiler produces the supported Android/iOS target.
- Mobile screens use shared domain types and invoke the same walkers.
- Mobile Jac code owns navigation, safe areas, input, connectivity display, and optional offline-command storage.
- It does not implement a parallel REST client or duplicate backend rules.

```text
Jac mobile screen
  → user enters a note
  → app generates an idempotency key
  → invoke create_memory walker
  → authenticated Jac service performs mutation
  → result returns
  → mobile marks memory Synced
```

A physical device cannot reach a laptop service through the phone's `localhost`. Use:

1. Preferred: a deployed preview Jac service.
2. Local fallback: the laptop's LAN address with both devices on one network.
3. A protected tunnel only when necessary and only with fake data.

The service address may change; the walker contract must not.

### Offline behavior

P0:

- Preserve the draft.
- Show that saving failed or is waiting.
- Offer Retry.

P1 queue:

```text
Offline save
  → generate idempotency key
  → store pending Jac command locally
  → show Pending
  → reconnect
  → invoke create_memory with the same key
  → receive one original/new memory
  → remove pending command
```

Integration test: create on mobile, verify on web and desktop, retry the same command, and confirm one graph memory.

## 13. Authentication and authorization

Use the Jac-supported authentication/session mechanism selected for the pinned toolchain. If an external identity provider such as Supabase Auth, Firebase Auth, Auth0, or another cloud identity service is selected, Jac remains responsible for application-level session interpretation and authorization.

```text
Identity provider or Jac auth verifies credentials
    ↓
Jac runtime associates caller with User node/session
    ↓
UI invokes walker
    ↓
Walker derives authenticated User
    ↓
Walker verifies User ─MEMBER→ Workspace
    ↓
Walker accesses only authorized graph data
```

For the hackathon, prefer the simplest Jac-supported email/password flow. Magic links and social OAuth add target-specific deep-link handling.

Rules:

- Never trust user/workspace identity supplied as normal walker input.
- Never store privileged infrastructure credentials in client builds.
- Never authorize only by hiding UI.
- Log outcomes without logging credentials or memory content.
- Use fake data and a dedicated demo identity.

## 14. Persistence and infrastructure

Jac is the application abstraction; infrastructure is replaceable.

Acceptable deployments may use:

- Jac's local/default persistent graph for development.
- Jac Scale or another Jac-supported hosted runtime.
- Cloud storage integrated beneath the Jac runtime.
- Containers, VMs, or managed compute hosting the Jac service.

Regardless of selection:

- Graph structure and business rules remain in Jac.
- Walkers remain the operation boundary.
- No platform directly queries storage.
- No ORM/domain model competes with the Jac graph.
- Switching infrastructure must not rewrite client product logic.
- Infrastructure adapters remain behind Jac modules owned by User 1.

By the end of scaffolding, User 1 must prove:

1. A `Memory` survives service restart.
2. Two authenticated sessions see the same authorized workspace.
3. Unauthorized sessions cannot traverse it.
4. Demo data resets predictably.

If the preferred host cannot pass these quickly, use the simplest verified Jac-supported persistence for the hackathon.

## 15. Synchronization

The persistent Jac graph is authoritative. Clients may cache view state but reconcile through walkers.

Minimum:

- Refresh after every successful mutation.
- Refresh when returning to foreground.
- Provide manual Refresh.
- Display last successful refresh time.

Optional live synchronization:

- Use a stable Jac-supported event/subscription mechanism.
- Treat events as invalidation signals.
- Refetch after reconnect.
- Never block the golden path on live sync.

Do not build three different synchronization models. Define shared semantics in Jac and use only target-specific lifecycle hooks.

## 16. Shared error contract

| Code | Meaning | Retryable |
|---|---|---|
| `VALIDATION` | Input violates an invariant | No |
| `UNAUTHENTICATED` | No valid session | After sign-in |
| `FORBIDDEN` | Caller lacks workspace access | No |
| `NOT_FOUND` | Item absent or inaccessible | No |
| `CONFLICT` | Idempotency/state conflict | Depends |
| `OFFLINE` | Target cannot reach service | Yes |
| `RATE_LIMITED` | Infrastructure throttled request | Yes, delayed |
| `INTERNAL` | Unexpected service failure | Usually |

Every target maps these shared codes to user-facing states. Do not parse exception strings to infer behavior.

## 17. Idempotency

`create_memory` performs this logical transaction:

1. Resolve the authenticated workspace.
2. Find an existing result under `(workspace, idempotency_key)`.
3. If found, report the original memory.
4. Otherwise create the memory and associate the key.
5. Persist atomically.

The graph may use a request node or indexed field supported by the selected Jac persistence layer. User 1 documents the exact choice.

## 18. Environments

| Environment | Purpose | Data |
|---|---|---|
| Local | Individual development/tests | Disposable fixtures |
| Preview | Continuous three-person integration | Shared fake data |
| Demo | Frozen presentation | Resettable seed data |

Commit safe example configuration, never local secrets. Public endpoints may appear in clients; privileged credentials may not.

Keep configuration names consistent even if Jac maps them differently per target:

```text
SHERRY_ENV=local|preview|demo
SHERRY_SERVICE_URL=<jac-service-origin>
SHERRY_AUTH_MODE=<selected-mode>
SHERRY_LIVE_SYNC=false|true
```

Use the pinned Jac release's configuration mechanism rather than inventing platform-specific loaders.

## 19. Three-user integration sequence

### A — Verify Jac targets

All three install the same pinned Jac version and prove:

- `jac run` works.
- Shared core compiles.
- A minimal web target runs.
- A minimal desktop target builds/runs.
- A minimal mobile target runs on the chosen device/environment.

Do this before product work. Unsupported assumptions must be discovered at the start.

### B — Freeze graph and walkers

User 1 provides shared nodes/edges/objects, errors, walker signatures, fixtures, and reset behavior. Users 2 and 3 confirm every screen can use those reports. Tag `jac-contract-v1`.

### C — Parallel work

- User 1 implements persistence, auth, permissions, and walkers.
- User 2 builds Jac web screens and desktop target.
- User 3 builds Jac mobile screens.
- Users 2 and 3 use Jac fixtures/mock walker reports until Preview is ready.

Mocks use the same Jac types and report shapes; they are not separate JSON contracts.

### D — First shared service

User 1 deploys Preview and provides the service URL, authentication flow, fake credentials privately, build identifier, and reset instructions.

Each owner runs:

1. authenticate
2. `current_workspace`
3. `create_memory`
4. `list_memories`
5. `search_memories`
6. `get_memory`
7. `delete_memory`

### E — Cross-target test

1. Create on mobile; find on web.
2. Create on web; find on desktop.
3. Search one unique phrase on every target.
4. Delete on desktop; verify absence elsewhere.
5. Repeat a create with one idempotency key; verify one memory.
6. Stop the service; verify all targets preserve intent and offer recovery.

## 20. Contract-change workflow

1. User 2 or 3 records the missing capability and user flow.
2. User 1 proposes an additive Jac type/walker change.
3. Affected target owners approve it.
4. User 1 updates contract, fixture, and service first.
5. User 1 identifies the integration commit/tag.
6. Target owners rebase and adopt it.

No target creates a local substitute model or custom operation to bypass the shared Jac contract.

## 21. AI-tool rules

- Every prompt states that the project is Jac-only.
- AI tools consult the installed Jac guide and current official docs before unfamiliar syntax.
- AI tools edit only their user's owned paths unless a human authorizes a shared change.
- AI tools must not introduce a familiar second stack.
- AI tools must not handwrite glue Jac is intended to generate.
- AI tools do not merge PRs or resolve cross-user conflicts without review.
- Generated Jac must compile/test; plausible syntax without verification is unacceptable.

Persistent instruction:

> This project is implemented end to end in Jac. Do not replace Jac application code with TypeScript, JavaScript, Python, Rust, Kotlin, Swift, Java, or a parallel framework stack. Use the installed Jac guide and official current documentation, compile the result, and keep business logic in shared Jac models and walkers.

## 22. Testing responsibilities

### User 1

- Domain invariants and walker reports.
- Authentication/workspace isolation.
- Idempotency and persistence restart.
- Search, soft delete, and reset.

### User 2

- Web CRUD/search flow and system states.
- Browser responsiveness and keyboard use.
- Desktop quick capture and packaged smoke test.

### User 3

- Mobile CRUD/search flow.
- Keyboard/safe-area behavior.
- Physical-device Preview connection.
- Session, draft preservation, and retry.

All three jointly run the cross-target acceptance sequence on the exact presentation commit and Jac build.

## 23. CI and merge gates

CI must use the pinned Jac toolchain and commands supported by that release. It must:

- validate/compile all Jac source
- run Jac tests
- verify service and web targets
- verify or smoke-check desktop and mobile targets where CI permits
- reject prohibited parallel application-language source unless generated or an approved adapter

Suggested policy: fail when new `.ts`, `.tsx`, `.js`, `.jsx`, `.py`, `.rs`, `.kt`, `.swift`, or `.java` application files appear outside generated directories and documented adapter exceptions.

Generated artifacts should not normally be committed. If deployment requires them, mark them generated and never edit them manually.

## 24. Deployment layout

```text
Jac source workspace
    ├── jac run / serve       → local and preview service
    ├── Jac web build         → browser deployment
    ├── Jac desktop build     → presentation laptop
    ├── Jac mobile build      → presentation phone
    └── jac scale deploy      → hosted Jac deployment when selected
```

Choose infrastructure after proving Jac targets. The provider must accommodate the Jac output; the application must not be rewritten for the provider.

## 25. Failure and fallback matrix

| Failure | Preferred recovery | Hackathon fallback |
|---|---|---|
| Cloud cannot host Jac runtime | Choose a Jac-compatible host | Run on controlled demo machine |
| Live sync unstable | Refetch on focus | Manual Refresh |
| Desktop packaging unstable | Fix Jac target config | Supported Jac dev mode |
| Mobile packaging unstable | Use supported Jac dev workflow | Previously verified build/device |
| Phone cannot reach local service | Use deployed Preview | LAN address/protected tunnel |
| Auth callbacks differ | Simpler Jac-supported email/password | Demo identity |
| Offline queue incomplete | Preserve draft and Retry | Require demo network |
| Docs differ from installed tool | Pin verified version; use `jac guide` | Reduce scope, never replace Jac |

No fallback may replace the application with a non-Jac implementation.

## 26. Security minimums

- Keep privileged infrastructure credentials out of clients.
- Derive identity from authenticated Jac sessions.
- Enforce workspace permission in shared walkers.
- Validate every walker input.
- Do not log credentials, memory content, or sensitive payloads.
- Use HTTPS for every non-local service connection.
- Use fake Preview/Demo data.
- Protect or disable `reset_demo` outside Demo.
- Test unauthorized graph traversal.
- Document adapters and prove they contain no business logic.

## 27. Definition of done

- All maintained application source is Jac except documented generated artifacts/minimal adapters.
- One pinned Jac version builds every required target.
- All targets use the same Jac domain definitions and walkers.
- No target contains an independent API/domain implementation.
- Persistence and authorization occur behind the Jac service boundary.
- Cross-target create, list, search, detail, and delete pass.
- A repeated idempotency key produces one memory.
- Manual refresh works without optional live synchronization.
- Demo data resets deterministically.
- Presentation commit, Jac version, service deployment, and builds are recorded.

## 28. Required technical spikes

Resolve during scaffolding using the pinned Jac release:

1. Confirm the current command/template for a full-stack web project.
2. Confirm the desktop workflow and supported host systems.
3. Confirm the mobile workflow and device requirements.
4. Confirm recommended authentication across all targets.
5. Confirm persistence for local, Preview, and deployed runtimes.
6. Confirm optional event/subscription support.
7. Confirm target-specific secure session storage.
8. Confirm CI commands for every target.

Record verified commands in the repository README. Do not guess when `jac guide` can verify them.

## 29. Official references

- Current documentation: https://jaclang.org/docs/latest
- Full-stack and target overview: https://jaclang.org/
- Install guide: https://jaclang.org/docs/latest/quick-guide/install

The official Jac site describes one language spanning browser, cloud, native, desktop, and mobile, with graph persistence and walker-based cross-tier behavior. Because Jac is evolving, the pinned compiler and its `jac guide` output are authoritative for exact syntax and commands.
