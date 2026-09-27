# Sherry browser extension (Jac)

A Chrome extension written in Jac. It captures **every message** of your
chats on chatgpt.com and claude.ai into your Sherry workspace, and keeps
**one summary memory per chat**, refreshed as the chat grows.

```
chatgpt.com / claude.ai page
  └─ content.js      reads the chat (src/lib/sites.cl.jac), sends new/changed messages
       └─ background.js   holds the API key, calls the Sherry API
            └─ Sherry (apps/web): capture_conversation, summarize_conversation
```

## Build and load

```bash
cd apps/extension
../../.venv/bin/jac run build.jac      # -> dist/
```

1. Open `chrome://extensions`, turn on **Developer mode**, click **Load unpacked**,
   and pick `apps/extension/dist`.
2. Start Sherry (`apps/web`). In the web app, open the account menu →
   **Connect an AI assistant** and copy the URL and API key.
3. Click the Sherry extension icon, paste both, then click **Save & test**. It
   should say *Connected ✓*.
4. Open (or reload) a chat on chatgpt.com or claude.ai. The popup shows
   *N messages on this page*.

After changing any `.cl.jac` file, rebuild and click the reload icon on the
extension card in `chrome://extensions`. Then reload the chat tabs.

## How capture works

- A `MutationObserver` notices page changes, and capture runs 1.2 s after the
  page settles. A 5 s safety scan also runs, which catches switching between chats.
- Nothing is sent while the assistant is still typing.
- Only new or changed messages are sent. The server stores each message under a
  stable key (the site's message id, or position + role), so re-sends never
  duplicate anything.
- After 20 s without new messages, Sherry is asked to summarize the chat. It skips
  the summary if the transcript hasn't changed. **Summarize this chat now** in the
  popup forces one.
- **Summaries:** the server uses Claude (`claude-opus-5`) when `ANTHROPIC_API_KEY`
  is set on the Sherry server. Otherwise it writes a basic summary (first question,
  latest question, latest answer).
- **Deleting a chat's summary** in Sherry erases that chat's captured transcript,
  and the extension stops capturing it. Undo re-enables capture.
- **Pausing:** the popup can pause all capture or turn it off per site.

## Testing with the new accounts

Use the new test Gmail accounts on chatgpt.com and claude.ai, not personal ones.
For each site:

1. Start a chat, send a couple of messages, and wait for the reply to finish.
2. Open the popup:
   - *This page* should show the right message count.
   - *Last activity* should say *Captured N new message(s)*.
3. Click **Summarize this chat now**. The summary appears in the Sherry web app
   with a *via extension* badge. **Show captured chat** in its detail view shows
   the transcript.
4. Edit or regenerate a message and check the stored transcript updates.
5. Switch to another chat in the sidebar. It should be captured as a separate
   conversation.

**If the count is 0 on a chat that has messages**, the site has changed its page
structure. Fix the selectors at the top of [src/lib/sites.cl.jac](src/lib/sites.cl.jac).
To find the new ones, right-click a message → Inspect. Only that file is site-specific.

## Files

| File | What it does |
|---|---|
| `src/lib/sites.cl.jac` | Site adapters: chat id, title, streaming check, messages. **All selectors live here.** |
| `src/content.cl.jac` | Watches the page, sends changes, schedules summaries, answers the popup |
| `src/background.cl.jac` | Routes messages; the only part that calls the API |
| `src/lib/api.cl.jac` | `POST /function/<name>` client with clear error messages |
| `src/lib/ext.cl.jac` | Typed wrappers for `chrome.*` (storage, messaging) and settings |
| `src/popup.cl.jac` + `static/popup.html` | Settings, status, summarize button |
| `static/manifest.json` | Manifest V3 |
| `build.jac` | `jac jac2js` each file, then bundle with Bun into `dist/` |

## Known limitations

- **The selectors in `sites.cl.jac` were not tested against the live sites.** They
  were written from these sites' known markup and tested against mock pages. Verify
  them with the test accounts first.
- claude.ai exposes no message ids. If an earlier message is deleted, later
  messages shift position, and some may be stored again under their new keys.
- Only chats with an id in the URL are captured. A brand-new ChatGPT chat is
  captured as soon as its URL changes to `/c/<id>`.
- A deployed (HTTPS) Sherry URL needs an extra host permission. The manifest lists
  it as optional, but the popup doesn't request it yet. `localhost` works out of the box.
- The API key is the Sherry account token. It can't be revoked separately (see `apps/web/README.md`).
