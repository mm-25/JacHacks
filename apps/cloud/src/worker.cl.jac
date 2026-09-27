"""Sherry on Cloudflare Workers: the HTTP entry point.

Keeps the Jac server's API contract, so every existing client (web app,
browser extension, desktop sync, MCP connector) only needs a new address and
key:

    POST /function/<name>     JSON body in, envelope out:
        {"ok": true, "type": "response", "data": {"result": ...}}
        {"ok": true, "type": "response", "data": {"error": "message"}}   bad input (HTTP 200)
        {"ok": false, "type": "error", "error": {...}}                   401 / 404 / 500

Anything else is served from the web app's static files (env.ASSETS) when
they're configured.
"""

import from .util { text_of, now_iso, construct, is_plain_object }
import from .auth { authenticate, ensure_workspace, Principal }
import from .memories {
    list_memories,
    get_memory,
    create_memory,
    delete_memory,
    restore_memory,
    load_demo_data,
    reset_demo
}
import from .captures { capture_conversation, summarize_conversation, get_conversation }
import from .keys { create_api_key, list_api_keys, revoke_api_key }
import from .dashboard { dashboard_stats, list_conversations, delete_conversation }
import from .oauth {
    protected_resource_metadata,
    authorization_server_metadata,
    register_client,
    authorize_start,
    authorize_submit,
    token,
    revoke,
    mcp_caller,
    unauthorized_mcp
}
import from .mcp { handle_mcp }

glob CORS: dict = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, content-type",
    "Access-Control-Max-Age": "86400"
};


def _json(payload: any, status: int) -> any {
    headers: dict = {**CORS, "Content-Type": "application/json"};
    return construct("Response", [JSON.stringify(payload), {"status": status, "headers": headers}]);
}


def _result(result: any) -> any {
    return _json({"ok": True, "type": "response", "data": {"result": result}, "error": None}, 200);
}


def _rejected(message: str) -> any {
    return _json({"ok": True, "type": "response", "data": {"error": message}, "error": None}, 200);
}


def _failure(status: int, code: str, message: str) -> any {
    return _json({"ok": False, "type": "error", "data": None, "error": {"code": code, "message": message}}, status);
}


"""Run one endpoint. Returns [found, result]."""
async def _dispatch(name: str, env: any, who: Principal, ws: str, body: any) -> list {
    if name == "list_memories" {
        return [True, await list_memories(env, who, ws, body)];
    }
    if name == "get_memory" {
        return [True, await get_memory(env, who, ws, body)];
    }
    if name == "create_memory" {
        return [True, await create_memory(env, who, ws, body)];
    }
    if name == "delete_memory" {
        return [True, await delete_memory(env, who, ws, body)];
    }
    if name == "restore_memory" {
        return [True, await restore_memory(env, who, ws, body)];
    }
    if name == "load_demo_data" {
        return [True, await load_demo_data(env, who, ws, body)];
    }
    if name == "reset_demo" {
        return [True, await reset_demo(env, who, ws, body)];
    }
    if name == "capture_conversation" {
        return [True, await capture_conversation(env, who, ws, body)];
    }
    if name == "summarize_conversation" {
        return [True, await summarize_conversation(env, who, ws, body)];
    }
    if name == "get_conversation" {
        return [True, await get_conversation(env, who, ws, body)];
    }
    if name == "create_api_key" {
        return [True, await create_api_key(env, who, ws, body)];
    }
    if name == "list_api_keys" {
        return [True, await list_api_keys(env, who, ws, body)];
    }
    if name == "revoke_api_key" {
        return [True, await revoke_api_key(env, who, ws, body)];
    }
    if name == "dashboard_stats" {
        return [True, await dashboard_stats(env, who, ws, body)];
    }
    if name == "list_conversations" {
        return [True, await list_conversations(env, who, ws, body)];
    }
    if name == "delete_conversation" {
        return [True, await delete_conversation(env, who, ws, body)];
    }
    if name == "whoami" {
        row: any = await env.DB.prepare("SELECT is_demo FROM workspaces WHERE user_id = ?").bind(who.userId).first();
        return [True, {"userId": who.userId, "email": who.email, "workspaceId": ws, "isDemo": bool(row and row.is_demo), "via": who.via}];
    }
    return [False, None];
}


async def _function(request: any, env: any, name: str) -> any {
    if name == "health" {
        return _result({"ok": True, "service": "sherry-api", "time": now_iso()});
    }
    if request.method != "POST" {
        return _failure(405, "method_not_allowed", "Use POST.");
    }
    who = await authenticate(request, env);
    if who is None {
        return _failure(401, "unauthorized", "Sign in again, or check your Sherry API key.");
    }
    body: any = {};
    try {
        body = await request.json();
    } except Exception {
        body = {};
    }
    if not is_plain_object(body) {
        body = {};
    }
    try {
        ws = await ensure_workspace(env, who);
        outcome = await _dispatch(name, env, who, ws, body);
        if not outcome[0] {
            return _failure(404, "not_found", "Unknown function '" + name + "'.");
        }
        return _result(outcome[1]);
    } except Exception as err {
        e: any = err;
        if e.sherryReject {
            return _rejected(text_of(e.message));
        }
        console.error("sherry: " + name + " failed", e);
        return _failure(500, "internal", "Something went wrong on Sherry's side.");
    }
}


async def:pub handle(request: any, env: any, ctx: any) -> any {
    url: any = construct("URL", [request.url]);
    path = text_of(url.pathname);
    if request.method == "OPTIONS" {
        return construct("Response", [None, {"status": 204, "headers": CORS}]);
    }
    if path.startswith("/function/") {
        return await _function(request, env, path[len("/function/"):]);
    }
    # ---- MCP connector (claude.ai, ChatGPT, Gemini) and its OAuth ----
    if path == "/mcp" or path == "/mcp/" {
        caller = await mcp_caller(request, env);
        if caller is None {
            return unauthorized_mcp(request);
        }
        return await handle_mcp(request, env, caller);
    }
    if path.startswith("/.well-known/oauth-protected-resource") {
        return protected_resource_metadata(request);
    }
    if path.startswith("/.well-known/oauth-authorization-server") or path.startswith("/.well-known/openid-configuration") {
        return authorization_server_metadata(request);
    }
    if path == "/register" and request.method == "POST" {
        return await register_client(request, env);
    }
    if path == "/authorize" {
        if request.method == "POST" {
            return await authorize_submit(request, env);
        }
        return await authorize_start(request, env);
    }
    if path == "/token" and request.method == "POST" {
        return await token(request, env);
    }
    if path == "/revoke" and request.method == "POST" {
        return await revoke(request, env);
    }
    if env.ASSETS {
        return await env.ASSETS.fetch(request);
    }
    return _failure(404, "not_found", "Not found.");
}
