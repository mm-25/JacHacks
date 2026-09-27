"""Dashboard, diagnostics and conversation list for the web app.

- dashboard_stats: everything the Dashboard cards show, in one call.
- list_conversations: the captured chats (Connected Conversations page).
- record_lookup: called by the MCP connector each time an assistant reads
  memories, so the dashboard can show lookups per assistant and the memories
  recalled most often (migrations/0003_usage.sql).
"""

import from .util { now_iso, now_seconds, new_id, text_of, int_of, query_all, query_one, execute, statement }
import from .auth { Principal }

glob ASSISTANTS: list[str] = ["claude", "chatgpt", "gemini", "codex", "antigravity"];
glob TOP_N: int = 5;
glob CAPTURE_FRESH_DAYS: int = 7;


"""Log one connector lookup and bump the recall count of what it returned."""
async def:pub record_lookup(env: any, user_id: str, platform: str, tool: str, ids: list[str]) -> None {
    stamp = now_iso();
    writes: list = [
        statement(
            env,
            "INSERT INTO memory_lookups (id, user_id, platform, tool, results, created_at) VALUES (?, ?, ?, ?, ?, ?)",
            [new_id(), user_id, platform, tool, len(ids), stamp]
        )
    ];
    if len(ids) > 0 {
        marks: list[str] = [];
        params: list = [stamp, user_id];
        for id in ids {
            marks.append("?");
            params.append(id);
        }
        writes.append(
            statement(
                env,
                "UPDATE memories SET recall_count = recall_count + 1, last_recalled_at = ? "
                + "WHERE user_id = ? AND id IN (" + ", ".join(marks) + ")",
                params
            )
        );
    }
    await env.DB.batch(writes);
}


"""Sort a list of dicts by `count`, largest first (stable)."""
def _by_count(items: list) -> list {
    # Insertion sort: jac2js turns list.sort(fn) into a Python-style key sort.
    i = 1;
    while i < len(items) {
        item = items[i];
        j = i - 1;
        while j >= 0 and items[j]["count"] < item["count"] {
            items[j + 1] = items[j];
            j -= 1;
        }
        items[j + 1] = item;
        i += 1;
    }
    return items;
}


"""The keys of a plain object (jac2js compiles `for k in d` to for...of)."""
def _keys(d: dict) -> list[str] {
    o: any = Object;
    return list(o.keys(d));
}


"""A use-case label for one summarized chat: its first topic tag (set by
Claude summaries), otherwise its title."""
def _use_case(tags_json: str, title: str) -> str {
    tags: any = [];
    try {
        tags = JSON.parse(tags_json or "[]");
    } except Exception {
        tags = [];
    }
    if Array.isArray(tags) and len(tags) > 0 {
        return text_of(tags[0]).replace("-", " ").strip()[:40];
    }
    label = title.strip();
    while label and label[len(label) - 1] in ".?!:" {
        label = label[:len(label) - 1];
    }
    return label[:40];
}


def _check(id: str, name: str, ok: bool, detail: str) -> dict {
    return {"id": id, "name": name, "status": "ok" if ok else "warn", "detail": detail};
}


async def _health(env: any, who: Principal, memory_total: int, last_capture: str) -> dict {
    checks: list[dict] = [];
    checks.append(_check("database", "Memory database", True, str(memory_total) + (" memory stored" if memory_total == 1 else " memories stored")));
    checks.append(_check("sign_in", "Sign-in", True, "Signed in as " + (who.email or "you")));
    if last_capture {
        age_days = (now_seconds() - Date.parse(last_capture) / 1000) / 86400;
        capture = _check(
            "capture", "Chat capture", age_days <= CAPTURE_FRESH_DAYS,
            "Last chat captured" if age_days <= CAPTURE_FRESH_DAYS
            else "No chats captured in the last " + str(CAPTURE_FRESH_DAYS) + " days"
        );
        capture["at"] = last_capture;
        checks.append(capture);
    } else {
        checks.append(_check("capture", "Chat capture", False, "No chats captured yet. Install the browser extension."));
    }
    rows = await query_all(
        env,
        "SELECT DISTINCT c.client_name AS name FROM oauth_tokens t JOIN oauth_clients c ON c.client_id = t.client_id "
        + "WHERE t.user_id = ? AND t.kind = 'refresh' AND t.expires_at > ?",
        [who.userId, now_seconds()]
    );
    names: list[str] = [];
    for r in rows {
        name = text_of(r.name) or "An assistant";
        if name not in names {
            names.append(name);
        }
    }
    checks.append(
        _check(
            "connector", "Assistant connector", len(names) > 0,
            ("Connected: " + ", ".join(names)) if len(names) > 0 else "No assistant connected yet"
        )
    );
    claude = bool(text_of(env.ANTHROPIC_API_KEY)) and text_of(env.SHERRY_SUMMARIES) != "off";
    checks.append(
        _check(
            "summaries", "Chat summaries", claude,
            "Written by Claude" if claude else "Basic summaries. Add an Anthropic API key for Claude summaries."
        )
    );
    ready = 0;
    for c in checks {
        if c["status"] == "ok" {
            ready += 1;
        }
    }
    return {"ready": ready, "total": len(checks), "checks": checks};
}


async def:pub dashboard_stats(env: any, who: Principal, ws: str, body: any) -> dict {
    uid = who.userId;

    # Chats by platform and by capture channel.
    chat_rows = await query_all(
        env,
        "SELECT platform, captured_via, COUNT(*) AS n, MAX(updated_at) AS last FROM conversations "
        + "WHERE user_id = ? AND ignored = 0 GROUP BY platform, captured_via",
        [uid]
    );
    total_chats = 0;
    last_capture = "";
    per_platform: dict = {};
    channels: list = [];
    for r in chat_rows {
        n = int_of(r.n, 0);
        platform = text_of(r.platform);
        total_chats += n;
        per_platform[platform] = per_platform.get(platform, 0) + n;
        via = text_of(r.captured_via);
        channels.append({"platform": platform, "channel": "Desktop" if via == "desktop" else "Web", "count": n});
        if text_of(r.last) > last_capture {
            last_capture = text_of(r.last);
        }
    }
    chats: list = [];
    for platform in _keys(per_platform) {
        chats.append({"platform": platform, "count": per_platform[platform]});
    }
    _by_count(chats);
    _by_count(channels);

    # Tool mix: captured chats, plus what assistants saved and looked up through the connector.
    activity: dict = {**per_platform};
    saved_rows = await query_all(
        env,
        "SELECT source_platform AS platform, COUNT(*) AS n FROM memories "
        + "WHERE user_id = ? AND deleted_at = '' AND captured_via = 'mcp' GROUP BY source_platform",
        [uid]
    );
    lookup_rows = await query_all(
        env,
        "SELECT platform, COUNT(*) AS n FROM memory_lookups WHERE user_id = ? GROUP BY platform",
        [uid]
    );
    lookups: list = [];
    for r in lookup_rows {
        lookups.append({"platform": text_of(r.platform), "count": int_of(r.n, 0)});
    }
    _by_count(lookups);
    for r in list(saved_rows) + list(lookup_rows) {
        platform = text_of(r.platform);
        if platform in ASSISTANTS {
            activity[platform] = activity.get(platform, 0) + int_of(r.n, 0);
        }
    }
    activity_total = 0;
    for platform in _keys(activity) {
        activity_total += activity[platform];
    }
    mix: list = [];
    for platform in _keys(activity) {
        count = activity[platform];
        mix.append({"platform": platform, "count": count, "percent": Math.round(count * 100 / activity_total) if activity_total else 0});
    }
    _by_count(mix);

    # Memories handed to assistants most often.
    top_rows = await query_all(
        env,
        "SELECT id, content, source_label, source_platform, recall_count FROM memories "
        + "WHERE user_id = ? AND deleted_at = '' AND recall_count > 0 "
        + "ORDER BY recall_count DESC, last_recalled_at DESC LIMIT " + str(TOP_N),
        [uid]
    );
    top_memories: list = [];
    for r in top_rows {
        top_memories.append({
            "id": text_of(r.id),
            "text": text_of(r.source_label) or text_of(r.content)[:120],
            "platform": text_of(r.source_platform),
            "recalls": int_of(r.recall_count, 0)
        });
    }

    # Use cases, from each summarized chat's topic tag or title.
    summary_rows = await query_all(
        env,
        "SELECT c.platform AS platform, c.title AS title, m.tags AS tags FROM conversations c "
        + "JOIN memories m ON m.user_id = c.user_id AND m.conversation_id = c.id AND m.deleted_at = '' "
        + "WHERE c.user_id = ? AND c.ignored = 0",
        [uid]
    );
    cases: dict = {};
    for r in summary_rows {
        label = _use_case(text_of(r.tags), text_of(r.title));
        if not label {
            continue;
        }
        # Group case-insensitively; show the first spelling seen ("Arbor AI").
        group = label.lower();
        entry: dict = cases.get(group, {"label": label, "count": 0, "platforms": {}});
        entry["count"] = entry["count"] + 1;
        platform = text_of(r.platform);
        tally: dict = entry["platforms"];
        tally[platform] = tally.get(platform, 0) + 1;
        cases[group] = entry;
    }
    use_cases: list = [];
    for group in _keys(cases) {
        entry: dict = cases[group];
        tally: dict = entry["platforms"];
        best = "";
        best_n = 0;
        for platform in _keys(tally) {
            if tally[platform] > best_n {
                best = platform;
                best_n = tally[platform];
            }
        }
        use_cases.append({"label": entry["label"], "count": entry["count"], "platform": best});
    }
    _by_count(use_cases);

    memory_row: any = await query_one(env, "SELECT COUNT(*) AS n FROM memories WHERE user_id = ? AND deleted_at = ''", [uid]);
    memory_total = int_of(memory_row.n if memory_row else 0, 0);

    return {
        "totalChats": total_chats,
        "chatsByPlatform": chats,
        "toolMix": mix,
        "topMemories": top_memories,
        "useCases": use_cases[:TOP_N],
        "summarizedChats": len(summary_rows),
        "lookups": lookups,
        "topPlatform": channels[0] if len(channels) > 0 else None,
        "nextPlatform": channels[1] if len(channels) > 1 else None,
        "totalMemories": memory_total,
        "health": await _health(env, who, memory_total, last_capture)
    };
}


async def:pub list_conversations(env: any, who: Principal, ws: str, body: any) -> dict {
    start = max(0, int_of(text_of(body.cursor), 0));
    size = max(1, min(int_of(body.limit, 25), 100));
    total_row: any = await query_one(
        env, "SELECT COUNT(*) AS n FROM conversations WHERE user_id = ? AND ignored = 0", [who.userId]
    );
    total = int_of(total_row.n if total_row else 0, 0);
    rows = await query_all(
        env,
        "SELECT c.id, c.platform, c.title, c.url, c.context, c.captured_via, c.created_at, c.updated_at, "
        + "c.summary_engine, (SELECT COUNT(*) FROM messages WHERE conversation_id = c.id) AS messages "
        + "FROM conversations c WHERE c.user_id = ? AND c.ignored = 0 "
        + "ORDER BY c.updated_at DESC LIMIT " + str(size) + " OFFSET " + str(start),
        [who.userId]
    );
    items: list = [];
    for r in rows {
        items.append({
            "id": text_of(r.id),
            "platform": text_of(r.platform),
            "title": text_of(r.title),
            "url": text_of(r.url),
            "context": text_of(r.context),
            "capturedVia": text_of(r.captured_via),
            "messages": int_of(r.messages, 0),
            "summaryEngine": text_of(r.summary_engine),
            "createdAt": text_of(r.created_at),
            "updatedAt": text_of(r.updated_at)
        });
    }
    return {"data": items, "nextCursor": str(start + size) if start + size < total else None, "total": total};
}
