"""Chat capture endpoints on D1 (port of apps/web/services/captures.sv.jac).

The browser extension (`captured_via="extension"`) and the desktop sync
(`captured_via="desktop"`) send whole chats; each becomes one conversation with
its messages plus ONE summary memory that is rewritten as the chat grows.
Messages are keyed by the capturer, so resending a chat only stores what
changed. See data-schema-specification.md.
"""

import from .util {
    now_iso,
    new_id,
    reject,
    text_of,
    int_of,
    is_http_url,
    sha256_hex,
    query_all,
    query_one,
    execute,
    statement
}
import from .auth { Principal }
import from .memories { memory_view, clean_tags }
import from .summarizer { summarize }

glob CAPTURE_PLATFORMS: list[str] = ["chatgpt", "claude", "gemini", "codex", "antigravity"];
glob CAPTURERS: list[str] = ["extension", "desktop"];
glob ROLES: list[str] = ["user", "assistant"];
glob MAX_MESSAGES_PER_CAPTURE: int = 300;
glob MAX_MESSAGE_CHARS: int = 100000;
glob MAX_TITLE_CHARS: int = 200;
glob MAX_CONTEXT_CHARS: int = 200;
glob CONVERSATION_COLUMNS: str = (
    "id, platform, external_id, url, title, context, captured_via, created_at, updated_at, "
    + "summarized_hash, summarized_at, summary_engine, summary_note, ignored"
);


async def _find_conversation(env: any, who: Principal, platform: str, external_id: str) -> any {
    return await query_one(
        env,
        f"SELECT {CONVERSATION_COLUMNS} FROM conversations WHERE user_id = ? AND platform = ? AND external_id = ?",
        [who.userId, platform, external_id]
    );
}


async def _ordered_messages(env: any, conversation_id: str) -> list {
    return await query_all(
        env,
        "SELECT key, role, text, position, sent_at, captured_at FROM messages "
        + "WHERE conversation_id = ? ORDER BY position, captured_at, key",
        [conversation_id]
    );
}


async def _transcript_hash(messages: list) -> str {
    joined = "";
    for m in messages {
        row: any = m;
        joined += text_of(row.key) + "\x1f" + text_of(row.role) + "\x1f" + text_of(row.text) + "\x1e";
    }
    return await sha256_hex(joined);
}


"""The original send time as ISO-8601 UTC, or "" when missing/unparseable
(capturers may not know it; Sherry never invents one)."""
def _sent_at(raw: any) -> str {
    text = text_of(raw).strip();
    if not text or len(text) > 40 {
        return "";
    }
    has_zone = text.endswith("Z") or new(RegExp, "[+-]\\d\\d:?\\d\\d$").test(text);
    if not has_zone {
        return "";
    }
    parsed: any = Date.parse(text);
    if Number.isNaN(parsed) {
        return "";
    }
    d: any = new(Date, parsed);
    return str(d.toISOString());
}


"""Store (or update) the messages of one chat."""
async def:pub capture_conversation(env: any, who: Principal, ws: str, body: any) -> dict {
    platform = text_of(body.platform);
    via = text_of(body.captured_via) or "extension";
    if platform not in CAPTURE_PLATFORMS {
        reject("Unknown capture platform '" + platform + "'.");
    }
    if via not in CAPTURERS {
        reject("Unknown capturer '" + via + "'.");
    }
    external_id = text_of(body.conversation_id).strip();
    if not external_id or len(external_id) > 200 {
        reject("conversation_id must be 1-200 characters.");
    }
    link = text_of(body.url).strip();
    if link and not is_http_url(link) {
        reject("url must start with http:// or https://.");
    }
    incoming: list = list(body.messages or []) if Array.isArray(body.messages) else [];
    if len(incoming) > MAX_MESSAGES_PER_CAPTURE {
        reject(f"Send at most {MAX_MESSAGES_PER_CAPTURE} messages per capture.");
    }
    title = text_of(body.title).strip()[:MAX_TITLE_CHARS];
    context = text_of(body.context).strip()[:MAX_CONTEXT_CHARS];
    stamp = now_iso();
    c: any = await _find_conversation(env, who, platform, external_id);
    if not c {
        await execute(
            env,
            "INSERT INTO conversations (id, user_id, platform, external_id, url, title, context, captured_via, "
            + "created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
            + "ON CONFLICT (user_id, platform, external_id) DO NOTHING",
            [new_id(), who.userId, platform, external_id, link, title, context, via, stamp, stamp]
        );
        c = await _find_conversation(env, who, platform, external_id);
    }
    if int_of(c.ignored, 0) {
        return {
            "conversationId": text_of(c.id), "received": len(incoming), "added": 0, "updated": 0,
            "totalMessages": 0, "ignored": True, "summaryStale": False
        };
    }
    existing: dict = {};
    for m in await _ordered_messages(env, text_of(c.id)) {
        row: any = m;
        existing[text_of(row.key)] = row;
    }
    writes: list = [];
    added = 0;
    updated = 0;
    seen: list[str] = [];
    for raw in incoming {
        item: any = raw;
        key = text_of(item.key).strip()[:200];
        role = text_of(item.role);
        text = text_of(item.text).strip()[:MAX_MESSAGE_CHARS];
        position = int_of(item.position, 0);
        sent_at = _sent_at(item.createdAt);
        if not key or role not in ROLES or not text or key in seen {
            continue;
        }
        seen.append(key);
        if key in existing {
            old: any = existing[key];
            if text_of(old.text) != text or text_of(old.role) != role or int_of(old.position, 0) != position {
                writes.append(
                    statement(
                        env,
                        "UPDATE messages SET text = ?, role = ?, position = ?, updated_at = ? "
                        + "WHERE conversation_id = ? AND key = ?",
                        [text, role, position, stamp, c.id, key]
                    )
                );
                updated += 1;
            }
            if sent_at and not text_of(old.sent_at) {
                writes.append(
                    statement(
                        env,
                        "UPDATE messages SET sent_at = ? WHERE conversation_id = ? AND key = ?",
                        [sent_at, c.id, key]
                    )
                );
            }
            continue;
        }
        writes.append(
            statement(
                env,
                "INSERT INTO messages (conversation_id, key, role, text, position, sent_at, captured_at, updated_at) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                [c.id, key, role, text, position, sent_at, stamp, stamp]
            )
        );
        added += 1;
    }
    changes: list[str] = [];
    values: list = [];
    if link and link != text_of(c.url) {
        changes.append("url = ?");
        values.append(link);
    }
    if title and title != text_of(c.title) {
        changes.append("title = ?");
        values.append(title);
    }
    if context and context != text_of(c.context) {
        changes.append("context = ?");
        values.append(context);
    }
    if added > 0 or updated > 0 {
        changes.append("updated_at = ?");
        values.append(stamp);
    }
    if len(changes) > 0 {
        values.append(c.id);
        writes.append(statement(env, "UPDATE conversations SET " + ", ".join(changes) + " WHERE id = ?", values));
    }
    if len(writes) > 0 {
        await env.DB.batch(writes);
    }
    ordered = await _ordered_messages(env, text_of(c.id));
    stale = len(ordered) > 0 and await _transcript_hash(ordered) != text_of(c.summarized_hash);
    return {
        "conversationId": text_of(c.id), "received": len(incoming), "added": added, "updated": updated,
        "totalMessages": len(ordered), "ignored": False, "summaryStale": stale
    };
}


def _summary_key(c: any) -> str {
    return ("conv-" + text_of(c.platform) + "-" + text_of(c.external_id))[:128];
}


"""Create or refresh the summary memory of one captured chat. Does nothing
(`status="unchanged"`) when the transcript hasn't changed, unless `force`."""
async def:pub summarize_conversation(env: any, who: Principal, ws: str, body: any) -> dict {
    c: any = await _find_conversation(env, who, text_of(body.platform), text_of(body.conversation_id).strip());
    if not c {
        return {"status": "not_found", "memory": None, "engine": "", "note": ""};
    }
    if int_of(c.ignored, 0) {
        return {"status": "ignored", "memory": None, "engine": "", "note": ""};
    }
    ordered = await _ordered_messages(env, text_of(c.id));
    if len(ordered) == 0 {
        return {"status": "empty", "memory": None, "engine": "", "note": ""};
    }
    key = _summary_key(c);
    existing: any = await query_one(
        env, "SELECT id FROM memories WHERE user_id = ? AND idempotency_key = ?", [who.userId, key]
    );
    digest = await _transcript_hash(ordered);
    if existing and digest == text_of(c.summarized_hash) and not body.force {
        row: any = await query_one(env, "SELECT * FROM memories WHERE id = ?", [existing.id]);
        return {
            "status": "unchanged", "memory": memory_view(row, ws),
            "engine": text_of(c.summary_engine), "note": text_of(c.summary_note)
        };
    }
    lines: list[dict] = [];
    for m in ordered {
        msg: any = m;
        lines.append({"role": text_of(msg.role), "text": text_of(msg.text)});
    }
    result = await summarize(env, text_of(c.title), lines);
    stamp = now_iso();
    status = "updated";
    tags = clean_tags(result["tags"]);
    label = str(result["title"])[:120];
    via = text_of(c.captured_via) or "extension";
    if not existing {
        await execute(
            env,
            "INSERT INTO memories (id, user_id, content, tags, source_type, source_platform, source_label, source_url, "
            + "source_context, captured_via, conversation_id, idempotency_key, created_at, updated_at) "
            + "VALUES (?, ?, ?, ?, 'conversation_excerpt', ?, ?, ?, ?, ?, ?, ?, ?, ?) "
            + "ON CONFLICT (user_id, idempotency_key) DO NOTHING",
            [new_id(), who.userId, result["content"], JSON.stringify(tags), c.platform, label, text_of(c.url),
             text_of(c.context), via, c.id, key, stamp, stamp]
        );
        status = "created";
    } else {
        current: any = await query_one(env, "SELECT tags, source_label, source_url, source_context FROM memories WHERE id = ?", [existing.id]);
        await execute(
            env,
            "UPDATE memories SET content = ?, tags = ?, source_label = ?, source_url = ?, source_context = ?, "
            + "updated_at = ? WHERE id = ?",
            [
                result["content"],
                JSON.stringify(tags) if len(tags) > 0 else text_of(current.tags),
                label or text_of(current.source_label),
                text_of(c.url) or text_of(current.source_url),
                text_of(c.context) or text_of(current.source_context),
                stamp,
                existing.id
            ]
        );
    }
    await execute(
        env,
        "UPDATE conversations SET summarized_hash = ?, summarized_at = ?, summary_engine = ?, summary_note = ? WHERE id = ?",
        [digest, stamp, result["engine"], result["note"], c.id]
    );
    saved: any = await query_one(
        env, "SELECT * FROM memories WHERE user_id = ? AND idempotency_key = ?", [who.userId, key]
    );
    return {"status": status, "memory": memory_view(saved, ws), "engine": result["engine"], "note": result["note"]};
}


"""The captured transcript behind a chat summary (provenance for the web app)."""
async def:pub get_conversation(env: any, who: Principal, ws: str, body: any) -> any {
    c: any = await query_one(
        env,
        f"SELECT {CONVERSATION_COLUMNS} FROM conversations WHERE user_id = ? AND id = ?",
        [who.userId, text_of(body.id)]
    );
    if not c {
        return None;
    }
    ordered = await _ordered_messages(env, text_of(c.id));
    messages: list[dict] = [];
    for m in ordered {
        msg: any = m;
        messages.append(
            {
                "role": text_of(msg.role), "text": text_of(msg.text), "position": int_of(msg.position, 0),
                "capturedAt": text_of(msg.captured_at), "sentAt": text_of(msg.sent_at) or None
            }
        );
    }
    return {
        "id": text_of(c.id),
        "platform": text_of(c.platform),
        "url": text_of(c.url),
        "title": text_of(c.title),
        "context": text_of(c.context) or None,
        "capturedVia": text_of(c.captured_via) or "extension",
        "messageCount": len(messages),
        "messages": messages,
        "summarizedAt": text_of(c.summarized_at) or None,
        "summaryEngine": text_of(c.summary_engine) or None,
        "summaryNote": text_of(c.summary_note) or None
    };
}
