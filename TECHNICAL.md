# Sherry Hackathon Technical Architecture

Status: implementation contract  
Audience: the three human builders and their AI tools  
Related files: `PLAN.md`, `PRODUCT.md`, `REQUIREMENTS.md`, `ROADMAP.md`

## 1. Technical decision in one sentence

Web, desktop, and mobile are separate clients that authenticate with Supabase Auth and communicate with one backend through the same versioned HTTPS API and shared TypeScript schemas; only the backend talks to Postgres.

This document is the technical source of truth. If a platform needs behavior not described here, the three users agree on a contract change before implementation.

## 2. System layout

```text
┌────────────────────────────── Clients ──────────────────────────────┐
│                                                                     │
│  Web                         Desktop                    Mobile       │
│  React + Vite               Tauri + React/Vite         Expo RN      │
│  Browser fetch              WebView fetch              Native fetch│
│  Supabase Auth client       Supabase Auth client       Supabase Auth│
│  User 2                     User 2                     User 3       │
│       │                          │                          │         │
└───────┼──────────────────────────┼──────────────────────────┼─────────┘
        │             HTTPS + JSON + Bearer JWT              │
        └──────────────────────────┼──────────────────────────┘
                                   ▼
                    ┌──────────────────────────┐
                    │ Versioned API            │
                    │ Supabase Edge Functions  │
                    │ or one Node/Worker API   │
                    │ User 1 owns              │
                    └─────────────┬────────────┘
                                  │ validates JWT,
                                  │ workspace and input
                                  ▼
                    ┌──────────────────────────┐
                    │ Supabase Postgres        │
                    │ memories + workspaces    │
                    │ idempotency + soft delete│
                    └─────────────┬────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────┐
                    │ Supabase Realtime        │
                    │ change notification only │
                    └──────────────────────────┘
```

### Critical boundary

- Clients call the API; clients do not contain SQL or service-role credentials.
- `packages/contracts` defines the data shapes.
- `packages/api-client` defines how every client makes requests.
- The backend owns validation, authorization, database access, and error conversion.
- Realtime tells a client that data changed. The client then refreshes through the API. Realtime is not the authoritative data path.

## 3. Why this architecture

### Preferred hackathon approach

Use Supabase for Auth, Postgres, and Realtime, with a thin server API implemented as Supabase Edge Functions. This minimizes infrastructure while preserving a clear server boundary.

Benefits:

- One database and identity system.
- The same JWT works across browser, Tauri, and Expo.
- Server-only secrets stay in the backend environment.
- The API can enforce identical rules for every client.
- Postgres changes can notify all active clients.

### Faster fallback

If Edge Function setup becomes a blocker, deploy the same `/v1` handlers as a small Node/Fastify service or Cloudflare Worker. Keep `packages/contracts` and `packages/api-client` unchanged. Clients should only need a different public API base URL.

### Rejected approach for this build

Do not let each client query Supabase tables directly. Supabase can safely support frontend access when RLS is configured, but mixing direct database queries with a custom API creates two data-access patterns, duplicates authorization logic, and makes the three platforms more likely to drift.

## 4. Monorepo structure and ownership

```text
sherry/
├── apps/
│   ├── web/                       # User 2
│   │   ├── src/app/
│   │   ├── src/features/memories/
│   │   ├── src/lib/
│   │   └── .env.example
│   ├── desktop/                   # User 2
│   │   ├── src-tauri/
│   │   ├── capabilities/
│   │   └── README.md
│   └── mobile/                    # User 3
│       ├── app/                   # Expo Router routes
│       ├── src/features/memories/
│       ├── src/lib/
│       └── .env.example
├── packages/
│   ├── contracts/                 # User 1; no platform UI
│   │   ├── src/memory.ts
│   │   ├── src/errors.ts
│   │   └── src/index.ts
│   ├── api-client/                # User 1
│   │   ├── src/client.ts
│   │   ├── src/auth-provider.ts
│   │   └── src/index.ts
│   ├── fixtures/                   # User 1
│   └── ui-web/                     # User 2; web and desktop only
├── services/
│   └── api/                        # User 1
│       ├── functions/v1-memories/
│       ├── src/auth/
│       ├── src/repositories/
│       └── tests/
├── supabase/
│   ├── migrations/                 # User 1 only
│   └── seed.sql                    # User 1 only
├── docs/
├── package.json
├── pnpm-workspace.yaml
└── turbo.json
```

### Ownership rule

User 1 owns the contract and backend. User 2 owns web and desktop. User 3 owns mobile. A platform owner may request a contract change but does not modify the contract package or migrations directly.

## 5. Technology stack by surface

| Layer | Choice | Purpose | Owner |
|---|---|---|---|
| Language | TypeScript, strict mode | One typed language across clients and shared packages | All |
| Package manager | pnpm workspaces | Monorepo dependency management | User 1 owns root config |
| Task runner | Turborepo | Scoped build, test, lint, and type-check | User 1 |
| Backend | Supabase Edge Functions | Versioned HTTPS API | User 1 |
| Database | Supabase Postgres | Durable memory storage | User 1 |
| Authentication | Supabase Auth | User identity and JWT sessions | User 1 contract; each client integrates |
| Realtime | Supabase Realtime | Change notifications | User 1 config; clients subscribe |
| Validation | Zod | Shared compile-time/runtime request schemas | User 1 |
| Web | React + Vite | Browser application | User 2 |
| Web data state | TanStack Query | Fetch, cache, invalidate, retry | User 2 |
| Desktop | Tauri 2 + web build | Lightweight desktop shell | User 2 |
| Mobile | Expo React Native + Expo Router | Android/iOS development | User 3 |
| Mobile server state | TanStack Query | Same query/invalidation model | User 3 |
| Mobile token storage | Expo SecureStore | Encrypted local session storage | User 3 |
| Tests | Vitest + Testing Library | Unit/component tests | Each owner |
| API tests | Vitest or Deno tests | Contract and authorization tests | User 1 |
| End-to-end | Playwright for web | Golden-path browser test | User 2 |

Pin exact versions when the repository is initialized and commit the lockfile. Do not independently upgrade framework versions during the hackathon.

## 6. Shared domain contract

The contract package exports both TypeScript types and Zod schemas. The backend parses all input with these schemas; clients use the inferred types.

```ts
import { z } from "zod";

export const MemorySourceSchema = z.object({
  type: z.enum(["manual_note", "conversation_excerpt", "import"]),
  platform: z.enum([
    "web",
    "desktop",
    "mobile",
    "chatgpt",
    "claude",
    "gemini",
  ]),
  label: z.string().max(120).optional(),
  url: z.string().url().optional(),
});

export const MemorySchema = z.object({
  id: z.string(),
  workspaceId: z.string(),
  content: z.string().min(1).max(20_000),
  tags: z.array(z.string().max(40)).max(20),
  source: MemorySourceSchema,
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
  deletedAt: z.string().datetime().nullable(),
});

export const CreateMemoryInputSchema = z.object({
  content: z.string().trim().min(1).max(20_000),
  tags: z.array(z.string().trim().min(1).max(40)).max(20).default([]),
  source: MemorySourceSchema,
  idempotencyKey: z.string().min(16).max(128),
});

export type Memory = z.infer<typeof MemorySchema>;
export type CreateMemoryInput = z.infer<typeof CreateMemoryInputSchema>;
```

### Contract rules

- JSON uses camelCase.
- Timestamps are UTC ISO 8601 strings.
- IDs are opaque strings; clients do not parse them.
- `source.platform` is supplied by the client but validated by the backend.
- New response fields must be optional until all clients adopt them.
- Removing, renaming, or changing a field requires a new API version or coordinated migration.
- Every write accepts an idempotency key.

## 7. Database layout

Minimum schema:

```sql
create table workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table workspace_members (
  workspace_id uuid not null references workspaces(id),
  user_id uuid not null references auth.users(id),
  role text not null check (role in ('owner', 'member')),
  primary key (workspace_id, user_id)
);

create table memories (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references workspaces(id),
  content text not null,
  tags text[] not null default '{}',
  source_type text not null,
  source_platform text not null,
  source_label text,
  source_url text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table idempotency_keys (
  workspace_id uuid not null references workspaces(id),
  key text not null,
  memory_id uuid not null references memories(id),
  created_at timestamptz not null default now(),
  primary key (workspace_id, key)
);
```

Required indexes:

- `memories(workspace_id, created_at desc)` for the library.
- `memories(workspace_id, deleted_at)` for active items.
- A Postgres full-text index if plain `ILIKE` search becomes slow; for hackathon seed data, deterministic case-insensitive search is acceptable.

Use Row Level Security as defense in depth even though requests normally go through the server API. The service-role key exists only in the backend environment and is never exposed in web, desktop, or mobile builds.

## 8. HTTP API contract

Base URL examples:

```text
Local:      http://localhost:54321/functions/v1/api
Preview:    https://<project-ref>.supabase.co/functions/v1/api
Production: https://api.example.com
```

Every authenticated request includes:

```http
Authorization: Bearer <supabase-access-token>
Content-Type: application/json
X-Client-Platform: web | desktop | mobile
X-Request-ID: <uuid>
```

### Endpoints

```text
GET    /v1/health
GET    /v1/memories?query=&cursor=&limit=25
POST   /v1/memories
GET    /v1/memories/:id
DELETE /v1/memories/:id
POST   /v1/demo/reset             # development/demo only
```

### List response

```json
{
  "data": [
    {
      "id": "mem_123",
      "workspaceId": "ws_123",
      "content": "Use concise weekly project updates.",
      "tags": ["preference"],
      "source": {
        "type": "manual_note",
        "platform": "mobile",
        "label": "Quick capture"
      },
      "createdAt": "2026-09-26T18:00:00.000Z",
      "updatedAt": "2026-09-26T18:00:00.000Z",
      "deletedAt": null
    }
  ],
  "nextCursor": null
}
```

### Error response

```json
{
  "error": {
    "code": "VALIDATION",
    "message": "Memory content is required.",
    "retryable": false,
    "requestId": "req_123"
  }
}
```

HTTP mapping:

| Status | Code | Meaning |
|---|---|---|
| 400 | `VALIDATION` | Invalid client input |
| 401 | `UNAUTHORIZED` | Missing, invalid, or expired identity |
| 403 | `FORBIDDEN` | User lacks workspace access |
| 404 | `NOT_FOUND` | Memory is absent or inaccessible |
| 409 | `CONFLICT` | Idempotency or state conflict |
| 429 | `RATE_LIMITED` | Client should back off |
| 500 | `INTERNAL` | Unexpected backend failure |

## 9. Shared API client

No app writes its own request code. `packages/api-client` accepts platform-specific token and transport adapters.

```ts
type ApiClientOptions = {
  baseUrl: string;
  platform: "web" | "desktop" | "mobile";
  getAccessToken: () => Promise<string | null>;
  fetchImpl?: typeof fetch;
};

export function createApiClient(options: ApiClientOptions) {
  async function request<T>(path: string, init?: RequestInit): Promise<T> {
    const token = await options.getAccessToken();
    const requestId = crypto.randomUUID();

    const response = await (options.fetchImpl ?? fetch)(
      `${options.baseUrl}${path}`,
      {
        ...init,
        headers: {
          "Content-Type": "application/json",
          "X-Client-Platform": options.platform,
          "X-Request-ID": requestId,
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
          ...init?.headers,
        },
      },
    );

    if (!response.ok) throw await parseApiError(response);
    return response.json() as Promise<T>;
  }

  return {
    listMemories: (query = "") =>
      request<ListMemoriesResponse>(`/v1/memories?query=${encodeURIComponent(query)}`),
    createMemory: (input: CreateMemoryInput) =>
      request<Memory>("/v1/memories", {
        method: "POST",
        body: JSON.stringify(input),
      }),
    deleteMemory: (id: string) =>
      request<void>(`/v1/memories/${encodeURIComponent(id)}`, {
        method: "DELETE",
      }),
  };
}
```

The package contains no React hooks, UI state, browser globals, or mobile libraries. Each app wraps it with its own TanStack Query hooks.

## 10. Authentication flow

### Shared sequence

```text
User signs in
    ↓
Supabase Auth returns access token + refresh token
    ↓
Platform stores session using its storage adapter
    ↓
API client requests current access token
    ↓
Authorization: Bearer <JWT>
    ↓
Backend verifies JWT with Supabase Auth
    ↓
Backend resolves user's workspace membership
    ↓
Backend performs authorized query
```

### Hackathon authentication choice

Use email and password for the shared demo account. Magic links and OAuth introduce deep-link/callback differences across browser, Tauri, and mobile. Add them after the three-client data flow works.

### Session storage by platform

| Platform | Storage | Notes |
|---|---|---|
| Web | Supabase JS browser session persistence | Never store service credentials; protect against XSS |
| Desktop | WebView session for the hackathon; OS-backed secure store for production | A packaged demo on a controlled machine is acceptable; document the limitation |
| Mobile | `expo-secure-store` adapter | Store tokens only, not memory payloads |

For a production version, use an OS-backed secure credential plugin on desktop before external distribution.

## 11. How web connects to the backend

### Stack

- React + Vite + TypeScript.
- TanStack Query for server state.
- Supabase JS for authentication and Realtime only.
- Shared `@sherry/api-client` for CRUD/search.
- Shared `@sherry/contracts` for types.

### Runtime flow

```text
React screen
  → useMemories() query hook
  → @sherry/api-client
  → browser fetch over HTTPS
  → API validates Supabase JWT
  → Postgres query
  → JSON response
  → TanStack Query cache
  → React renders
```

### Web environment

```text
VITE_API_BASE_URL=https://<project-ref>.supabase.co/functions/v1/api
VITE_SUPABASE_URL=https://<project-ref>.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=<public-key>
```

All `VITE_` values are bundled into client code and therefore must be public configuration. Never put the database password or service-role key in a Vite variable.

### Web integration checklist

1. Import contract and API-client workspace packages.
2. Initialize Supabase Auth with public URL/key.
3. Pass `supabase.auth.getSession()` through `getAccessToken`.
4. Create one API client instance.
5. Wrap API calls in query/mutation hooks.
6. Invalidate `memories` after create/delete or on Realtime change.
7. Show cached data while refetching; show a retry action on failure.

## 12. How desktop connects to the backend

### Stack

- Tauri 2 shell.
- The same React/Vite build and web components as `apps/web`.
- Shared API client with `platform: "desktop"`.
- Native code only for desktop-specific capabilities such as quick capture, window control, or secure storage.

Tauri acts as a static host for the web build inside a system WebView. It does not create a second backend and does not connect to Postgres directly.

### Runtime flow

```text
Tauri window
  → shared React memory screens
  → @sherry/api-client
  → WebView fetch over HTTPS
  → same API used by web/mobile
```

Use ordinary WebView `fetch` first. If platform CORS/network behavior blocks it, inject Tauri's official HTTP plugin as `fetchImpl` in the shared API client and allowlist only the API origin in Tauri capabilities.

### Desktop-specific boundary

```text
apps/web                 reusable screens/features
apps/desktop/src-tauri   Rust shell, capabilities, packaging
apps/desktop/src         desktop-only bootstrap and quick capture
```

Do not fork the memory screens into desktop copies. The desktop bootstrap imports them from the web feature package or shared web source.

### Desktop environment

Use the same public values as web. During build, Vite-exposed variables remain public. Tauri capability configuration should allow network access only to the known API host.

### Desktop integration checklist

1. Make the web app work first.
2. Point Tauri's development URL to the Vite server.
3. Point Tauri's production frontend path to the Vite `dist` output.
4. Set the API client platform to `desktop`.
5. Verify auth persistence after restarting the packaged app.
6. Add quick capture only after list/create/search work in the wrapper.
7. Test the exact packaged binary on the demo laptop.

## 13. How mobile connects to the backend

### Stack

- Expo React Native + TypeScript.
- Expo Router for file-based screens.
- TanStack Query for server state.
- Supabase JS with an Expo SecureStore-backed auth storage adapter.
- Shared API client using the React Native global `fetch`.
- AsyncStorage or SQLite only for a small offline write queue, not as a second source of truth.

### Runtime flow

```text
React Native screen
  → useMemories() query hook
  → @sherry/api-client
  → React Native fetch over HTTPS
  → same API used by web/desktop
  → JSON response
  → TanStack Query cache
  → native UI renders
```

### Mobile environment

```text
EXPO_PUBLIC_API_BASE_URL=https://<project-ref>.supabase.co/functions/v1/api
EXPO_PUBLIC_SUPABASE_URL=https://<project-ref>.supabase.co
EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<public-key>
```

`EXPO_PUBLIC_` values are visible in the compiled application. They may contain only public configuration, never service-role keys or private API secrets.

### Physical-device development

A physical phone cannot reach the laptop through `localhost`. Use one of these:

1. Preferred: point the phone at the deployed preview API.
2. Local fallback: run the API on the laptop's LAN address and ensure both devices share a network.
3. Tunnel only if necessary, and never expose an unprotected local endpoint containing real data.

### Offline write queue

The P0 build may show an error and preserve unsaved text. If implementing the P1 queue:

```text
Create pressed while offline
  → generate idempotency key
  → store pending command locally
  → display Offline / Pending
  → connectivity returns or user taps Retry
  → send same command with same key
  → server returns existing/new memory exactly once
  → remove pending command
  → invalidate memory list
```

### Mobile integration checklist

1. Import shared contracts and API client without importing web UI.
2. Configure SecureStore as the Supabase session storage adapter.
3. Create one API client with `platform: "mobile"`.
4. Implement list/create against fixtures before the backend is ready.
5. Switch only `EXPO_PUBLIC_API_BASE_URL` to integrate.
6. Verify a physical phone can reach the preview API.
7. Verify keyboard, safe areas, app restart, token refresh, and retry behavior.

## 14. Realtime synchronization

Realtime is a notification layer, not a second CRUD path.

```text
Mobile creates memory through API
    ↓
Backend inserts into Postgres
    ↓
Postgres/Realtime emits workspace change
    ↓
Web and desktop receive notification
    ↓
Clients invalidate `memories` query
    ↓
Clients fetch authoritative list through API
```

Channel convention:

```text
workspace:<workspace-id>:memories
```

Rules:

- Subscribe only after authentication.
- Use private channels and authorize with the user's JWT.
- A Realtime message contains an event type and memory ID, not full sensitive content.
- On reconnect, always refetch; do not assume missed events were replayed.
- If Realtime fails, show no catastrophic error. Manual refresh and mutation-triggered refetch keep the app usable.

For the shortest hackathon path, start with refetch-on-focus plus a Refresh control. Add Realtime after the golden path works.

## 15. Backend request lifecycle

Every endpoint follows the same order:

1. Generate or accept a request ID.
2. Parse the bearer token.
3. Validate the user with Supabase Auth.
4. Resolve workspace membership from server-controlled data.
5. Parse query/body with the shared Zod schema.
6. Execute a parameterized repository operation.
7. Serialize with the shared response schema.
8. Return a stable error shape on failure.
9. Log request ID, route, status, latency, and user/workspace identifiers—not memory content or tokens.

### Create transaction

Within one database transaction:

1. Check `(workspace_id, idempotency_key)`.
2. If found, return the linked memory.
3. Insert the memory.
4. Insert the idempotency-key record.
5. Commit.

This is what makes mobile retry safe.

### Delete behavior

For the hackathon, `DELETE` sets `deleted_at`. All list/search/detail queries exclude deleted rows. The demo reset endpoint may restore seed data. Hard deletion is a later privacy requirement.

## 16. Local and shared environments

Use three environments:

| Environment | Purpose | Data |
|---|---|---|
| Local | Individual development and tests | Disposable fixtures |
| Preview | All three users integrate continuously | Shared fake/demo data |
| Demo | Frozen presentation environment | Resettable seed data |

Each app commits `.env.example`, never `.env.local`. Public keys and URLs may be exposed to clients; service keys stay in backend secret management.

### Cross-origin configuration

Allow only:

- The local web development origin.
- The deployed web preview origin.
- The Tauri application origin required by the selected transport.
- Requests carrying valid authorization from mobile.

Do not use unrestricted `*` CORS together with credential cookies. This architecture uses bearer tokens, but origins should still be restricted for clarity and defense in depth.

## 17. Integration sequence for the three users

### Checkpoint A — contract freeze

User 1:

- Publishes schemas, fixtures, API-client interface, and mock transport.

Users 2 and 3:

- Review field names, error shapes, and platform needs.
- Approve the contract before building screens.

Output: tag `contract-v1`.

### Checkpoint B — parallel implementation

- User 1 implements API/database/auth against contract fixtures.
- User 2 builds web screens, then runs them inside Tauri.
- User 3 builds native mobile screens.
- Users 2 and 3 use the mock transport until preview API health passes.

### Checkpoint C — first real connection

1. User 1 deploys Preview and provides only:
   - API base URL
   - Supabase URL
   - Supabase publishable key
   - demo credentials through a private channel
2. User 2 switches web and desktop environment values.
3. User 3 switches mobile environment values.
4. Each owner runs the same create/list contract test.

### Checkpoint D — cross-platform integration

Run in this order:

1. Create on mobile; refresh and inspect on web.
2. Create on web; refresh and inspect on desktop.
3. Search the same unique phrase on all three clients.
4. Delete on desktop; verify absence on web and mobile.
5. Repeat a create request with the same idempotency key; verify one row.
6. Interrupt the API; verify all clients preserve user intent and offer retry.

### Checkpoint E — optional Realtime

After Checkpoint D passes, add subscription-driven query invalidation one client at a time. A Realtime failure must never break manual refresh.

## 18. Contract-change workflow

When User 2 or User 3 needs a backend change:

1. Open an integration item describing the user flow and required field/endpoint.
2. User 1 proposes an additive schema change and updates fixtures.
3. The affected platform owners approve it.
4. User 1 merges contracts/API first and publishes a commit/tag.
5. Platform owners rebase and adopt it.

No one works around a missing backend field by inventing a platform-only version of the model.

## 19. Testing responsibilities

### User 1 — backend

- Schema parsing tests.
- Authorization and workspace-isolation tests.
- Idempotency test.
- Search and soft-delete tests.
- Seed/reset test.
- Contract fixture serialization test.

### User 2 — web and desktop

- Query/mutation hook tests using the mock transport.
- Loading, empty, failure, and retry component tests.
- Playwright golden-path test for web.
- Packaged Tauri smoke test on presentation hardware.

### User 3 — mobile

- Query/mutation hook tests using the mock transport.
- Create validation and unsaved-text preservation tests.
- Physical-device smoke test.
- Session persistence and offline/retry test.

### Shared integration test

All three people jointly run the acceptance tests in `REQUIREMENTS.md` on `main`. The person who owns the failing layer diagnoses it; another person verifies the fix.

## 20. CI and merge gates

Every PR runs only affected tasks where possible:

```text
pnpm lint
pnpm typecheck
pnpm test
pnpm build
```

Additional gates:

- Contract or migration change: User 1 approval plus one consuming platform owner.
- Web/desktop change: User 2 approval.
- Mobile change: User 3 approval.
- Root config or lockfile: User 1 coordinates; all active users rebase after merge.
- No AI tool merges or resolves integration conflicts without the responsible human reviewing the exact diff.

## 21. Deployment layout

```text
Web       → Vercel or Cloudflare Pages static deployment
Desktop   → Local signed/unsigned Tauri build for demo hardware
Mobile    → Expo Go or EAS preview build on one physical phone
API       → Supabase Edge Functions
Database  → Supabase Postgres
Auth      → Supabase Auth
Realtime  → Supabase Realtime
```

The hackathon does not require app-store submission, general desktop distribution, production code signing, or a custom domain.

## 22. Failure and fallback matrix

| Failure | Preferred recovery | Demo fallback |
|---|---|---|
| Realtime unavailable | Refetch on focus/reconnect | Refresh button |
| Edge Functions blocked | Deploy same handlers to Worker/Node | Local API on demo laptop |
| Tauri fetch/CORS issue | Use allowlisted Tauri HTTP plugin | Run desktop in dev mode |
| Packaged desktop fails | Fix capability/build config | Demonstrate in Tauri dev window |
| Expo build fails | Use Expo Go | Mobile simulator only if previously verified |
| Physical phone cannot reach local API | Use Preview API | LAN address or protected tunnel |
| Auth callback differs by platform | Use email/password | Fixed demo token only in isolated demo mode |
| Offline queue incomplete | Preserve draft and show retry | Require network for demo |
| AI summary unreliable | Disable feature flag | Core product remains unaffected |

## 23. Security minimums

- Never ship a Supabase service-role key to any client.
- Enable RLS on exposed tables and test workspace isolation.
- Validate JWTs server-side; do not trust a client-supplied user or workspace ID.
- Validate every input with shared runtime schemas.
- Do not log tokens, passwords, or memory content.
- Restrict the Tauri HTTP capability to the API host.
- Keep public configuration distinct from secrets.
- Use HTTPS for every non-local request.
- Use fake data in preview/demo environments.
- Disable or protect the demo reset endpoint outside the demo environment.

## 24. Final technical definition of done

- All clients compile against `contract-v1` without local type copies.
- Web, desktop, and mobile authenticate into the same demo workspace.
- All CRUD/search traffic uses `@sherry/api-client` and the same `/v1` API.
- No client directly accesses Postgres or contains a service credential.
- Cross-platform create, search, and delete pass.
- A duplicated create request produces one memory.
- Manual refresh works even when Realtime is disabled.
- Platform-specific session storage survives the expected demo lifecycle.
- The presentation commit, backend deployment, database migration, and seed dataset are tagged and recorded.

## 25. Official references

- Supabase Auth and JWT/RLS integration: https://supabase.com/docs/guides/auth
- Supabase secure frontend/backend data access: https://supabase.com/docs/guides/database/secure-data
- Supabase Row Level Security: https://supabase.com/docs/guides/database/postgres/row-level-security
- Supabase Realtime authorization: https://supabase.com/docs/guides/realtime/authorization
- Expo Router: https://docs.expo.dev/router/introduction/
- Expo SecureStore: https://docs.expo.dev/versions/latest/sdk/securestore/
- Expo environment variables: https://docs.expo.dev/guides/environment-variables/
- Tauri frontend configuration: https://v2.tauri.app/start/frontend/
- Tauri HTTP client plugin: https://v2.tauri.app/plugin/http-client/
- Vite environment variables: https://vite.dev/guide/env-and-mode
