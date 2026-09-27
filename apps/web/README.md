# Sherry web (Jac)

The Sherry web app and its memory database, built as one Jac fullstack project.
The same server also exposes the HTTP API that the desktop and mobile clients call.

- **UI:** `components/*.cl.jac` (compiled to React), `styles/global.css`
- **API + database:** `services/memories.sv.jac`. The Jac graph is the database and is
  persisted to SQLite under `.jac/data/`.
- **Entry point:** `main.jac`

## Run it

```bash
# one-time, from the repo root
python3 -m venv .venv
.venv/bin/pip install -r apps/requirements.txt

# from apps/web
cd apps/web
export SSL_CERT_FILE=$(../../.venv/bin/python -m certifi)   # macOS python.org builds need this for downloads
../../.venv/bin/jac install                                 # installs Bun + npm deps into .jac/
../../.venv/bin/jac start --dev main.jac                    # http://localhost:8000 (hot reload)
```

`jac start main.jac` (without `--dev`) serves the production bundle. Add `--port N`
to change the port. Server-side changes need a restart; `.cl.jac` changes hot-reload.

Type-check everything with `../../.venv/bin/jac check .`.

**Demo:** on the sign-in screen, click **Open the demo workspace**. It signs in as
`demo@sherry.app` / `sherry-demo-2026`, creating the account on first use, and loads the
sample memories. Every client that signs in with this account shares the same workspace.
It is fake demo data, so don't store anything private there. *Reset to demo data* in the
account menu appears only for the demo account.

**Real accounts start empty.** No sample data is added to them.

Wipe all local data: stop the server, then `rm -rf .jac/data`. Don't rename `[project] name`
in `jac.toml` without wiping too: graph data is stored per project name, while accounts are
stored in the shared `main.db`, so existing accounts would lose their workspace.

## Share it with your team

The database lives wherever this server runs. To let teammates' apps (desktop,
mobile, their browser extensions) use the same Sherry during the hackathon, put
your running copy online:

```bash
# stop the dev server first (Ctrl+C), then:
./share.sh
```

It runs Sherry in normal mode on port 8000 and opens a Cloudflare quick tunnel
to it (`cloudflared` from `apps/mcp/.bin/`). It prints a public
`https://….trycloudflare.com` address; teammates use that as the Sherry URL and
API base. Everyone signs in with their own account, so each person's data stays
separate. Ctrl+C stops sharing.

- **Only while it runs:** it works only while your laptop is on and the script is running.
- **New address each time:** the address changes on every start. Send teammates
  the new one, or use a fixed domain (a named Cloudflare tunnel or an ngrok
  static domain) for the demo.
- **Everything is public:** anyone with the address can reach the web app and
  create an account. Accounts are isolated from each other, but use strong
  passwords, because there is no limit on login attempts.
- **MCP connector:** the Sherry connector (`apps/mcp`) keeps working unchanged. It
  talks to Sherry on `localhost:8000` on the same machine.

For an always-on setup, deploy this same folder to a server and run
`jac start main.jac --port <port>` there.

## What the web app does

| Requirement | How |
|---|---|
| Create (FR-010/011/013) | Composer: type, then press Save or ⌘/Ctrl+Enter. The item shows as *Saving…* straight away |
| Idempotency (FR-041) | The client generates a key per capture and reuses it on every retry. The server returns the existing memory when a key repeats |
| Offline / failure (FR-014, AT-04, AT-06) | Unsent captures stay visible as *Offline* or *Not saved* cards with Retry/Discard. They're persisted in `localStorage` and retried automatically when the browser comes back online or the page reloads |
| Library (FR-020/021/023) | Newest first. Shows preview, platform chip, source label, relative time and tags. *Load more* uses cursor pagination |
| Search (FR-030/031/032) | Server-side, case-insensitive; matches content, tags, source label and platform. Debounced as you type |
| Detail + provenance (FR-022) | Full text, source type, platform, label, link, saved/updated times, ID |
| Delete (FR-050/051/052) | Asks for confirmation, then soft-deletes. An *Undo* toast restores it |
| Sync (FR-040/042/043) | Re-fetches every 5 s while the tab is visible, on window focus, and when back online, plus a manual Refresh button. The top bar shows *Synced / Syncing… / Offline / Can't reach Sherry · Retry* |
| Reset (FR-061) | Account menu → *Reset to demo data* (demo account only; the server refuses on real workspaces) |
| Captured chats | Memories from the browser extension show a *via extension* badge. The detail view has **Show captured chat** for the full transcript |
| Connect an AI assistant | Account menu → shows the API URL and API key for the Sherry MCP server. Memories saved through MCP show a *via MCP* badge |
| Responsive (WEB-002) | Two panes (list + detail) from 900 px up. Below that, a single column where the detail opens full-width with a back button |
| Keyboard (WEB-004) | `/` focuses search, `Esc` closes the detail, visible focus rings, labelled controls |

## HTTP API (for desktop and mobile)

Every endpoint is `POST /function/<name>` with a JSON body of named parameters. All of
them except `health` need `Authorization: Bearer <token>`. Each account's data lives in its
own graph root, so a user only ever sees their own workspace.

```bash
# register (once) - note the identity type is "username"; use the email as the value
curl -X POST localhost:8000/user/register -H 'Content-Type: application/json' -d '{
  "identities":[{"type":"username","value":"demo@sherry.app"}],
  "credential":{"type":"password","password":"sherry-demo-2026"}}'

# login -> data.token
curl -X POST localhost:8000/user/login -H 'Content-Type: application/json' -d '{
  "identity":{"type":"username","value":"demo@sherry.app"},
  "credential":{"type":"password","password":"sherry-demo-2026"}}'
```

| Function | Body | Returns (`data.result`) |
|---|---|---|
| `health` | `{}` | `{ok, service, time}` |
| `list_memories` | `{query?, cursor?, limit?}` | `{data: Memory[], nextCursor, total}` |
| `get_memory` | `{id}` | `Memory` or `null` |
| `create_memory` | `{content, source_platform, idempotency_key, tags?, source_type?, source_label?, source_url?, source_context?, captured_via?}` | `Memory` |
| `delete_memory` | `{id}` | `true` / `false` |
| `restore_memory` | `{id}` | `Memory` or `null` |
| `load_demo_data` | `{}` | Marks the workspace as a demo and adds the sample memories if missing. Idempotent. Returns the first page |
| `reset_demo` | `{}` | Wipes the workspace back to the sample memories. Demo workspaces only. Returns the first page |

### Capture endpoints (browser extension)

| Function | Body | Returns (`data.result`) |
|---|---|---|
| `capture_conversation` | `{platform, conversation_id, url?, title?, context?, captured_via?, messages: [{key, role, text, position, createdAt?}]}` | `{conversationId, received, added, updated, totalMessages, ignored, summaryStale}` |
| `summarize_conversation` | `{platform, conversation_id, force?}` | `{status: created\|updated\|unchanged\|ignored\|empty\|not_found, memory, engine: claude\|basic, note}` |
| `get_conversation` | `{id}` (the memory's `source.conversationId`) | `{id, platform, url, title, messageCount, messages[], summarizedAt, summaryEngine, summaryNote}` |

`platform` is one of `chatgpt | claude | gemini`, and `role` is `user | assistant`. Re-sending
the same message keys is a no-op. Each chat has one summary memory, marked
`captured_via: "extension"`, and it's rewritten when the chat changes. Deleting that memory
erases the chat's transcript and makes future captures of that chat return `ignored: true`.

**Summaries** use Claude through the official `anthropic` Python SDK
(`pip install anthropic` in the venv) when `ANTHROPIC_API_KEY` is set:

| Env var | Default | Meaning |
|---|---|---|
| `ANTHROPIC_API_KEY` | none | Enables Claude summaries. Without it, a basic extractive summary is used |
| `SHERRY_SUMMARY_MODEL` | `claude-opus-5` | Model for summaries |
| `SHERRY_SUMMARY_EFFORT` | `medium` | `low` / `medium` / `high` |
| `SHERRY_SUMMARIES` | on | Set to `off` to always use the basic summary |

`Memory` matches the contract in `REQUIREMENTS.md`, plus one additive field:
`{id, workspaceId, content, tags, source: {type, platform, label, url, capturedVia}, createdAt, updatedAt, deletedAt}`.
`captured_via` / `capturedVia` is `app` (default), `mcp`, `extension` or `import`.
Extension summaries also carry `source.conversationId`. The MCP server must
send `captured_via: "mcp"`.
`source_platform` must be one of `web | desktop | mobile | chatgpt | claude | gemini`, and
`idempotency_key` must be 16–128 characters.

Responses come wrapped in Jac's envelope: `{"ok": true, "data": {"result": ...}}`. Ignore the
extra `_jac_*` keys. A validation failure returns HTTP 200 with `data.error` set and no
`result`, so check for that.

### API key for the MCP server

The API key is the account's token from `/user/login`. It's also shown in the web app
under *Connect an AI assistant*. In this Jac server mode, the token is created at sign-up,
never expires, and isn't rotated. The MCP server sends it as
`Authorization: Bearer <SHERRY_API_KEY>` to `SHERRY_API_URL`.

The full data contract shared by every Sherry app (fields, allowed values, how the
desktop scraper maps to it) is in [data-schema-specification.md](../../data-schema-specification.md).

## Known limitations

- **Different stack from TECHNICAL.md.** This project uses Jac, not React/Vite + Supabase.
  The routes are `POST /function/<name>` instead of `/v1/memories`. The data shape is the
  same, but the backend and mobile owners need to agree to this before they build on it.
- Sync polls every 5 s; there is no push. That meets the "timed refresh" fallback in FR-042.
- Search and idempotency lookups scan the workspace linearly. That's fine for demo-sized
  data but should be indexed before real use.
- A server-side validation error shows as a generic "couldn't accept" message in the UI,
  because the Jac client receives `null`. The client validates first, so this is rare.
- The MCP API key is the account's login token, so it can't be revoked or scoped separately.
  Per-tool, revocable keys would need Jac cross-user grants and are left for later.
- Sign-in tokens are random 256-bit values stored in `main.db` (not signed JWTs). They never expire,
  and there is no limit on login attempts, so use strong passwords once Sherry is reachable online.
- Jac's built-in accounts store passwords as unsalted SHA-256 hashes (in `.jac/data/main.db`)
  and there is no password reset or change screen. Use a proper password hash (argon2/bcrypt)
  and a reset flow before real users sign up. For the demo, a password can be reset by writing
  `sha256(new password)` into that user's `password_hash` row while the server is running.
- In `.cl.jac` files, only `def:pub` functions and `glob:pub` values are exported. A plain
  `glob` imported from another module is undefined at runtime and blanks the page.
- Endpoints must be imported in `main.jac` to register. Client `sv import` alone did not
  register them with jac-client 0.3.25.
