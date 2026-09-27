"""Memory endpoints on D1. Same behaviour and wire shapes as
apps/web/services/memories.sv.jac (see data-schema-specification.md): soft
deletes with undo, idempotent creates, search over content, tags, label,
platform and project, offset cursors, and the demo workspace.
"""

import from .util {
    now_iso,
    new_id,
    reject,
    text_of,
    int_of,
    is_http_url,
    query_all,
    query_one,
    execute,
    statement,
    MAX_LIMIT,
    DEFAULT_LIMIT
}
import from .auth { Principal }

glob:pub CAPTURE_CHANNELS: list[str] = ["app", "mcp", "extension", "desktop", "import"];
glob:pub SOURCE_TYPES: list[str] = ["manual_note", "conversation_excerpt", "import"];
glob:pub SOURCE_PLATFORMS: list[str] = [
    "web", "desktop", "mobile", "chatgpt", "claude", "gemini", "codex", "antigravity"
];
glob MAX_CONTENT: int = 20000;
glob MAX_TAGS: int = 20;
glob MAX_TAG_LEN: int = 40;
glob MAX_LABEL_LEN: int = 120;
glob MAX_CONTEXT_LEN: int = 200;
glob MEMORY_COLUMNS: str = (
    "id, content, tags, source_type, source_platform, source_label, source_url, "
    + "source_context, captured_via, conversation_id, created_at, updated_at, deleted_at"
);


"""The public Memory shape (camelCase), from a `memories` row."""
def:pub memory_view(row: any, workspace_id: str) -> dict {
    tags: any = [];
    try {
        tags = JSON.parse(text_of(row.tags) or "[]");
    } except Exception {
        tags = [];
    }
    return {
        "id": text_of(row.id),
        "workspaceId": workspace_id,
        "content": text_of(row.content),
        "tags": tags,
        "source": {
            "type": text_of(row.source_type),
            "platform": text_of(row.source_platform),
            "label": text_of(row.source_label) or None,
            "url": text_of(row.source_url) or None,
            "context": text_of(row.source_context) or None,
            "capturedVia": text_of(row.captured_via) or "app",
            "conversationId": text_of(row.conversation_id) or None
        },
        "createdAt": text_of(row.created_at),
        "updatedAt": text_of(row.updated_at),
        "deletedAt": text_of(row.deleted_at) or None
    };
}


def:pub clean_tags(raw: any) -> list[str] {
    cleaned: list[str] = [];
    if not Array.isArray(raw) {
        return cleaned;
    }
    for item in list(raw) {
        tag = text_of(item).strip();
        while tag.startswith("#") {
            tag = tag[1:];
        }
        tag = tag.lower();
        if not tag or tag in cleaned {
            continue;
        }
        if len(tag) > MAX_TAG_LEN {
            reject(f"Tags can be at most {MAX_TAG_LEN} characters.");
        }
        cleaned.append(tag);
    }
    if len(cleaned) > MAX_TAGS {
        reject(f"A memory can have at most {MAX_TAGS} tags.");
    }
    return cleaned;
}


def _like(needle: str) -> str {
    escaped = needle.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_");
    return "%" + escaped + "%";
}


# Words that carry no meaning for search ("what is my favorite animal" -> favorite, animal).
glob STOP_WORDS: list[str] = [
    "the", "and", "for", "are", "was", "were", "what", "which", "who", "whom", "whose",
    "when", "where", "why", "how", "you", "your", "yours", "my", "mine", "me", "our", "ours",
    "his", "her", "hers", "its", "their", "them", "they", "this", "that", "these", "those",
    "with", "from", "about", "into", "have", "has", "had", "does", "did", "do", "can", "could",
    "should", "would", "will", "shall", "not", "any", "all", "some", "there", "here", "just",
    "tell", "know", "remember", "sherry", "please", "also", "then", "than", "is", "am", "be",
    "o", "a", "de", "do", "da", "que", "qual", "meu", "minha", "sobre", "com", "para"
];
glob MAX_TERMS: int = 8;


"""Search words from a query: lowercased, punctuation trimmed, stop words and
1-letter words dropped. A query of only stop words searches as one phrase."""
def _terms(needle: str) -> list[str] {
    terms: list[str] = [];
    for raw in needle.split() {
        word = raw.strip(".,;:!?()[]{}\"'`“”‘’");
        if len(word) < 2 or word in STOP_WORDS or word in terms {
            continue;
        }
        terms.append(word);
    }
    if len(terms) == 0 {
        return [needle];
    }
    return terms[:MAX_TERMS];
}


"""List active memories, newest first. With a query, memories matching any of
its words are returned, those matching the most words first (then newest)."""
async def:pub list_memories(env: any, who: Principal, ws: str, body: any) -> dict {
    needle = text_of(body.query).strip().lower();
    cursor = text_of(body.cursor);
    start = int_of(cursor, 0) if cursor else 0;
    start = max(0, start);
    size = max(1, min(int_of(body.limit, DEFAULT_LIMIT), MAX_LIMIT));
    params: list = [who.userId];
    score = "0";
    if needle {
        haystack = (
            "(lower(content) || ' ' || lower(source_label) || ' ' || source_platform || ' ' "
            + "|| lower(source_context) || ' ' || lower(tags))"
        );
        parts: list[str] = [];
        for term in _terms(needle) {
            params.append(_like(term));
            parts.append(f"(CASE WHEN {haystack} LIKE ?{len(params)} ESCAPE '\\' THEN 1 ELSE 0 END)");
        }
        score = " + ".join(parts);
    }
    where = "user_id = ?1 AND deleted_at = ''" + (f" AND ({score}) > 0" if needle else "");
    # kind: "chat" = summaries of captured chats, "personal" = everything else.
    kind = text_of(body.kind);
    if kind == "chat" {
        where += " AND conversation_id != ''";
    } elif kind == "personal" {
        where += " AND conversation_id = ''";
    }
    total_row: any = await query_one(env, f"SELECT COUNT(*) AS n FROM memories WHERE {where}", params);
    total = int_of(total_row.n if total_row else 0, 0);
    rows = await query_all(
        env,
        f"SELECT {MEMORY_COLUMNS}, ({score}) AS score FROM memories WHERE {where} "
        + f"ORDER BY score DESC, updated_at DESC LIMIT {size} OFFSET {start}",
        params
    );
    next_cursor: any = str(start + size) if start + size < total else None;
    return {
        "data": [memory_view(r, ws) for r in rows],
        "nextCursor": next_cursor,
        "total": total
    };
}


async def:pub find_memory(env: any, who: Principal, id: str) -> any {
    return await query_one(
        env, f"SELECT {MEMORY_COLUMNS} FROM memories WHERE user_id = ? AND id = ?", [who.userId, id]
    );
}


async def:pub get_memory(env: any, who: Principal, ws: str, body: any) -> any {
    row: any = await find_memory(env, who, text_of(body.id));
    if not row or text_of(row.deleted_at) {
        return None;
    }
    return memory_view(row, ws);
}


"""Create a memory. Replaying the same `idempotency_key` returns the memory
created the first time instead of a duplicate (FR-041, AT-03)."""
async def:pub create_memory(env: any, who: Principal, ws: str, body: any) -> dict {
    key = text_of(body.idempotency_key).strip();
    if len(key) < 16 or len(key) > 128 {
        reject("idempotency_key must be 16-128 characters.");
    }
    existing: any = await query_one(
        env,
        f"SELECT {MEMORY_COLUMNS} FROM memories WHERE user_id = ? AND idempotency_key = ?",
        [who.userId, key]
    );
    if existing {
        return memory_view(existing, ws);
    }
    content = text_of(body.content).strip();
    if not content {
        reject("Memory content is required.");
    }
    if len(content) > MAX_CONTENT {
        reject(f"Memory content can be at most {MAX_CONTENT} characters.");
    }
    source_type = text_of(body.source_type) or "manual_note";
    platform = text_of(body.source_platform);
    via = text_of(body.captured_via) or "app";
    if source_type not in SOURCE_TYPES {
        reject("Unknown source type '" + source_type + "'.");
    }
    if platform not in SOURCE_PLATFORMS {
        reject("Unknown source platform '" + platform + "'.");
    }
    if via not in CAPTURE_CHANNELS {
        reject("Unknown capture channel '" + via + "'.");
    }
    label = text_of(body.source_label).strip();
    if len(label) > MAX_LABEL_LEN {
        reject(f"Source label can be at most {MAX_LABEL_LEN} characters.");
    }
    url = text_of(body.source_url).strip();
    if url and not is_http_url(url) {
        reject("Source URL must start with http:// or https://.");
    }
    context = text_of(body.source_context).strip();
    if len(context) > MAX_CONTEXT_LEN {
        reject(f"Source context can be at most {MAX_CONTEXT_LEN} characters.");
    }
    tags = clean_tags(body.tags);
    stamp = now_iso();
    await execute(
        env,
        "INSERT INTO memories (id, user_id, content, tags, source_type, source_platform, source_label, "
        + "source_url, source_context, captured_via, idempotency_key, created_at, updated_at) "
        + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (user_id, idempotency_key) DO NOTHING",
        [new_id(), who.userId, content, JSON.stringify(tags), source_type, platform, label, url, context, via, key, stamp, stamp]
    );
    row: any = await query_one(
        env,
        f"SELECT {MEMORY_COLUMNS} FROM memories WHERE user_id = ? AND idempotency_key = ?",
        [who.userId, key]
    );
    return memory_view(row, ws);
}


"""Deleting a chat summary is a privacy action: its captured transcript is
erased and the chat is ignored from then on. Undo lifts the ignore flag."""
async def:pub forget_conversation(env: any, who: Principal, conversation_id: str, forget: bool) {
    owned: any = await query_one(
        env, "SELECT id FROM conversations WHERE id = ? AND user_id = ?", [conversation_id, who.userId]
    );
    if not owned {
        return;
    }
    stamp = now_iso();
    if forget {
        await env.DB.batch(
            [
                statement(env, "DELETE FROM messages WHERE conversation_id = ?", [conversation_id]),
                statement(
                    env,
                    "UPDATE conversations SET ignored = 1, summarized_hash = '', updated_at = ? WHERE id = ?",
                    [stamp, conversation_id]
                )
            ]
        );
    } else {
        await execute(
            env, "UPDATE conversations SET ignored = 0, updated_at = ? WHERE id = ?", [stamp, conversation_id]
        );
    }
}


"""Soft-delete a memory. Returns False when it doesn't exist."""
async def:pub delete_memory(env: any, who: Principal, ws: str, body: any) -> bool {
    row: any = await find_memory(env, who, text_of(body.id));
    if not row or text_of(row.deleted_at) {
        return False;
    }
    stamp = now_iso();
    await execute(
        env, "UPDATE memories SET deleted_at = ?, updated_at = ? WHERE id = ?", [stamp, stamp, row.id]
    );
    if text_of(row.conversation_id) {
        await forget_conversation(env, who, text_of(row.conversation_id), True);
    }
    return True;
}


"""Undo a soft delete (backs the 'Undo' action after deleting)."""
async def:pub restore_memory(env: any, who: Principal, ws: str, body: any) -> any {
    row: any = await find_memory(env, who, text_of(body.id));
    if not row {
        return None;
    }
    await execute(
        env, "UPDATE memories SET deleted_at = '', updated_at = ? WHERE id = ?", [now_iso(), row.id]
    );
    if text_of(row.conversation_id) {
        await forget_conversation(env, who, text_of(row.conversation_id), False);
    }
    return memory_view(await find_memory(env, who, text_of(row.id)), ws);
}


# ---------- demo workspace ----------

glob SEED: list[dict] = [
    {"key": "mem_demo_001", "content": "Use concise weekly project updates.", "tags": ["preference", "writing"], "type": "manual_note", "platform": "web", "label": "Quick capture", "url": ""},
    {"key": "mem_demo_002", "content": "Decision: Sherry stores memories as user-visible saved items, not auto-inferred facts. Keeps the demo trustworthy and every item traceable to a source.", "tags": ["decision", "product"], "type": "conversation_excerpt", "platform": "claude", "label": "Product scoping chat", "url": ""},
    {"key": "mem_demo_003", "content": "I prefer TypeScript strict mode and small, single-purpose pull requests.", "tags": ["preference", "engineering"], "type": "manual_note", "platform": "desktop", "label": "Quick capture", "url": ""},
    {"key": "mem_demo_004", "content": "Research note: spaced repetition works best when review intervals roughly double after each successful recall.", "tags": ["research", "learning"], "type": "conversation_excerpt", "platform": "chatgpt", "label": "Study techniques thread", "url": ""},
    {"key": "mem_demo_005", "content": "Dietary preference: vegetarian, no mushrooms. Mention this when asking for recipes.", "tags": ["preference", "personal"], "type": "manual_note", "platform": "mobile", "label": "Pocket capture", "url": ""},
    {"key": "mem_demo_006", "content": "Gemini suggested structuring the pitch as problem, live demo, then provenance and deletion to show trust.", "tags": ["pitch", "hackathon"], "type": "conversation_excerpt", "platform": "gemini", "label": "Pitch brainstorm", "url": ""},
    {"key": "mem_demo_007", "content": "Imported reading list: 'Designing Data-Intensive Applications' chapters 5 and 9 on replication and consistency.", "tags": ["reading"], "type": "import", "platform": "web", "label": "Bookmarks import", "url": "https://dataintensive.net/"}
];


async def _seed(env: any, who: Principal) {
    base = Date.UTC(2026, 8, 26, 18, 0, 0);
    batch: list = [];
    i = 0;
    for s in SEED {
        stamp_date: any = new(Date, base - i * 7 * 3600 * 1000);
        stamp = str(stamp_date.toISOString());
        batch.append(
            statement(
                env,
                "INSERT INTO memories (id, user_id, content, tags, source_type, source_platform, source_label, "
                + "source_url, idempotency_key, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
                + "ON CONFLICT (user_id, idempotency_key) DO NOTHING",
                [
                    new_id(), who.userId, s["content"], JSON.stringify(s["tags"]), s["type"], s["platform"],
                    s["label"], s["url"], "seed-" + str(s["key"]) + "-0000000000", stamp, stamp
                ]
            )
        );
        i += 1;
    }
    await env.DB.batch(batch);
}


"""Turn this workspace into the demo workspace and add the sample memories if
they aren't there yet. Safe to call repeatedly."""
async def:pub load_demo_data(env: any, who: Principal, ws: str, body: any) -> dict {
    await execute(env, "UPDATE workspaces SET is_demo = 1 WHERE user_id = ?", [who.userId]);
    seeded: any = await query_one(
        env,
        "SELECT 1 AS x FROM memories WHERE user_id = ? AND idempotency_key LIKE 'seed-%' LIMIT 1",
        [who.userId]
    );
    if not seeded {
        await _seed(env, who);
    }
    return await list_memories(env, who, ws, {"query": "", "cursor": "", "limit": DEFAULT_LIMIT});
}


"""Wipe a demo workspace and restore the seed data (FR-061). Refuses on real
workspaces so a stray call can't erase a user's memories."""
async def:pub reset_demo(env: any, who: Principal, ws: str, body: any) -> dict {
    row: any = await query_one(env, "SELECT is_demo FROM workspaces WHERE user_id = ?", [who.userId]);
    if not row or not int_of(row.is_demo, 0) {
        reject("Only the demo workspace can be reset.");
    }
    await execute(env, "DELETE FROM memories WHERE user_id = ?", [who.userId]);
    await _seed(env, who);
    return await list_memories(env, who, ws, {"query": "", "cursor": "", "limit": DEFAULT_LIMIT});
}
