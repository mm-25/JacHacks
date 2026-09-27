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
glob:pub GEMINI: str = "gemini";

glob CHATGPT_MESSAGE_SELECTOR: str = "[data-message-author-role]";
glob CHATGPT_STOP_SELECTOR: str = "[data-testid='stop-button'], button[aria-label='Stop streaming']";
glob CLAUDE_USER_SELECTOR: str = "[data-testid='user-message']";
glob CLAUDE_ASSISTANT_SELECTOR: str = ".font-claude-response, .font-claude-message";
glob CLAUDE_STREAMING_SELECTOR: str = "[data-is-streaming='true']";
# gemini.google.com renders each turn as <user-query> + <model-response> custom
# elements. The reply text is in <message-content>; the optional "Show thinking"
# panel sits outside it, so it's never captured.
glob GEMINI_TURN_SELECTOR: str = "user-query, model-response";
glob GEMINI_USER_TEXT_SELECTOR: str = ".query-text";
glob GEMINI_REPLY_SELECTOR: str = "message-content";
glob GEMINI_STREAMING_SELECTOR: str = "button.send-button.stop, button[aria-label='Stop response'], model-response [aria-busy='true']";
# Text-bearing blocks of an assistant reply (Claude, Gemini). Tool-use strips ("Search Sherry used",
# with an icon-font glyph) are interface controls, not prose, so they're skipped.
glob PROSE_SELECTOR: str = "p, ul, ol, pre, h1, h2, h3, h4, h5, h6, blockquote, table";
glob CHROME_SELECTOR: str = "button, [role='button'], summary, details, [aria-hidden='true']";
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
    js_text: any = String(raw);
    cleaned: any = js_text.replace(new(RegExp, PRIVATE_USE_PATTERN, "g"), "");
    return str(cleaned).strip();
}


"""True when an ancestor of `el` (not `el` itself) inside `container` matches."""
def _inside(container: any, el: any, selector: str) -> bool {
    parent: any = el.parentElement;
    found: any = parent.closest(selector) if parent else None;
    return bool(found) and bool(container.contains(found));
}


"""An assistant reply's prose only, one block per paragraph; falls back to all
text when the reply has no recognised blocks (e.g. a markup change)."""
def _reply_text(el: any) -> str {
    parts: list[str] = [];
    blocks: list[any] = list(el.querySelectorAll(PROSE_SELECTOR));
    for block in blocks {
        if _inside(el, block, PROSE_SELECTOR) {
            continue;
        }
        chrome: any = block.closest(CHROME_SELECTOR);
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
    if host == "gemini.google.com" {
        return GEMINI;
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
    if site == GEMINI {
        # /app/<id>, /u/1/app/<id> (second account), /gem/<gem>/<id>
        return _match("/(?:app|gem/[^/]+)/([A-Za-z0-9_-]+)", path);
    }
    return "";
}


def:pub conversation_title(site: str) -> str {
    title = str(_doc().title or "").strip();
    for suffix in [" - Claude", " | Claude", " - ChatGPT", " | ChatGPT", " - Gemini", " | Gemini"] {
        if title.endswith(suffix) {
            title = title[:len(title) - len(suffix)].strip();
        }
    }
    if title == "ChatGPT" or title == "Claude" or title == "Gemini" or title == "Google Gemini" {
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
    if site == GEMINI {
        return bool(doc.querySelector(GEMINI_STREAMING_SELECTOR));
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
        text = _text_of(el) if role == "user" else _reply_text(el);
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


def _gemini_messages -> list[dict] {
    out: list[dict] = [];
    nodes: list[any] = list(_doc().querySelectorAll(GEMINI_TURN_SELECTOR));
    position = 0;
    for el in nodes {
        role = "user" if str(el.tagName).lower() == "user-query" else "assistant";
        text = "";
        if role == "user" {
            query: any = el.querySelector(GEMINI_USER_TEXT_SELECTOR);
            text = _text_of(query) if query else _text_of(el);
        } else {
            reply: any = el.querySelector(GEMINI_REPLY_SELECTOR);
            text = _reply_text(reply) if reply else "";
        }
        if not text {
            continue;
        }
        # Gemini exposes no stable per-message id either; position + role is
        # stable for a chat, like claude.ai.
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
    if site == GEMINI {
        return _gemini_messages();
    }
    return [];
}
