# Sherry on Cloudflare (Workers + D1) with Supabase login

Live at **https://sherry.sherry-cloud.workers.dev**. It serves the web app, the API
(`/function/<name>`) and the claude.ai / ChatGPT / Gemini connector (`/mcp`).

The hosted Sherry backend. It serves the same API as the Jac server in `apps/web`
(`POST /function/<name>`, same request and response shapes, see
`data-schema-specification.md`), so every Sherry app only needs a new address and key.

```
web app ──(Supabase login token)──┐
extension / desktop sync / MCP ───┼──(Sherry API key)──▶  Cloudflare Worker  ──▶  D1 database
                                  │                        (Jac → JavaScript)
Supabase Auth ◀── sign up / sign in (web app)
```

- **Code:** written in Jac (`src/*.cl.jac`) and compiled to JavaScript with `jac jac2js`
  (`build.jac`). `src/index.js` is a three-line entry point, because Cloudflare needs a
  default export.
- **Database:** Cloudflare D1 (SQLite). The schema is in `migrations/`. It holds workspaces,
  memories, captured conversations and messages, and API keys (stored hashed).
- **Logins:** Supabase Auth. The Worker verifies Supabase access tokens against the
  project's public keys (ES256/RS256 via JWKS; the legacy HS256 secret is also supported).
  It checks the signature, expiry, issuer, audience and role.
- **API keys:** long-lived `shr_…` keys for the extension, desktop sync and MCP connector,
  which can't do an interactive login. Create them from the web app (`create_api_key`);
  only their SHA-256 hash is stored. A key can't be used to create more keys.
- **Summaries:** Claude via the official Anthropic TypeScript SDK when the Worker has an
  `ANTHROPIC_API_KEY` secret; otherwise a basic summary.

## MCP connector (`/mcp`)

This is the connector from `apps/mcp`, now running on the Worker, with the same five tools
(`save_memory`, `search_memories`, `list_recent_memories`, `get_memory`, `delete_memory`)
and the same instructions. Add `https://sherry.sherry-cloud.workers.dev/mcp` as a custom
connector in claude.ai, ChatGPT (developer mode) or Gemini (custom apps).

- **Sign-in:** OAuth 2.1. The assistant registers itself (DCR), then the user signs in on
  Sherry's page, which checks the email and password with Supabase. The assistant then
  exchanges a one-time code (PKCE S256) for tokens. Access tokens last 8 hours and refresh
  tokens 30 days; a refresh rotates both. Everything is stored hashed in D1
  (`migrations/0002`).
- **Protocol:** Streamable HTTP without sessions, using the initialize-handshake revisions up
  to 2025-11-25. A 2026-07-28 client's `server/discover` probe gets "method not found",
  and the client falls back to the handshake, as the official SDK does. Tested with the
  official Python SDK in both modes.
- **Which assistant saved it:** taken from the name the assistant registered with (Claude,
  ChatGPT, Gemini).

## Endpoints

These are the same as the Jac server's: `health`, `list_memories`, `get_memory`,
`create_memory`, `delete_memory`, `restore_memory`, `load_demo_data`, `reset_demo`,
`capture_conversation`, `summarize_conversation` and `get_conversation`.

New here:

| Endpoint | Who | Returns |
|---|---|---|
| `whoami` | anyone signed in | `{userId, email, workspaceId, isDemo, via}` |
| `create_api_key` `{name}` | web app session only | `{key, apiKey}`. `key` is shown only once. |
| `list_api_keys` | web app session only | `[{id, name, prefix, createdAt, lastUsedAt}]` |
| `revoke_api_key` `{id}` | web app session only | `bool` |
| `dashboard_stats` | anyone signed in | Everything the Dashboard and Diagnostics pages show: chats per assistant, tool mix, use cases, recalls, lookups, top platform, pipeline health |
| `list_conversations` `{cursor, limit}` | anyone signed in | `{data: [{id, platform, title, url, context, capturedVia, messages, updatedAt, …}], nextCursor, total}` |

`list_memories` also takes `kind`: `"chat"` (summaries of captured chats) or `"personal"`
(everything else). The connector records every lookup (`memory_lookups`) and bumps each
returned memory's `recall_count` (`migrations/0003_usage.sql`). **Apply that migration
(`npm run db:remote`) before deploying this code**, or the connector's searches fail.

Accounts are created and signed in through Supabase, not through `/user/login`.

## Set up (once)

You need a free **Cloudflare** account and a free **Supabase** project.

```bash
cd apps/cloud
npm install
npx wrangler login                    # opens the browser
npx wrangler d1 create sherry         # prints a database_id: put it in wrangler.jsonc
npm run db:remote                     # creates the tables in the cloud database
```

1. In `wrangler.jsonc`, set `vars.SUPABASE_URL` to your project URL
   (`https://<project>.supabase.co`, from Supabase → Project Settings → API).
2. Optional: to get Claude-written summaries, run
   `npx wrangler secret put ANTHROPIC_API_KEY`.
3. Deploy with `npm run deploy`. It prints the Worker's address
   (`https://sherry.<you>.workers.dev`).

## Run locally

Create `.dev.vars` (ignored by git) with at least `SUPABASE_URL=…`, then:

```bash
npm run db:local      # once: local copy of the database
npm run dev           # compiles the Jac and starts http://localhost:8787
```

## Cost (check current pricing)

At hackathon scale, everything fits in the free tiers:
- **Cloudflare Workers Free:** 100,000 requests a day.
- **D1 Free:** 5 GB of storage, 5 million rows read and 100,000 rows written a day.
- **Supabase Free:** 50,000 monthly active users.

The paid steps are roughly $5/month for Workers Paid and $25/month for Supabase Pro.
Claude summaries are billed separately by Anthropic, per token.

## Known limitations

- **Search is case-insensitive only for ASCII letters.** SQLite's `lower()` doesn't
  fold accented letters, so "É" and "é" don't match.
- **Summaries run inside the request.** Summarizing a very long chat with Claude can take a
  while. A queue (Cloudflare Queues) would move that out of the request.
- **Jac compiler quirks worked around here:**
  - A variable named `bytes` compiles to the string `"bytes"`, so use another name.
  - In an f-string, text starting with `'` right after `{…}` is dropped, so use `+` for
    those messages.
