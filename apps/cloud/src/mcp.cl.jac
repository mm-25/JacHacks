"""The Sherry MCP connector on the Worker (port of apps/mcp/main.jac).

Streamable HTTP at POST /mcp, stateless (no Mcp-Session-Id): every request is
authorized by its OAuth bearer token (see oauth.cl.jac) and answered with one
JSON response. Speaks the initialize-handshake protocol revisions up to
2025-11-25. A 2026-07-28 client first probes `server/discover`; it gets
"method not found" and falls back to the handshake, as the MCP SDK clients do.

Tools: save_memory, search_memories, list_recent_memories, get_memory,
delete_memory - same names, descriptions and hints as before.
"""

import from .util { sha256_hex, text_of, int_of, construct, is_plain_object }
import from .auth { Principal, ensure_workspace }
import from .oauth { McpCaller }
import from .memories { list_memories, get_memory, create_memory, delete_memory }

glob SUPPORTED_VERSIONS: list[str] = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"];
glob LATEST_VERSION: str = "2025-11-25";
glob PLATFORMS: list[str] = ["claude", "chatgpt", "gemini"];

glob INSTRUCTIONS: str = (
    "Sherry is the user's personal memory, shared across their AI assistants and "
    + "devices. Use it on your own initiative - the user should never have to ask:\n"
    + "- At the start of every conversation, call search_memories with a few keywords "
    + "from the user's first message (or list_recent_memories when there is no clear "
    + "topic), and use what you find to answer with their context. Search again whenever "
    + "they refer to past work, decisions, preferences, people or projects. Don't narrate "
    + "the lookup; mention the source (platform and date) when you rely on a memory.\n"
    + "- When the user states something worth keeping - a decision, a preference, a fact "
    + "about themselves or their work, a plan or a deadline - call save_memory with one "
    + "self-contained sentence, without asking. Never save secrets (passwords, keys, "
    + "financial or health details) or small talk, nothing the user asks you not to "
    + "keep, and nothing you already found in Sherry.\n"
    + "- Only delete a memory when the user explicitly asks."
);

glob TOOLS: list[dict] = [
    {
        "name": "save_memory",
        "title": "Save to Sherry",
        "description": "Save something to the user's Sherry memory so they (and their other AI assistants and devices) can find it later. Call it on your own whenever the user states a decision, preference, fact about themselves or their work, plan or deadline worth keeping - and when they ask you to remember something or to save/summarize the chat. `content` should be one self-contained statement that makes sense without this conversation. Never save secrets. Saving the same content twice is harmless.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "content": {"type": "string", "description": "The fact, decision or chat summary to save."},
                "title": {"type": "string", "description": "Optional short title."},
                "tags": {"type": "array", "items": {"type": "string"}, "description": "Optional topic tags."},
                "source_url": {"type": "string", "description": "Optional link to the original chat."},
                "assistant": {"type": "string", "description": "Optional: claude, chatgpt or gemini, if Sherry can't tell which assistant is calling."}
            },
            "required": ["content"]
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": False, "idempotentHint": True, "openWorldHint": False}
    },
    {
        "name": "search_memories",
        "title": "Search Sherry",
        "description": "Search the user's Sherry memories (case-insensitive text search over content, tags, source names and projects), newest first. Call it on your own at the start of every conversation with keywords from the user's message, and whenever they mention past decisions, preferences, projects, people or earlier conversations - including ones held in other AI assistants.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Words to look for."},
                "limit": {"type": "integer", "minimum": 1, "maximum": 25, "default": 10}
            },
            "required": ["query"]
        },
        "annotations": {"readOnlyHint": True, "openWorldHint": False}
    },
    {
        "name": "list_recent_memories",
        "title": "Recent Sherry memories",
        "description": "List the user's most recent Sherry memories, newest first.",
        "inputSchema": {
            "type": "object",
            "properties": {"limit": {"type": "integer", "minimum": 1, "maximum": 25, "default": 10}}
        },
        "annotations": {"readOnlyHint": True, "openWorldHint": False}
    },
    {
        "name": "get_memory",
        "title": "Open a Sherry memory",
        "description": "Get one Sherry memory by id, with its full text and provenance.",
        "inputSchema": {
            "type": "object",
            "properties": {"memory_id": {"type": "string"}},
            "required": ["memory_id"]
        },
        "annotations": {"readOnlyHint": True, "openWorldHint": False}
    },
    {
        "name": "delete_memory",
        "title": "Delete a Sherry memory",
        "description": "Delete a Sherry memory by id. It disappears from all the user's devices. Only call this when the user explicitly asks to delete that memory.",
        "inputSchema": {
            "type": "object",
            "properties": {"memory_id": {"type": "string"}},
            "required": ["memory_id"]
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False}
    }
];


def _platform_from_name(name: str) -> str {
    lowered = name.lower();
    if "claude" in lowered or "anthropic" in lowered {
        return "claude";
    }
    if "openai" in lowered or "chatgpt" in lowered {
        return "chatgpt";
    }
    if "gemini" in lowered or "google" in lowered {
        return "gemini";
    }
    return "";
}


def _brief(m: any) -> dict {
    source: any = m.source or {};
    return {
        "id": m.id,
        "content": m.content,
        "tags": m.tags or [],
        "source": {
            "platform": source.platform,
            "type": source.type,
            "label": source.label,
            "url": source.url,
            "capturedVia": source.capturedVia
        },
        "createdAt": m.createdAt,
        "updatedAt": m.updatedAt
    };
}


def _tool_error(message: str) -> dict {
    return {"content": [{"type": "text", "text": message}], "isError": True};
}


def _tool_result(value: dict) -> dict {
    return {"content": [{"type": "text", "text": JSON.stringify(value)}], "structuredContent": value, "isError": False};
}


async def _call_tool(env: any, who: McpCaller, name: str, args: any) -> dict {
    person = Principal(userId=who.userId, email=who.email, via="mcp");
    ws = await ensure_workspace(env, person);
    if name == "save_memory" {
        body = text_of(args.content).strip();
        if not body {
            return _tool_error("content is empty.");
        }
        chosen = text_of(args.assistant).strip().lower();
        platform = chosen if chosen in PLATFORMS else (_platform_from_name(who.clientName) or "claude");
        title = text_of(args.title).strip()[:120];
        label = title or ("Saved from " + (who.clientName or platform) + " chat")[:120];
        key = "mcp-" + (await sha256_hex(platform + "\x1f" + body))[:48];
        url = text_of(args.source_url).strip();
        tags: any = args.tags if Array.isArray(args.tags) else [];
        memory: any = await create_memory(
            env,
            person,
            ws,
            {
                "content": body,
                "source_platform": platform,
                "idempotency_key": key,
                "tags": tags,
                "source_type": "conversation_excerpt",
                "source_label": label,
                "source_url": url if url.startswith("http") else "",
                "captured_via": "mcp"
            }
        );
        return _tool_result({"saved": True, "memory": _brief(memory)});
    }
    if name == "search_memories" or name == "list_recent_memories" {
        query = text_of(args.query) if name == "search_memories" else "";
        limit = max(1, min(int_of(args.limit, 10), 25));
        page: any = await list_memories(env, person, ws, {"query": query, "cursor": "", "limit": limit});
        items: list[dict] = [];
        for m in list(page.data) {
            items.append(_brief(m));
        }
        if name == "search_memories" {
            return _tool_result({"query": query, "total": page.total, "memories": items});
        }
        return _tool_result({"total": page.total, "memories": items});
    }
    if name == "get_memory" {
        memory: any = await get_memory(env, person, ws, {"id": text_of(args.memory_id)});
        if not memory {
            return _tool_error("No memory with that id (it may have been deleted).");
        }
        return _tool_result({"memory": _brief(memory)});
    }
    if name == "delete_memory" {
        deleted: any = await delete_memory(env, person, ws, {"id": text_of(args.memory_id)});
        if not deleted {
            return _tool_error("No memory with that id (it may already be deleted).");
        }
        return _tool_result({"deleted": True, "id": text_of(args.memory_id)});
    }
    return _tool_error("Unknown tool '" + name + "'.");
}


def _reply(id: any, result: any) -> dict {
    return {"jsonrpc": "2.0", "id": id, "result": result};
}


def _error(id: any, code: int, message: str) -> dict {
    return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}};
}


"""One JSON-RPC message -> its response, or None for notifications."""
async def _handle_message(env: any, who: McpCaller, msg: any) -> any {
    if not is_plain_object(msg) or text_of(msg.jsonrpc) != "2.0" or not text_of(msg.method) {
        return _error(None, -32600, "Invalid request.");
    }
    method = text_of(msg.method);
    # A JSON-RPC notification is a message without an id: no response.
    if not ("id" in msg) {
        return None;
    }
    params: any = msg.params or {};
    if method == "initialize" {
        asked = text_of(params.protocolVersion);
        version = asked if asked in SUPPORTED_VERSIONS else LATEST_VERSION;
        return _reply(
            msg.id,
            {
                "protocolVersion": version,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "sherry", "title": "Sherry memory", "version": "0.2.0", "websiteUrl": "https://sherry.sherry-cloud.workers.dev"},
                "instructions": INSTRUCTIONS
            }
        );
    }
    if method == "ping" {
        return _reply(msg.id, {});
    }
    if method == "tools/list" {
        return _reply(msg.id, {"tools": TOOLS});
    }
    if method == "tools/call" {
        name = text_of(params.name);
        args: any = params.arguments if is_plain_object(params.arguments) else {};
        try {
            return _reply(msg.id, await _call_tool(env, who, name, args));
        } except Exception as err {
            e: any = err;
            if e.sherryReject {
                return _reply(msg.id, _tool_error(text_of(e.message)));
            }
            console.error("sherry mcp: " + name + " failed", e);
            return _reply(msg.id, _tool_error("Sherry couldn't complete that right now. Try again."));
        }
    }
    return _error(msg.id, -32601, "Method not found: " + method);
}


def _json(payload: any, status: int) -> any {
    headers: dict = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type, mcp-protocol-version",
        "Cache-Control": "no-store"
    };
    return construct("Response", [JSON.stringify(payload), {"status": status, "headers": headers}]);
}


async def:pub handle_mcp(request: any, env: any, who: McpCaller) -> any {
    if request.method != "POST" {
        return construct("Response", [None, {"status": 405, "headers": {"Allow": "POST"}}]);
    }
    body: any = None;
    try {
        body = await request.json();
    } except Exception {
        return _json(_error(None, -32700, "Parse error."), 400);
    }
    if Array.isArray(body) {
        # JSON-RPC batch (2025-03-26 clients).
        replies: list = [];
        for item in list(body) {
            reply: any = await _handle_message(env, who, item);
            if reply {
                replies.append(reply);
            }
        }
        if len(replies) == 0 {
            return construct("Response", [None, {"status": 202}]);
        }
        return _json(replies, 200);
    }
    reply: any = await _handle_message(env, who, body);
    if not reply {
        return construct("Response", [None, {"status": 202}]);
    }
    return _json(reply, 200);
}
