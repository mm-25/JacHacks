"""Sherry memory API and data layer.

The Jac graph is the database. Every signed-in user gets an isolated `root`;
under it hangs exactly one `Workspace`, and every saved item is a `Memory`
node connected to that workspace:

    root --> Workspace --> Memory, Memory, ...

All endpoints except `health` are authenticated (`def:priv`), so each caller
only ever reads and writes their own workspace (NFR-004). Deletes are soft
(`deleted_at` is set) so demo mistakes can be undone (FR-052).

New workspaces start empty. Sample data is only loaded by `load_demo_data`
(the web app's "Open the demo workspace" button), which also marks the
workspace as a demo so that `reset_demo` is allowed on it.

The wire shapes (`MemoryView`, `MemorySource`, `MemoryPage`) mirror the
`Memory` contract in REQUIREMENTS.md, including camelCase field names, so
mobile and desktop clients can call the same `/function/<name>` endpoints.
"""

import from datetime { datetime, timezone, timedelta }

# How an item reached Sherry: typed in a Sherry app, saved by an assistant via
# MCP, captured from a website by the browser extension, captured from local AI
# tool logs by the desktop app, or bulk-imported.
glob CAPTURE_CHANNELS: list[str] = ["app", "mcp", "extension", "desktop", "import"];
glob SOURCE_TYPES: list[str] = ["manual_note", "conversation_excerpt", "import"];
glob SOURCE_PLATFORMS: list[str] = [
         "web",
         "desktop",
         "mobile",
         "chatgpt",
         "claude",
         "gemini",
         "codex",
         "antigravity"
     ];
glob MAX_CONTENT: int = 20000;
glob MAX_TAGS: int = 20;
glob MAX_TAG_LEN: int = 40;
glob MAX_LABEL_LEN: int = 120;
glob MAX_CONTEXT_LEN: int = 200;
glob DEFAULT_LIMIT: int = 25;
glob MAX_LIMIT: int = 100;


node Workspace {
    has name: str = "My workspace",
        created_at: str = "",
        is_demo: bool = False;
}


node Memory {
    has content: str,
        tags: list[str] = [],
        source_type: str = "manual_note",
        source_platform: str = "web",
        source_label: str = "",
        source_url: str = "",
        source_context: str = "",
        captured_via: str = "app",
        conversation_id: str = "",
        idempotency_key: str = "",
        created_at: str = "",
        updated_at: str = "",
        deleted_at: str = "";
}


obj MemorySource {
    has `type: str,
        platform: str,
        label: str | None = None,
        url: str | None = None,
        context: str | None = None,
        capturedVia: str = "app",
        conversationId: str | None = None;
}


obj MemoryView {
    has id: str,
        workspaceId: str,
        content: str,
        tags: list[str],
        source: MemorySource,
        createdAt: str,
        updatedAt: str,
        deletedAt: str | None = None;
}


obj MemoryPage {
    has data: list[MemoryView],
        nextCursor: str | None = None,
        total: int = 0;
}


obj SeedItem {
    has key: str,
        content: str,
        tags: list[str],
        source_type: str,
        source_platform: str,
        source_label: str,
        source_url: str = "";
}


obj HealthStatus {
    has ok: bool,
        service: str,
        time: str;
}


def _now_iso -> str {
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    );
}


"""Read a field that newer versions of Sherry added to a node type. Nodes saved
before the field existed don't have it, so fall back to its default. Always
use this for fields added after launch (source_context, context,
captured_via on chats, sent_at)."""
def _field(n: any, name: str, fallback: str) -> str {
    value = getattr(n, name, fallback);
    return str(value) if value is not None else fallback;
}


def _workspace -> Workspace {
    found = [root-->][?:Workspace];
    if len(found) > 0 {
        return found[0];
    }
    return (root ++> Workspace(name="My workspace", created_at=_now_iso()))[0];
}


def _view(m: Memory, ws: Workspace) -> MemoryView {
    return MemoryView(
        id=jid(m),
        workspaceId=jid(ws),
        content=m.content,
        tags=list(m.tags),
        source=MemorySource(
            `type=m.source_type,
            platform=m.source_platform,
            label=m.source_label or None,
            url=m.source_url or None,
            context=_field(m, "source_context", "") or None,
            capturedVia=m.captured_via or "app",
            conversationId=m.conversation_id or None
        ),
        createdAt=m.created_at,
        updatedAt=m.updated_at,
        deletedAt=m.deleted_at or None
    );
}


def _find(ws: Workspace, id: str) -> Memory | None {
    for m in [ws-->][?:Memory] {
        if jid(m) == id {
            return m;
        }
    }
    return None;
}


def _matches(m: Memory, needle: str) -> bool {
    if needle in m.content.lower() {
        return True;
    }
    if needle in m.source_label.lower() or needle in m.source_platform {
        return True;
    }
    if needle in _field(m, "source_context", "").lower() {
        return True;
    }
    for t in m.tags {
        if needle in t.lower() {
            return True;
        }
    }
    return False;
}


def _clean_tags(tags: list[str]) -> list[str] {
    cleaned: list[str] = [];
    for raw in tags {
        t = raw.strip().lstrip("#").lower();
        if not t or t in cleaned {
            continue;
        }
        if len(t) > MAX_TAG_LEN {
            raise ValueError(f"Tags can be at most {MAX_TAG_LEN} characters.");
        }
        cleaned.append(t);
    }
    if len(cleaned) > MAX_TAGS {
        raise ValueError(f"A memory can have at most {MAX_TAGS} tags.");
    }
    return cleaned;
}


def _by_created(m: Memory) -> str {
    return m.created_at;
}


"""Liveness probe. Public so clients can tell 'API down' from 'signed out'."""
def:pub health -> HealthStatus {
    return HealthStatus(ok=True, service="sherry-api", time=_now_iso());
}


"""List active memories, newest first, with optional case-insensitive search
over content, tags, source label and platform. `cursor` is an opaque offset
string returned as `nextCursor` by the previous page. `kind` narrows the list:
"chat" (summaries of captured chats) or "personal" (everything else)."""
def:priv list_memories(
    query: str = "", cursor: str = "", limit: int = 25, kind: str = ""
) -> MemoryPage {
    ws = _workspace();
    needle = query.strip().lower();
    active = [
        m
        for m in [ws-->][?:Memory]
        if not m.deleted_at
    ];
    if needle {
        active = [
            m
            for m in active
            if _matches(m, needle)
        ];
    }
    if kind == "chat" or kind == "personal" {
        active = [
            m
            for m in active
            if bool(_field(m, "conversation_id", "")) == (kind == "chat")
        ];
    }
    active.sort(key=_by_created, reverse=True);
    start = int(cursor) if cursor.isdigit() else 0;
    size = max(1, min(limit, MAX_LIMIT));
    window = active[start:start + size];
    next_cursor = str(start + size) if start + size < len(active) else None;
    return MemoryPage(
        data=[_view(m, ws) for m in window], nextCursor=next_cursor, total=len(active)
    );
}


"""Fetch one active memory with full content and provenance."""
def:priv get_memory(id: str) -> MemoryView | None {
    ws = _workspace();
    m = _find(ws, id);
    if m is None or m.deleted_at {
        return None;
    }
    return _view(m, ws);
}


"""Create a memory. Replaying the same `idempotency_key` returns the memory
created the first time instead of a duplicate (FR-041, AT-03)."""
def:priv create_memory(
    content: str,
    source_platform: str,
    idempotency_key: str,
    tags: list[str] | None = None,
    source_type: str = "manual_note",
    source_label: str = "",
    source_url: str = "",
    captured_via: str = "app",
    source_context: str = ""
) -> MemoryView {
    ws = _workspace();
    key = idempotency_key.strip();
    if len(key) < 16 or len(key) > 128 {
        raise ValueError("idempotency_key must be 16-128 characters.");
    }
    for existing in [ws-->][?:Memory] {
        if existing.idempotency_key == key {
            return _view(existing, ws);
        }
    }
    body = content.strip();
    if not body {
        raise ValueError("Memory content is required.");
    }
    if len(body) > MAX_CONTENT {
        raise ValueError(f"Memory content can be at most {MAX_CONTENT} characters.");
    }
    if source_type not in SOURCE_TYPES {
        raise ValueError(f"Unknown source type '{source_type}'.");
    }
    if source_platform not in SOURCE_PLATFORMS {
        raise ValueError(f"Unknown source platform '{source_platform}'.");
    }
    if captured_via not in CAPTURE_CHANNELS {
        raise ValueError(f"Unknown capture channel '{captured_via}'.");
    }
    label = source_label.strip();
    if len(label) > MAX_LABEL_LEN {
        raise ValueError(f"Source label can be at most {MAX_LABEL_LEN} characters.");
    }
    url = source_url.strip();
    if url and not (url.startswith("https://") or url.startswith("http://")) {
        raise ValueError("Source URL must start with http:// or https://.");
    }
    context = source_context.strip();
    if len(context) > MAX_CONTEXT_LEN {
        raise ValueError(f"Source context can be at most {MAX_CONTEXT_LEN} characters.");
    }
    stamp = _now_iso();
    m = Memory(
        content=body,
        tags=_clean_tags(tags or []),
        source_type=source_type,
        source_platform=source_platform,
        source_label=label,
        source_url=url,
        source_context=context,
        captured_via=captured_via,
        idempotency_key=key,
        created_at=stamp,
        updated_at=stamp
    );
    ws ++> m;
    return _view(m, ws);
}


"""Soft-delete a memory. Returns False when it does not exist."""
def:priv delete_memory(id: str) -> bool {
    ws = _workspace();
    m = _find(ws, id);
    if m is None or m.deleted_at {
        return False;
    }
    stamp = _now_iso();
    m.deleted_at = stamp;
    m.updated_at = stamp;
    if m.conversation_id {
        _forget_conversation(ws, m.conversation_id, True);
    }
    return True;
}


"""Undo a soft delete (backs the 'Undo' action after deleting)."""
def:priv restore_memory(id: str) -> MemoryView | None {
    ws = _workspace();
    m = _find(ws, id);
    if m is None {
        return None;
    }
    m.deleted_at = "";
    m.updated_at = _now_iso();
    if m.conversation_id {
        _forget_conversation(ws, m.conversation_id, False);
    }
    return _view(m, ws);
}


node CapturedConversation {
    has platform: str,
        external_id: str,
        url: str = "",
        title: str = "",
        context: str = "",
        captured_via: str = "extension",
        created_at: str = "",
        updated_at: str = "",
        summarized_hash: str = "",
        summarized_at: str = "",
        summary_engine: str = "",
        summary_note: str = "",
        ignored: bool = False;
}


node CapturedMessage {
    has key: str,
        role: str,
        text: str,
        position: int = 0,
        sent_at: str = "",
        captured_at: str = "",
        updated_at: str = "";
}


"""Deleting a chat summary is a privacy action: the captured transcript is
erased and the chat is ignored from then on. Undo lifts the ignore flag; the
transcript is re-captured the next time the chat is open."""
def _forget_conversation(ws: Workspace, conversation_id: str, forget: bool) {
    for c in [ws-->][?:CapturedConversation] {
        if jid(c) != conversation_id {
            continue;
        }
        c.ignored = forget;
        c.updated_at = _now_iso();
        if forget {
            for msg in [c-->][?:CapturedMessage] {
                del msg;
            }
            c.summarized_hash = "";
        }
    }
}


"""Turn this workspace into the demo workspace: mark it as a demo and add the
sample memories if they are not there yet. Safe to call repeatedly."""
def:priv load_demo_data -> MemoryPage {
    ws = _workspace();
    ws.is_demo = True;
    has_seed = False;
    for m in [ws-->][?:Memory] {
        if m.idempotency_key.startswith("seed-") {
            has_seed = True;
        }
    }
    if not has_seed {
        _seed(ws);
    }
    return list_memories("", "", DEFAULT_LIMIT);
}


"""Wipe a demo workspace and restore the deterministic seed data (FR-061).
Refuses on real workspaces so a stray call can't erase a user's memories."""
def:priv reset_demo -> MemoryPage {
    ws = _workspace();
    if not ws.is_demo {
        raise ValueError("Only the demo workspace can be reset.");
    }
    for m in [ws-->][?:Memory] {
        del m;
    }
    _seed(ws);
    return list_memories("", "", DEFAULT_LIMIT);
}


def _seed(ws: Workspace) {
    base = datetime(2026, 9, 26, 18, 0, 0, tzinfo=timezone.utc);
    for (i, s) in enumerate(SEED) {
        stamp = (base - timedelta(hours=i * 7)).isoformat(
            timespec="milliseconds"
        ).replace(
            "+00:00", "Z"
        );
        ws ++> Memory(
            content=s.content,
            tags=list(s.tags),
            source_type=s.source_type,
            source_platform=s.source_platform,
            source_label=s.source_label,
            source_url=s.source_url,
            idempotency_key=f"seed-{s.key}-0000000000",
            created_at=stamp,
            updated_at=stamp
        );
    }
}


# Deterministic seed data (FR-060). The first entry is the fixture from PLAN.md.
glob SEED: list[SeedItem] = [
         SeedItem(
             key="mem_demo_001",
             content="Use concise weekly project updates.",
             tags=["preference", "writing"],
             source_type="manual_note",
             source_platform="web",
             source_label="Quick capture"
         ),
         SeedItem(
             key="mem_demo_002",
             content="Decision: Sherry stores memories as user-visible saved items, not auto-inferred facts. Keeps the demo trustworthy and every item traceable to a source.",
             tags=["decision", "product"],
             source_type="conversation_excerpt",
             source_platform="claude",
             source_label="Product scoping chat"
         ),
         SeedItem(
             key="mem_demo_003",
             content="I prefer TypeScript strict mode and small, single-purpose pull requests.",
             tags=["preference", "engineering"],
             source_type="manual_note",
             source_platform="desktop",
             source_label="Quick capture"
         ),
         SeedItem(
             key="mem_demo_004",
             content="Research note: spaced repetition works best when review intervals roughly double after each successful recall.",
             tags=["research", "learning"],
             source_type="conversation_excerpt",
             source_platform="chatgpt",
             source_label="Study techniques thread"
         ),
         SeedItem(
             key="mem_demo_005",
             content="Dietary preference: vegetarian, no mushrooms. Mention this when asking for recipes.",
             tags=["preference", "personal"],
             source_type="manual_note",
             source_platform="mobile",
             source_label="Pocket capture"
         ),
         SeedItem(
             key="mem_demo_006",
             content="Gemini suggested structuring the pitch as problem, live demo, then provenance and deletion to show trust.",
             tags=["pitch", "hackathon"],
             source_type="conversation_excerpt",
             source_platform="gemini",
             source_label="Pitch brainstorm"
         ),
         SeedItem(
             key="mem_demo_007",
             content="Imported reading list: 'Designing Data-Intensive Applications' chapters 5 and 9 on replication and consistency.",
             tags=["reading"],
             source_type="import",
             source_platform="web",
             source_label="Bookmarks import",
             source_url="https://dataintensive.net/"
         )
     ];
