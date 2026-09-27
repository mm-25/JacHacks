"""Site adapters: how to read a chat on each supported AI website.

Everything site-specific lives here, so when chatgpt.com or claude.ai change
their page structure, this is the only file to update. Each adapter answers:
which conversation is open, is the assistant still typing, and what are the
messages (in order, with a stable key per message).

The selectors below are best-effort and MUST be checked against the live
sites - use the extension popup's "Messages on this page" count to verify.
"""

glob:pub CHATGPT: str = "chatgpt";
glob:pub CLAUDE: str = "claude";

glob CHATGPT_MESSAGE_SELECTOR: str = "[data-message-author-role]";
glob CHATGPT_STOP_SELECTOR: str = "[data-testid='stop-button'], button[aria-label='Stop streaming']";
glob CLAUDE_USER_SELECTOR: str = "[data-testid='user-message']";
glob CLAUDE_ASSISTANT_SELECTOR: str = ".font-claude-response, .font-claude-message";
glob CLAUDE_STREAMING_SELECTOR: str = "[data-is-streaming='true']";
# Text-bearing blocks of a Claude reply. Tool-use strips ("Search Sherry used",
# with an icon-font glyph) are interface controls, not prose, so they're skipped.
glob CLAUDE_PROSE_SELECTOR: str = "p, ul, ol, pre, h1, h2, h3, h4, h5, h6, blockquote, table";
glob CLAUDE_CHROME_SELECTOR: str = "button, [role='button'], summary, details, [aria-hidden='true']";
# Icon fonts render from the Unicode private-use area; never real message text.
glob PRIVATE_USE_PATTERN: str = "[\\uE000-\\uF8FF]";


def _doc -> any {
    g: any = globalThis;
    return g.document;
}


def _location -> any {
    g: any = globalThis;
    return g.location;
}


def _match(pattern: str, text: str) -> str {
    found: any = new(RegExp, pattern).exec(text);
    return str(found[1]) if found else "";
}


def _text_of(el: any) -> str {
    raw: any = el.innerText or el.textContent or "";
    cleaned: any = str(raw).replace(new(RegExp, PRIVATE_USE_PATTERN, "g"), "");
    return str(cleaned).strip();
}


"""True when an ancestor of `el` (not `el` itself) inside `root` matches."""
def _inside(root: any, el: any, selector: str) -> bool {
    parent: any = el.parentElement;
    found: any = parent.closest(selector) if parent else None;
    return bool(found) and bool(root.contains(found));
}


"""A Claude reply's prose only, one block per paragraph; falls back to all
text when the reply has no recognised blocks (e.g. a markup change)."""
def _claude_reply_text(el: any) -> str {
    parts: list[str] = [];
    blocks: list[any] = list(el.querySelectorAll(CLAUDE_PROSE_SELECTOR));
    for block in blocks {
        if _inside(el, block, CLAUDE_PROSE_SELECTOR) {
            continue;
        }
        chrome: any = block.closest(CLAUDE_CHROME_SELECTOR);
        if chrome and el.contains(chrome) {
            continue;
        }
        text = _text_of(block);
        if text {
            parts.append(text);
        }
    }
    return "\n\n".join(parts) if len(parts) > 0 else _text_of(el);
}


"""Which supported site is this tab on ('' when none)."""
def:pub detect_site -> str {
    host = str(_location().hostname);
    if host == "chatgpt.com" or host.endswith(".chatgpt.com") or host == "chat.openai.com" {
        return CHATGPT;
    }
    if host == "claude.ai" or host.endswith(".claude.ai") {
        return CLAUDE;
    }
    return "";
}


"""The site's id for the open chat ('' on a new, not-yet-saved chat)."""
def:pub conversation_id(site: str) -> str {
    path = str(_location().pathname);
    if site == CHATGPT {
        return _match("/c/([A-Za-z0-9-]+)", path);
    }
    if site == CLAUDE {
        return _match("/chat/([A-Za-z0-9-]+)", path);
    }
    return "";
}


def:pub conversation_title(site: str) -> str {
    title = str(_doc().title or "").strip();
    for suffix in [" - Claude", " | Claude", " - ChatGPT", " | ChatGPT"] {
        if title.endswith(suffix) {
            title = title[:len(title) - len(suffix)].strip();
        }
    }
    if title == "ChatGPT" or title == "Claude" {
        return "";
    }
    return title;
}


def:pub conversation_url -> str {
    loc = _location();
    return str(loc.origin) + str(loc.pathname);
}


"""True while the assistant is still generating - capture waits for it."""
def:pub is_streaming(site: str) -> bool {
    doc = _doc();
    if site == CHATGPT {
        return bool(doc.querySelector(CHATGPT_STOP_SELECTOR));
    }
    if site == CLAUDE {
        return bool(doc.querySelector(CLAUDE_STREAMING_SELECTOR));
    }
    return False;
}


def _chatgpt_messages -> list[dict] {
    out: list[dict] = [];
    nodes: list[any] = list(_doc().querySelectorAll(CHATGPT_MESSAGE_SELECTOR));
    position = 0;
    for el in nodes {
        role = str(el.getAttribute("data-message-author-role") or "");
        if role != "user" and role != "assistant" {
            continue;
        }
        text = _text_of(el);
        if not text {
            continue;
        }
        msg_id = str(el.getAttribute("data-message-id") or "");
        key = msg_id if msg_id else f"{position}-{role}";
        out.append({"key": key, "role": role, "text": text, "position": position});
        position += 1;
    }
    return out;
}


def _claude_messages -> list[dict] {
    out: list[dict] = [];
    selector = CLAUDE_USER_SELECTOR + ", " + CLAUDE_ASSISTANT_SELECTOR;
    nodes: list[any] = list(_doc().querySelectorAll(selector));
    position = 0;
    for el in nodes {
        # Skip matches nested inside another match (querySelectorAll is in
        # document order, so outer containers come first).
        parent: any = el.parentElement;
        if parent and parent.closest(selector) {
            continue;
        }
        role = "user" if el.matches(CLAUDE_USER_SELECTOR) else "assistant";
        text = _text_of(el) if role == "user" else _claude_reply_text(el);
        if not text {
            continue;
        }
        # claude.ai exposes no message ids; position + role is stable for a chat.
        out.append(
            {"key": f"{position}-{role}", "role": role, "text": text, "position": position}
        );
        position += 1;
    }
    return out;
}


"""All messages of the open chat, oldest first: {key, role, text, position}."""
def:pub read_messages(site: str) -> list[dict] {
    if site == CHATGPT {
        return _chatgpt_messages();
    }
    if site == CLAUDE {
        return _claude_messages();
    }
    return [];
}
