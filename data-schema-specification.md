# Sherry: Unified Data Schema

This is the one data contract for every Sherry app: web, browser extension, MCP
connector (claude.ai / ChatGPT / Gemini), desktop and mobile. If your app writes
to or reads from Sherry, it uses the records and values below, so every
platform's data lands in the same database in the same shape.

> Started from the desktop scraper's schema. Section 5 still describes that
> scraper's output, now corrected to match `scraper.jac`.

## 1. Where the data lives

There is **one database**: Cloudflare D1, behind the hosted Sherry API in
`apps/cloud` (a Cloudflare Worker written in Jac). It holds memories, captured
chats and API keys. **Accounts** (email + password) live in Supabase Auth; D1
only stores each account's Supabase user id.

Apps never open the database. They call the Sherry API over HTTP:

```
web app ─┐
extension ┤
MCP ──────┼──▶  Sherry API (apps/cloud, Cloudflare Worker)  ──▶  D1 database
desktop ──┤     POST /function/<name>
mobile ───┘                  ▲
                             └── logins checked against Supabase Auth
```

The old local Jac server (`apps/web` with `jac start`, data in
`apps/web/.jac/data/`) is no longer used. Nothing in it was copied to D1.

Each account has its own private workspace. An app only ever sees the data of
the account whose key it uses.

## 2. Records

```
Account ─▶ Workspace ─┬─▶ Memory            (what people search and see)
                      └─▶ Conversation ─▶ Message ...   (raw captured chats)
```

A captured chat is stored twice, at two levels:
- **Conversation + Messages:** every message, exactly as captured.
- **One summary Memory**, linked to the conversation and rewritten as the chat
  grows.

Single facts and notes are just Memories, with no conversation.

### Memory

This is the shape every endpoint returns (camelCase):

| Field | Type | Notes |
|---|---|---|
| `id` | string | Set by Sherry. |
| `workspaceId` | string | Set by Sherry. |
| `content` | string | 1–20,000 characters. |
| `tags` | string[] | Up to 20, each at most 40 characters, lowercase. |
| `source.type` | enum | `manual_note`, `conversation_excerpt`, `import` |
| `source.platform` | enum | Where the content came from (section 3). |
| `source.label` | string? | Short title. At most 120 characters. |
| `source.url` | string? | `http(s)://` link to the original, when there is one. |
| `source.context` | string? | Project or folder the chat belonged to (desktop logs). At most 200 characters. |
| `source.capturedVia` | enum | How it reached Sherry (section 3). |
| `source.conversationId` | string? | Set on chat summaries: the Conversation behind it. |
| `createdAt` / `updatedAt` | ISO-8601 UTC | Set by Sherry. |
| `deletedAt` | ISO-8601? | Set when deleted (deletes can be undone). |

### Conversation

| Field | Type | Notes |
|---|---|---|
| `id` | string | Set by Sherry. |
| `platform` | enum | `chatgpt`, `claude`, `gemini`, `codex`, `antigravity` |
| external id | string | **The app's own id for the chat** (the site's chat id, or the full session id from a log file), 1–200 characters. With `platform`, it identifies the chat. |
| `title` | string | At most 200 characters. |
| `url` | string | Empty for local logs. |
| `context` | string? | Project or folder. |
| `capturedVia` | enum | `extension` or `desktop` |
| `messages` | Message[] | Oldest first. |

### Message

| Field | Type | Notes |
|---|---|---|
| `key` | string | **Stable id from the capturing app**, at most 200 characters. Re-sending the same key updates the message instead of adding a new one. |
| `role` | enum | `user` or `assistant` |
| `text` | string | At most 100,000 characters. |
| `position` | int | Order within the chat. |
| `sentAt` | ISO-8601 UTC? | When the message was originally sent (from the log or site). Empty if unknown. Sherry never invents it. |
| `capturedAt` | ISO-8601 UTC | When Sherry first stored it. |

## 3. Allowed values

**`source.platform`**: where the content came from.

| Value | Meaning |
|---|---|
| `chatgpt`, `claude`, `gemini` | Those assistants (websites, apps, or MCP) |
| `codex`, `antigravity` | Those coding agents (desktop logs) |
| `web`, `desktop`, `mobile` | Typed directly into a Sherry app |

Claude Code sessions use `claude`. The `desktop` capture channel tells them
apart from claude.ai chats.

**`source.capturedVia`**: how it reached Sherry.

| Value | Who uses it |
|---|---|
| `app` | Typed into a Sherry app (web, desktop, mobile) |
| `mcp` | Saved by an assistant through the Sherry connector |
| `extension` | Browser extension capturing a web chat |
| `desktop` | Desktop app capturing local AI tool logs |
| `import` | Bulk import |

Anything else is rejected with a clear error.

## 4. Writing and reading (for app developers)

- **Base URL:** `https://sherry.sherry-cloud.workers.dev`. This is the hosted Sherry
  (Cloudflare Worker + D1, in `apps/cloud`); it's always on.
  `http://localhost:8000` is only the old local Jac server.
- **Requests:** every call is `POST <base>/function/<name>` with a JSON body.
- **Auth:** add `Authorization: Bearer <API key>` to every call.
  - **Apps without a login screen** (extension, desktop sync, scripts): use a Sherry API
    key (`shr_…`). Create it in Sherry web → account menu → **Connect apps and
    assistants** → **Create key**. It's shown once and can be revoked there.
  - **Apps with a login screen** (mobile): sign the user in with Supabase Auth
    (email + password, same project as the web app) and send the Supabase access token.
    Refresh it before it expires, which is about an hour.
- **Response:** `{"ok": true, "data": {"result": ...}}`.
  - Also available: `whoami`, and (web sessions only) `create_api_key`, `list_api_keys`
    and `revoke_api_key`.
  - A rejected input comes back as `{"data": {"error": "message"}}`, with HTTP 200.
  - A bad key comes back as HTTP 401.

| Endpoint | Body | Returns |
|---|---|---|
| `create_memory` | `content`, `source_platform`, `idempotency_key` (16–128 chars, unique per memory; retries with the same key never duplicate), optional `tags`, `source_type`, `source_label`, `source_url`, `source_context`, `captured_via` | Memory |
| `list_memories` | `query` (searches content, tags, label, platform, project), `cursor`, `limit` (max 100) | `{data: Memory[], nextCursor, total}` |
| `get_memory` / `delete_memory` / `restore_memory` | `id` | Memory / bool / Memory |
| `capture_conversation` | `platform`, `conversation_id` (your external id), `messages` (max 300 per call: `{key, role, text, position, createdAt?}`), optional `title`, `url`, `context`, `captured_via` (`extension` or `desktop`) | `{conversationId, added, updated, totalMessages, ignored, summaryStale}` |
| `summarize_conversation` | `platform`, `conversation_id`, optional `force` | `{status, memory, engine, note}` |
| `get_conversation` | `id` (Sherry's `conversationId`) | Conversation with messages |

### Rules every capturer follows

1. **Send whole chats repeatedly.** Keys make it idempotent: unchanged messages
   are ignored, so it's safe to resend every few seconds.
2. **Call `summarize_conversation` when a chat goes quiet**, for example 20
   seconds after the last new message. It does nothing if nothing changed.
3. **Respect `ignored: true`.** If `capture_conversation` returns it, the user
   deleted that chat's summary in Sherry. Its messages have been erased, and
   your app should stop sending that chat.
4. **Never send a timestamp you don't have.** Leave `createdAt` empty.

## 5. Desktop scraper → Sherry

`scraper.jac` reads local session logs and emits one row per message:

```json
{
  "id": "codex-rollout-2026-09-26T21-46-15-a1-42",
  "content": "Can you make it responsive?",
  "createdAt": "2026-09-26T21:46:15Z",
  "source": { "type": "conversation_excerpt", "platform": "codex", "label": "User" }
}
```

What `scraper.jac` produces today:

| Platform | Logs read | `id` | `source.label` |
|---|---|---|---|
| `antigravity` | `~/.gemini/antigravity/brain/<conv>/…/transcript.jsonl` | `{step_index}-{conv_id}-user` or `-ai` | `User` / `Antigravity` |
| `claude` | `~/.claude/projects/<project>/<session>.jsonl` (Claude Code) | `claude-{session}-{line}` | `User` / `Claude` |
| `codex` | `~/.codex/sessions/YYYY/MM/DD/<file>.jsonl` | `codex-{session[:30]}-{line}` | `User` / `Codex` |

To store rows in Sherry, group them by session and call `capture_conversation`
once per session with `captured_via: "desktop"`:

| Sherry field | From the scraper |
|---|---|
| `platform` | `source.platform` |
| `conversation_id` | Session id: the conv folder (Antigravity), the file name (Claude, Codex) |
| `context` | Project folder name (Claude); empty otherwise |
| `title` | Project name or first user message, shortened |
| message `key` | Row `id` |
| message `role` | `user` if `source.label` is `User`, otherwise `assistant` |
| message `text` | `content` |
| message `position` | Line or step index |
| message `createdAt` | `createdAt` |

Then call `summarize_conversation` when the session has been quiet for a bit.

**Ready-made: [`sherry_sync.jac`](sherry_sync.jac)** does all of this: grouping,
roles, positions, sending only what changed, summaries after 20 seconds of quiet,
and stopping when a chat is deleted in Sherry. It never crashes the scraper when
Sherry is offline. Use it either way:

```bash
# No code changes: sync the JSON file the scraper already writes (newest 200 rows)
SHERRY_URL=<sherry address> SHERRY_API_KEY=<your key> jac run sherry_sync.jac
```

```jac
# Or inside scraper.jac, to sync every row (not just the newest 200):
import from sherry_sync { SherrySync }
sync = SherrySync.from_env();   # before the while loop
sync.push(all_mems);            # in the loop, before all_mems is sorted/capped
```

Optional: `SHERRY_SYNC_PLATFORMS` (for example `claude,codex`) and
`SHERRY_SYNC_CONTEXTS` (only these projects). If the scraper adds `"session"` and
`"context"` keys to its rows (the session id and project folder), the helper uses
them instead of parsing ids, and project filtering starts working.

**Known scraper issues to fix before syncing:**
- **Codex ids collide.** Codex session ids are cut to 30 characters, which is
  mostly the start time in the file name. Two sessions started in the same
  second collide, so use the full file name.
- **Claude replies are cut short.** Only the first text block of each Claude
  reply is kept, so multi-part replies lose text.
- **Privacy.** The scraper reads **every** local session, including anything
  pasted into it. Let the user choose which projects to sync before sending
  anything to Sherry.
