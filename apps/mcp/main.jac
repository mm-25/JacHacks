"""Sherry MCP server - lets claude.ai, ChatGPT and other MCP clients save and
search the user's Sherry memories.

Run (Sherry web/API must be running, default http://localhost:8000):

    cd apps/mcp
    SHERRY_MCP_PUBLIC_URL=https://<public-host> ../../.venv/bin/jac run main.jac

Remote connectors (claude.ai, ChatGPT) need a public HTTPS URL - see README.

Environment:
    SHERRY_API_URL          Sherry Jac API (default http://localhost:8000)
    SHERRY_MCP_PUBLIC_URL   Public base URL of this server (default http://localhost:8100)
    SHERRY_MCP_HOST / PORT  Listen address (default 127.0.0.1:8100)
    SHERRY_MCP_DATA         OAuth state file (default ./.data/oauth.json)
"""

import os;
import html;
import hashlib;
import from urllib.parse { urlparse }
import from pathlib { Path }
import from starlette.requests { Request }
import from starlette.responses { Response, HTMLResponse, RedirectResponse, JSONResponse }
import from mcp.server.mcpserver { MCPServer, Context }
import from mcp.server.mcpserver.exceptions { ToolError }
import from mcp.server.auth.settings { AuthSettings, ClientRegistrationOptions, RevocationOptions }
import from mcp.server.auth.middleware.auth_context { get_access_token }
import from mcp.server.transport_security { TransportSecuritySettings }
import from mcp.types { ToolAnnotations }
import from oauth { SherryOAuthProvider, SCOPE }
import sherry_api;

glob PUBLIC_URL: str = os.environ.get("SHERRY_MCP_PUBLIC_URL", "http://localhost:8100").rstrip("/");
glob HOST: str = os.environ.get("SHERRY_MCP_HOST", "127.0.0.1");
glob PORT: int = int(os.environ.get("SHERRY_MCP_PORT", "8100"));
glob DATA_FILE: str = os.environ.get(
    "SHERRY_MCP_DATA", str(Path(str(__file__)).resolve().parent / ".data" / "oauth.json")
);
glob RESOURCE_URL: str = PUBLIC_URL + "/mcp";
glob PLATFORMS: list[str] = ["claude", "chatgpt", "gemini"];

glob INSTRUCTIONS: str = (
    "Sherry is the user's personal memory layer, shared across their AI assistants "
    + "and devices. Use it to keep continuity:\n"
    + "- When the user asks you to remember, save or note something - or to save this "
    + "chat - call save_memory. For a chat, write a concise summary yourself: decisions, "
    + "facts and preferences the user stated, and next steps. Keep names, numbers and dates.\n"
    + "- Before answering questions about the user's past decisions, preferences, projects "
    + "or earlier conversations (including ones in other assistants), call search_memories.\n"
    + "- Mention the source (platform and date) when you rely on a memory.\n"
    + "- Only delete a memory when the user explicitly asks."
);

glob provider: SherryOAuthProvider = SherryOAuthProvider(
    public_url=PUBLIC_URL, resource_url=RESOURCE_URL, data_file=DATA_FILE
);

glob server: MCPServer = MCPServer(
    name="sherry",
    title="Sherry memory",
    description="Save and search your Sherry memories from any AI assistant.",
    instructions=INSTRUCTIONS,
    website_url=os.environ.get("SHERRY_API_URL", "http://localhost:8000"),
    version="0.1.0",
    auth_server_provider=provider,
    auth=AuthSettings(
        issuer_url=PUBLIC_URL,
        resource_server_url=RESOURCE_URL,
        validate_token_resource=True,
        required_scopes=[SCOPE],
        client_registration_options=ClientRegistrationOptions(
            enabled=True, valid_scopes=[SCOPE], default_scopes=[SCOPE]
        ),
        revocation_options=RevocationOptions(enabled=True)
    )
);


# ---------- helpers ----------

def _sherry_token -> str {
    access = get_access_token();
    if access is None {
        raise ToolError("Not signed in to Sherry.");
    }
    token = provider.sherry_token_for(access.token);
    if not token {
        raise ToolError("Your Sherry connection expired. Reconnect Sherry in your assistant's settings.");
    }
    return token;
}


"""Which assistant is calling, from the MCP client's self-reported name."""
def _client_platform(ctx: Context | None) -> tuple[str, str] {
    name = "";
    try {
        params: any = ctx.session.client_params if ctx else None;
        name = str(params.client_info.name) if params and params.client_info else "";
    } except Exception {
        name = "";
    }
    lowered = name.lower();
    if "claude" in lowered or "anthropic" in lowered {
        return ("claude", name);
    }
    if "openai" in lowered or "chatgpt" in lowered {
        return ("chatgpt", name);
    }
    if "gemini" in lowered or "google" in lowered {
        return ("gemini", name);
    }
    return ("", name);
}


async def _call(name: str, body: dict) -> any {
    try {
        return sherry_api.clean(await sherry_api.call(_sherry_token(), name, body));
    } except sherry_api.SherryError as err {
        raise ToolError(str(err));
    }
}


def _brief(m: dict) -> dict {
    source: dict = (m.get("source") or {}) as dict;
    return {
        "id": m.get("id"),
        "content": m.get("content"),
        "tags": m.get("tags") or [],
        "source": {
            "platform": source.get("platform"),
            "type": source.get("type"),
            "label": source.get("label"),
            "url": source.get("url"),
            "capturedVia": source.get("capturedVia")
        },
        "createdAt": m.get("createdAt"),
        "updatedAt": m.get("updatedAt")
    };
}


# ---------- tools ----------

"""Save something to the user's Sherry memory so they (and their other AI
assistants and devices) can find it later. Use it when the user asks you to
remember or save something, or to save/summarize the current chat. `content`
should be self-contained: write the fact, decision or summary so it makes
sense without this conversation. Saving the same content twice is harmless."""
@server.tool(
    title="Save to Sherry",
    annotations=ToolAnnotations(
        readOnlyHint=False, destructiveHint=False, idempotentHint=True, openWorldHint=False
    )
)
async def save_memory(
    content: str,
    title: str = "",
    tags: list[str] | None = None,
    source_url: str = "",
    assistant: str = "",
    ctx: Context | None = None
) -> dict {
    body = content.strip();
    if not body {
        raise ToolError("content is empty.");
    }
    (detected, client_name) = _client_platform(ctx);
    platform = assistant.strip().lower() if assistant.strip().lower() in PLATFORMS else detected;
    if not platform {
        platform = "claude";
    }
    label = title.strip()[:120] or f"Saved from {client_name or platform} chat"[:120];
    # Same content from the same assistant -> same key, so retries never duplicate.
    key = "mcp-" + hashlib.sha256(f"{platform}\x1f{body}".encode("utf-8")).hexdigest()[:48];
    memory: dict = await _call(
        "create_memory",
        {
            "content": body,
            "source_platform": platform,
            "idempotency_key": key,
            "tags": tags or [],
            "source_type": "conversation_excerpt",
            "source_label": label,
            "source_url": source_url.strip() if source_url.strip().startswith("http") else "",
            "captured_via": "mcp"
        }
    ) as dict;
    return {"saved": True, "memory": _brief(memory)};
}


"""Search the user's Sherry memories (case-insensitive text search over
content, tags and source names), newest first. Use it before answering
questions about the user's past decisions, preferences, projects or earlier
conversations - including ones held in other AI assistants."""
@server.tool(
    title="Search Sherry",
    annotations=ToolAnnotations(readOnlyHint=True, openWorldHint=False)
)
async def search_memories(query: str, limit: int = 10) -> dict {
    page: dict = await _call(
        "list_memories", {"query": query, "cursor": "", "limit": max(1, min(limit, 25))}
    ) as dict;
    items = [_brief(m as dict) for m in (page.get("data") or [])];
    return {"query": query, "total": page.get("total", len(items)), "memories": items};
}


"""List the user's most recent Sherry memories, newest first."""
@server.tool(
    title="Recent Sherry memories",
    annotations=ToolAnnotations(readOnlyHint=True, openWorldHint=False)
)
async def list_recent_memories(limit: int = 10) -> dict {
    page: dict = await _call(
        "list_memories", {"query": "", "cursor": "", "limit": max(1, min(limit, 25))}
    ) as dict;
    items = [_brief(m as dict) for m in (page.get("data") or [])];
    return {"total": page.get("total", len(items)), "memories": items};
}


"""Get one Sherry memory by id, with its full text and provenance."""
@server.tool(
    title="Open a Sherry memory",
    annotations=ToolAnnotations(readOnlyHint=True, openWorldHint=False)
)
async def get_memory(memory_id: str) -> dict {
    memory = await _call("get_memory", {"id": memory_id});
    if not memory {
        raise ToolError("No memory with that id (it may have been deleted).");
    }
    return {"memory": _brief(memory as dict)};
}


"""Delete a Sherry memory by id. It disappears from all the user's devices.
Only call this when the user explicitly asks to delete that memory."""
@server.tool(
    title="Delete a Sherry memory",
    annotations=ToolAnnotations(readOnlyHint=False, destructiveHint=True, openWorldHint=False)
)
async def delete_memory(memory_id: str) -> dict {
    deleted = await _call("delete_memory", {"id": memory_id});
    if not deleted {
        raise ToolError("No memory with that id (it may already be deleted).");
    }
    return {"deleted": True, "id": memory_id};
}


# ---------- sign-in page (OAuth authorize step) ----------

glob PAGE_CSS: str = """
@import url("https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600&display=swap");
:root{--canvas:#fff;--canvas-soft-2:#f5f5f5;--hairline:#ebebeb;--hairline-strong:#a1a1a1;--ink:#171717;--body:#4d4d4d;--mute:#888;--primary:#171717;--primary-hover:#383838;--on-primary:#fff;--danger:#ee0000;--danger-deep:#c50000;--danger-soft:#f7d4d6;--focus:#0070f3;--ring:0 0 0 1px rgba(0,0,0,.08);--mesh-opacity:.55;color-scheme:light}
@media (prefers-color-scheme:dark){:root{--canvas:#0a0a0a;--canvas-soft-2:#1a1a1a;--hairline:#2e2e2e;--hairline-strong:#5c5c5c;--ink:#ededed;--body:#a1a1a1;--mute:#7a7a7a;--primary:#ededed;--primary-hover:#cfcfcf;--on-primary:#0a0a0a;--danger:#ff6166;--danger-deep:#ff8a8e;--danger-soft:#3c1618;--focus:#52a8ff;--ring:0 0 0 1px rgba(255,255,255,.1);--mesh-opacity:.38;color-scheme:dark}}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:grid;place-items:center;padding:64px 16px;background:var(--canvas);color:var(--ink);font:15px/1.55 "Geist","Inter",ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;-webkit-font-smoothing:antialiased;position:relative;isolation:isolate;overflow-x:hidden}
body::before{content:"";position:absolute;z-index:-1;left:50%;top:-12%;width:min(1100px,150vw);height:70%;transform:translateX(-50%);background:radial-gradient(38% 55% at 18% 45%,#007cf0,transparent 70%),radial-gradient(30% 50% at 34% 70%,#00dfd8,transparent 70%),radial-gradient(34% 55% at 52% 35%,#7928ca,transparent 70%),radial-gradient(30% 50% at 66% 62%,#ff0080,transparent 70%),radial-gradient(32% 55% at 80% 40%,#ff4d4d,transparent 70%),radial-gradient(28% 45% at 90% 68%,#f9cb28,transparent 70%);filter:blur(60px) saturate(1.1);opacity:var(--mesh-opacity);pointer-events:none}
body::after{content:"";position:absolute;inset:0;z-index:-1;background:linear-gradient(to bottom,transparent 0%,transparent 35%,var(--canvas) 78%);pointer-events:none}
.card{width:100%;max-width:420px;background:var(--canvas);border-radius:12px;padding:32px;box-shadow:0 1px 1px rgba(0,0,0,.02),0 8px 16px -4px rgba(0,0,0,.04),0 24px 32px -8px rgba(0,0,0,.06),var(--ring)}
.brand{display:flex;align-items:center;gap:10px;margin-bottom:24px}
.logo{width:32px;height:32px;border-radius:6px;background:var(--primary);color:var(--on-primary);display:grid;place-items:center;font-weight:600;font-size:17px;letter-spacing:-.6px}
.wordmark{font-size:20px;line-height:28px;font-weight:600;letter-spacing:-.6px}
h1{font-size:32px;line-height:40px;font-weight:600;letter-spacing:-1.28px;margin:0 0 12px}
p{margin:0 0 16px;color:var(--body)}
.who{background:var(--canvas-soft-2);border-radius:8px;padding:12px 14px;margin-bottom:16px;font-size:14px;line-height:20px;color:var(--body)}.who b{color:var(--ink);font-weight:500}
label{display:block;font-size:13px;font-weight:500;color:var(--body);margin:12px 0 6px}
input{width:100%;height:40px;padding:0 12px;border-radius:6px;border:1px solid var(--hairline);background:var(--canvas);color:var(--ink);font:inherit;font-size:14px}
input:hover{border-color:var(--hairline-strong)}
input:focus{outline:none;border-color:var(--hairline-strong);box-shadow:0 0 0 3px color-mix(in srgb,var(--focus) 18%,transparent)}
.row{display:flex;gap:12px;margin-top:24px}
button{flex:1;min-height:44px;border-radius:100px;font-family:inherit;font-size:16px;line-height:24px;font-weight:500;cursor:pointer;border:none;background:var(--canvas);color:var(--ink);box-shadow:var(--ring)}
button:hover{background:var(--canvas-soft-2)}
button.primary{background:var(--primary);color:var(--on-primary);box-shadow:none}button.primary:hover{background:var(--primary-hover)}
button:focus-visible{outline:2px solid var(--focus);outline-offset:2px}
.error{background:var(--danger-soft);color:var(--danger-deep);border-radius:6px;padding:10px 12px;font-size:14px;line-height:20px;margin-bottom:8px}
.small{font-size:12px;line-height:16px;color:var(--mute);margin-top:16px;margin-bottom:0}
""";


def _page(body: str, status: int = 200) -> HTMLResponse {
    return HTMLResponse(
        "<!doctype html><html lang='en'><head><meta charset='utf-8'>"
        + "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        + "<title>Connect Sherry</title><style>" + PAGE_CSS + "</style></head><body>"
        + "<main class='card'><div class='brand'><div class='logo' aria-hidden='true'>S</div>"
        + "<span class='wordmark'>Sherry</span></div>" + body + "</main></body></html>",
        status_code=status
    );
}


def _login_form(request_id: str, pending: dict, error: str, email: str) -> HTMLResponse {
    params: dict = pending["params"] as dict;
    client = html.escape(provider.client_label(str(pending["client_id"])));
    redirect_host = html.escape(str(urlparse(str(params["redirect_uri"])).hostname or ""));
    error_html = f"<div class='error' role='alert'>{html.escape(error)}</div>" if error else "";
    return _page(
        f"<h1>Connect your memory.</h1>"
        + f"<div class='who'><b>{client}</b> wants to save and search your Sherry memories."
        + f"<br>After signing in you'll be sent back to <b>{redirect_host}</b>.</div>"
        + error_html
        + "<form method='post' action='/sherry/login'>"
        + f"<input type='hidden' name='request' value='{html.escape(request_id)}'>"
        + "<label for='email'>Sherry email</label>"
        + f"<input id='email' name='email' type='email' autocomplete='email' required value='{html.escape(email)}'>"
        + "<label for='password'>Password</label>"
        + "<input id='password' name='password' type='password' autocomplete='current-password' required>"
        + "<div class='row'><button type='submit' name='action' value='deny' formnovalidate>Cancel</button>"
        + "<button class='primary' type='submit' name='action' value='allow'>Allow access</button></div>"
        + "</form><p class='small'>You can disconnect at any time from your assistant's connector settings. "
        + "Everything saved shows up in Sherry with its source.</p>"
    );
}


def _expired -> HTMLResponse {
    return _page(
        "<h1>This sign-in link expired.</h1><p>Go back to your assistant and start connecting Sherry again.</p>",
        400
    );
}


@server.custom_route("/sherry/login", methods=["GET"])
async def login_page(request: Request) -> Response {
    request_id = str(request.query_params.get("request", ""));
    pending = provider.pending_request(request_id);
    if pending is None {
        return _expired();
    }
    return _login_form(request_id, pending, "", "");
}


@server.custom_route("/sherry/login", methods=["POST"])
async def login_submit(request: Request) -> Response {
    form: any = await request.form();
    request_id = str(form.get("request", ""));
    pending = provider.pending_request(request_id);
    if pending is None {
        return _expired();
    }
    if str(form.get("action", "")) == "deny" {
        return RedirectResponse(provider.deny_sign_in(request_id), status_code=302);
    }
    email = str(form.get("email", "")).strip().lower();
    password = str(form.get("password", ""));
    token: str | None = None;
    try {
        token = await sherry_api.login(email, password);
    } except Exception {
        return _login_form(request_id, pending, "Can't reach Sherry right now. Try again in a moment.", email);
    }
    if not token {
        return _login_form(request_id, pending, "That email and password don't match a Sherry account.", email);
    }
    return RedirectResponse(provider.complete_sign_in(request_id, email, token), status_code=302);
}


@server.custom_route("/health", methods=["GET"])
async def health(request: Request) -> Response {
    return JSONResponse({"ok": True, "service": "sherry-mcp", "resource": RESOURCE_URL});
}


with entry:__main__ {
    public_host = str(urlparse(PUBLIC_URL).netloc);
    print(f"Sherry MCP server on http://{HOST}:{PORT}/mcp (public URL: {RESOURCE_URL})");
    server.run(
        "streamable-http",
        host=HOST,
        port=PORT,
        transport_security=TransportSecuritySettings(
            enable_dns_rebinding_protection=True,
            allowed_hosts=[public_host, f"127.0.0.1:{PORT}", f"localhost:{PORT}"],
            allowed_origins=[
                PUBLIC_URL,
                "https://claude.ai",
                "https://chatgpt.com",
                f"http://127.0.0.1:{PORT}",
                f"http://localhost:{PORT}"
            ]
        )
    );
}
