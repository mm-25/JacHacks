"""Capture API: how whole AI chats get into Sherry.

Two capturers send chats here, with the same shape:
- the browser extension (`captured_via="extension"`): chatgpt.com, claude.ai,
  gemini.google.com;
- the desktop app (`captured_via="desktop"`): local Claude Code, Codex and
  Antigravity session logs.

Each chat becomes one `CapturedConversation` (with its `CapturedMessage`s)
under the user's workspace, plus ONE summary `Memory` that is rewritten as
the chat grows:

    Workspace --> CapturedConversation --> CapturedMessage ...
    Workspace --> Memory (captured_via=<capturer>, conversation_id=<chat>)

Captures are idempotent: messages are keyed by the capturer (the site's
message id, position + role, or the desktop scraper's row id), so re-sending a
chat every few seconds only stores what changed. Summaries only run when the
transcript changed since the last summary. The shared data contract is in
data-schema-specification.md at the repo root.
"""

import hashlib;
import from datetime { datetime }
import from services.memories {
    Workspace,
    Memory,
    MemoryView,
    CapturedConversation,
    CapturedMessage,
    _workspace,
    _view,
    _now_iso,
    _clean_tags,
    _field
}
import from services.summarizer { TranscriptLine, summarize }

glob CAPTURE_PLATFORMS: list[str] = ["chatgpt", "claude", "gemini", "codex", "antigravity"];
glob CAPTURERS: list[str] = ["extension", "desktop"];
glob ROLES: list[str] = ["user", "assistant"];
glob MAX_MESSAGES_PER_CAPTURE: int = 300;
glob MAX_MESSAGE_CHARS: int = 100000;
glob MAX_TITLE_CHARS: int = 200;
glob MAX_CONTEXT_CHARS: int = 200;


obj CaptureResult {
    has conversationId: str,
        received: int,
        added: int,
        updated: int,
        totalMessages: int,
        ignored: bool,
        summaryStale: bool;
}


obj SummaryResult {
    has status: str,
        memory: MemoryView | None = None,
        engine: str = "",
        note: str = "";
}


obj TranscriptMessage {
    has role: str,
        text: str,
        position: int,
        capturedAt: str,
        sentAt: str | None = None;
}


obj ConversationView {
    has id: str,
        platform: str,
        url: str,
        title: str,
        context: str | None,
        capturedVia: str,
        messageCount: int,
        messages: list[TranscriptMessage],
        summarizedAt: str | None = None,
        summaryEngine: str | None = None,
        summaryNote: str | None = None;
}


def _find_conversation(
    ws: Workspace, platform: str, external_id: str
) -> CapturedConversation | None {
    for c in [ws-->][?:CapturedConversation] {
        if c.platform == platform and c.external_id == external_id {
            return c;
        }
    }
    return None;
}


def _by_position(m: CapturedMessage) -> int {
    return m.position;
}


def _ordered(c: CapturedConversation) -> list[CapturedMessage] {
    msgs = [m for m in [c-->][?:CapturedMessage]];
    msgs.sort(key=_by_position);
    return msgs;
}


def _transcript_hash(msgs: list[CapturedMessage]) -> str {
    h = hashlib.sha256();
    for m in msgs {
        h.update(f"{m.key}\x1f{m.role}\x1f{m.text}\x1e".encode("utf-8"));
    }
    return h.hexdigest();
}


"""The original send time of a message as ISO-8601 UTC, or "" when missing or
unparseable (capturers may not know it; Sherry never invents one)."""
def _sent_at(raw: any) -> str {
    text = str(raw or "").strip();
    if not text or len(text) > 40 {
        return "";
    }
    try {
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"));
    } except ValueError {
        return "";
    }
    if parsed.tzinfo is None {
        return "";
    }
    return parsed.isoformat(timespec="milliseconds").replace("+00:00", "Z");
}


def _summary_key(c: CapturedConversation) -> str {
    return f"conv-{c.platform}-{c.external_id}"[:128];
}


"""Store (or update) the messages of one chat. `messages` is a list of
`{key, role, text, position, createdAt?}` objects (`createdAt` = when the
message was originally sent, ISO-8601); unchanged messages are ignored.
`context` is the project or folder a desktop session belongs to."""
def:priv capture_conversation(
    platform: str,
    conversation_id: str,
    url: str = "",
    title: str = "",
    messages: list[dict] | None = None,
    captured_via: str = "extension",
    context: str = ""
) -> CaptureResult {
    if platform not in CAPTURE_PLATFORMS {
        raise ValueError(f"Unknown capture platform '{platform}'.");
    }
    if captured_via not in CAPTURERS {
        raise ValueError(f"Unknown capturer '{captured_via}'.");
    }
    external_id = conversation_id.strip();
    if not external_id or len(external_id) > 200 {
        raise ValueError("conversation_id must be 1-200 characters.");
    }
    link = url.strip();
    if link and not (link.startswith("https://") or link.startswith("http://")) {
        raise ValueError("url must start with http:// or https://.");
    }
    incoming = messages or [];
    if len(incoming) > MAX_MESSAGES_PER_CAPTURE {
        raise ValueError(
            f"Send at most {MAX_MESSAGES_PER_CAPTURE} messages per capture."
        );
    }
    ws = _workspace();
    stamp = _now_iso();
    c = _find_conversation(ws, platform, external_id);
    if c is None {
        c = CapturedConversation(
            platform=platform,
            external_id=external_id,
            url=link,
            title=title.strip()[:MAX_TITLE_CHARS],
            context=context.strip()[:MAX_CONTEXT_CHARS],
            captured_via=captured_via,
            created_at=stamp,
            updated_at=stamp
        );
        ws ++> c;
    }
    if c.ignored {
        return CaptureResult(
            conversationId=jid(c),
            received=len(incoming),
            added=0,
            updated=0,
            totalMessages=0,
            ignored=True,
            summaryStale=False
        );
    }
    if link {
        c.url = link;
    }
    if title.strip() {
        c.title = title.strip()[:MAX_TITLE_CHARS];
    }
    if context.strip() {
        c.context = context.strip()[:MAX_CONTEXT_CHARS];
    }
    existing: dict[str, CapturedMessage] = {};
    for m in [c-->][?:CapturedMessage] {
        existing[m.key] = m;
    }
    added = 0;
    updated = 0;
    for raw in incoming {
        key = str(raw.get("key", "")).strip()[:200];
        role = str(raw.get("role", ""));
        text = str(raw.get("text", "")).strip()[:MAX_MESSAGE_CHARS];
        position = int(raw.get("position", 0));
        sent_at = _sent_at(raw.get("createdAt"));
        if not key or role not in ROLES or not text {
            continue;
        }
        if key in existing {
            old = existing[key];
            if old.text != text or old.role != role or old.position != position {
                old.text = text;
                old.role = role;
                old.position = position;
                old.updated_at = stamp;
                updated += 1;
            }
            if sent_at and not _field(old, "sent_at", "") {
                old.sent_at = sent_at;
            }
            continue;
        }
        fresh = CapturedMessage(
            key=key,
            role=role,
            text=text,
            position=position,
            sent_at=sent_at,
            captured_at=stamp,
            updated_at=stamp
        );
        c ++> fresh;
        existing[key] = fresh;
        added += 1;
    }
    if added > 0 or updated > 0 {
        c.updated_at = stamp;
    }
    ordered = _ordered(c);
    return CaptureResult(
        conversationId=jid(c),
        received=len(incoming),
        added=added,
        updated=updated,
        totalMessages=len(ordered),
        ignored=False,
        summaryStale=len(ordered) > 0 and _transcript_hash(ordered) != c.summarized_hash
    );
}


"""Create or refresh the summary memory of one captured chat. Does nothing
(`status="unchanged"`) when the transcript hasn't changed, unless `force`."""
def:priv summarize_conversation(
    platform: str, conversation_id: str, force: bool = False
) -> SummaryResult {
    ws = _workspace();
    c = _find_conversation(ws, platform, conversation_id.strip());
    if c is None {
        return SummaryResult(status="not_found");
    }
    if c.ignored {
        return SummaryResult(status="ignored");
    }
    ordered = _ordered(c);
    if len(ordered) == 0 {
        return SummaryResult(status="empty");
    }
    key = _summary_key(c);
    existing: Memory | None = None;
    for m in [ws-->][?:Memory] {
        if m.idempotency_key == key {
            existing = m;
        }
    }
    digest = _transcript_hash(ordered);
    if existing is not None and digest == c.summarized_hash and not force {
        current = existing as Memory;
        return SummaryResult(
            status="unchanged",
            memory=_view(current, ws),
            engine=c.summary_engine,
            note=c.summary_note
        );
    }
    result = summarize(
        c.title, [TranscriptLine(role=m.role, text=m.text) for m in ordered]
    );
    stamp = _now_iso();
    status = "updated";
    if existing is None {
        existing = Memory(
            content=result.content,
            tags=_clean_tags(result.tags),
            source_type="conversation_excerpt",
            source_platform=platform,
            source_label=result.title[:120],
            source_url=c.url,
            source_context=_field(c, "context", ""),
            captured_via=_field(c, "captured_via", "extension") or "extension",
            conversation_id=jid(c),
            idempotency_key=key,
            created_at=stamp,
            updated_at=stamp
        );
        ws ++> existing;
        status = "created";
    } else {
        existing.content = result.content;
        existing.tags = _clean_tags(result.tags) or existing.tags;
        existing.source_label = result.title[:120] or existing.source_label;
        existing.source_url = c.url or existing.source_url;
        existing.source_context = _field(c, "context", "") or _field(existing, "source_context", "");
        existing.updated_at = stamp;
    }
    c.summarized_hash = digest;
    c.summarized_at = stamp;
    c.summary_engine = result.engine;
    c.summary_note = result.note;
    return SummaryResult(
        status=status,
        memory=_view(existing, ws),
        engine=result.engine,
        note=result.note
    );
}


"""The captured transcript behind a chat summary (provenance for the web app)."""
def:priv get_conversation(id: str) -> ConversationView | None {
    ws = _workspace();
    for c in [ws-->][?:CapturedConversation] {
        if jid(c) != id {
            continue;
        }
        ordered = _ordered(c);
        return ConversationView(
            id=jid(c),
            platform=c.platform,
            url=c.url,
            title=c.title,
            context=_field(c, "context", "") or None,
            capturedVia=_field(c, "captured_via", "extension") or "extension",
            messageCount=len(ordered),
            messages=[
                TranscriptMessage(
                    role=m.role,
                    text=m.text,
                    position=m.position,
                    capturedAt=m.captured_at,
                    sentAt=_field(m, "sent_at", "") or None
                ) for m in ordered
            ],
            summarizedAt=c.summarized_at or None,
            summaryEngine=c.summary_engine or None,
            summaryNote=c.summary_note or None
        );
    }
    return None;
}
