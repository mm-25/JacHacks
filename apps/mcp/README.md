# Sherry MCP server (Jac)

This server lets **claude.ai** and **ChatGPT** save to and search your Sherry
memory. The assistant decides when to call the tools; you can also ask it
directly ("save this chat to Sherry", "what did I decide about X?").

```
claude.ai / ChatGPT ──HTTPS + OAuth──▶ Sherry MCP server (this, :8100) ──▶ Sherry API (apps/web, :8000)
```

It is written in Jac on top of the official MCP Python SDK (`mcp` 2.x). It uses
the Streamable HTTP transport and OAuth 2.1 sign-in (dynamic client registration
plus PKCE). Users sign in with their **Sherry email and password**, and every
tool call runs against the Sherry API as that user.

## Tools

| Tool | What it does | Marked as |
|---|---|---|
| `save_memory(content, title?, tags?, source_url?)` | Saves a fact, decision or chat summary, tagged with the calling assistant (`claude` / `chatgpt`) and `capturedVia: mcp`. Saving the same content twice is harmless | write |
| `search_memories(query, limit?)` | Text search over content, tags and sources | read-only |
| `list_recent_memories(limit?)` | Newest memories | read-only |
| `get_memory(memory_id)` | One memory with its provenance | read-only |
| `delete_memory(memory_id)` | Deletes a memory everywhere | destructive |

The server also sends instructions telling the model when to use each tool. ChatGPT
asks the user to confirm every tool that isn't marked read-only.

## Run locally

```bash
# 1. Sherry must be running (apps/web): http://localhost:8000
# 2. From the repo root, once:
.venv/bin/pip install -r apps/requirements.txt
# 3. Start the MCP server:
cd apps/mcp
../../.venv/bin/jac run main.jac          # http://127.0.0.1:8100/mcp
```

| Env var | Default | Meaning |
|---|---|---|
| `SHERRY_MCP_PUBLIC_URL` | `http://localhost:8100` | The **public** base URL (the tunnel's URL, below) |
| `SHERRY_API_URL` | `http://localhost:8000` | Where the Sherry API is |
| `SHERRY_MCP_HOST` / `SHERRY_MCP_PORT` | `127.0.0.1` / `8100` | Listen address |
| `SHERRY_MCP_DATA` | `./.data/oauth.json` | Connected clients and hashed tokens (mode 600) |

## Connect claude.ai or ChatGPT

Both connect from their own servers, so they need a **public HTTPS URL**, not
`localhost`. For the hackathon, use a tunnel to your laptop. Only the MCP server
has to be public; Sherry itself stays on localhost.

**Shortcut:** with `cloudflared` saved at `apps/mcp/.bin/cloudflared` (ignored by git),
run `./connect.sh` from `apps/mcp`. It opens the tunnel, starts the server with the
tunnel URL and prints the connector URL; Ctrl+C stops both. Then go to step 3.

Or do it by hand:

1. Install a tunnel, for example [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/),
   and run:
   ```bash
   cloudflared tunnel --url http://localhost:8100
   ```
   It prints a URL like `https://random-words.trycloudflare.com`.
2. Restart the MCP server with that URL:
   ```bash
   SHERRY_MCP_PUBLIC_URL=https://random-words.trycloudflare.com ../../.venv/bin/jac run main.jac
   ```
3. Add the connector, using `https://random-words.trycloudflare.com/mcp` as the URL:
   - **claude.ai:** Customize → Connectors → **+** → Add custom connector. Paste
     the URL and leave the OAuth fields empty. Free plans allow 1 custom connector.
   - **ChatGPT:** turn on Developer mode, create an app for the remote MCP server,
     paste the URL and choose **OAuth**. Developer mode needs Plus, Pro, Business,
     Enterprise or Education.
     See OpenAI's [developer mode guide](https://developers.openai.com/api/docs/guides/developer-mode).
     Add it from **Settings → Apps**, then click **Connect**; the **+** on the Plugins page
     opens a plugin-builder chat instead.
   - **Gemini:** on gemini.google.com (desktop), open **Settings → Connected Apps**, and under
     **Custom apps** choose **Add a custom app**. Paste the URL, leave **Advanced features**
     empty (Gemini registers itself), then **Next**. Google currently limits custom apps to
     personal Google accounts, 18+, in the US, with the language set to English and Keep
     Activity on. Gemini asks you to confirm every write. Use `@Sherry` in a prompt to point
     Gemini at it. See Google's [custom apps help](https://support.google.com/gemini/answer/17209137).
4. The assistant opens the **Connect your memory** page. Sign in with your Sherry
   email and password and click **Allow access**.
5. Try it: "Save a summary of this chat to Sherry." It shows up in the Sherry web
   app with a *via MCP* badge. Then, in a new chat or the other assistant, ask
   "What do you know from Sherry about …?"

Quick-tunnel URLs change every time `cloudflared` restarts. When that happens,
restart the MCP server with the new URL and reconnect the connector. For the demo,
a named Cloudflare tunnel or an ngrok static domain keeps the URL fixed.

## Known limitations

- **Tokens:** the OAuth tokens map to the Sherry account token, so changing your
  Sherry password doesn't disconnect existing connectors. Disconnect them from the
  assistant's settings instead; that revokes the token.
- **Sign-ins stored in memory:** pending sign-ins and authorization codes are lost on
  restart. Just try connecting again.
- **Platform detection:** the calling assistant is detected from the MCP client's
  self-reported name. Unknown clients are recorded as `claude`; pass `assistant` to
  `save_memory` to override.
- **Not a production auth server:** there is no rate limiting on the sign-in page and
  no account-recovery flow.
