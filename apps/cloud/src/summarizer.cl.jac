"""Conversation summarizer (port of apps/web/services/summarizer.jac).

Uses Claude through the official Anthropic TypeScript SDK when the Worker has
an ANTHROPIC_API_KEY secret. Without it - or if the call fails - it falls back
to a simple extractive summary, so capture never depends on a paid API call.

Settings (Worker vars/secrets):
    ANTHROPIC_API_KEY      secret; enables Claude summaries
    SHERRY_SUMMARY_MODEL   default claude-opus-5
    SHERRY_SUMMARY_EFFORT  low | medium | high (default medium)
    SHERRY_SUMMARIES       "off" to always use the basic summary
"""

import from "@anthropic-ai/sdk" { default as Anthropic }
import from .util { text_of, construct }

glob DEFAULT_MODEL: str = "claude-opus-5";
glob MAX_TRANSCRIPT_CHARS: int = 400000;
glob MAX_TAGS: int = 5;

glob SYSTEM_PROMPT: str = (
    "You write entries for Sherry, a personal memory layer that follows the user "
    + "across AI assistants. You receive one conversation between the user and an "
    + "AI assistant. Write the memory the user would want to find later: the "
    + "decisions made, facts and preferences the user stated about themselves or "
    + "their work, conclusions reached, and open questions or next steps. Skip "
    + "small talk and the assistant's generic explanations unless the user relied "
    + "on them. Be specific: keep names, numbers, versions and dates. Write in the "
    + "same language the user wrote in. Never invent details that are not in the "
    + "conversation."
);

glob SUMMARY_SCHEMA: dict = {
    "type": "object",
    "properties": {
        "title": {"type": "string", "description": "Short title for the conversation, at most 80 characters."},
        "summary": {"type": "string", "description": "2-5 sentence summary of what matters from this conversation."},
        "key_points": {"type": "array", "items": {"type": "string"}, "description": "Up to 6 specific decisions, facts, preferences or next steps."},
        "tags": {"type": "array", "items": {"type": "string"}, "description": "Up to 5 short lowercase topic tags without '#'."}
    },
    "required": ["title", "summary", "key_points", "tags"],
    "additionalProperties": False
};


def _cut(text: str, limit: int) -> str {
    return text[:limit] + ("…" if len(text) > limit else "");
}


"""{title, content, tags, engine, note} from the transcript alone."""
def:pub basic_summary(title: str, lines: list[dict], note: str) -> dict {
    user_lines: list[str] = [];
    assistant_lines: list[str] = [];
    for line in lines {
        if line["role"] == "user" {
            user_lines.append(str(line["text"]));
        } else {
            assistant_lines.append(str(line["text"]));
        }
    }
    first_ask = user_lines[0] if len(user_lines) > 0 else "";
    last_ask = user_lines[len(user_lines) - 1] if len(user_lines) > 1 else "";
    last_answer = assistant_lines[len(assistant_lines) - 1] if len(assistant_lines) > 0 else "";
    parts: list[str] = [];
    if first_ask {
        parts.append("Asked: " + _cut(first_ask, 400));
    }
    if last_ask {
        parts.append("Latest ask: " + _cut(last_ask, 400));
    }
    if last_answer {
        parts.append("Latest answer: " + _cut(last_answer, 600));
    }
    parts.append(f"({len(user_lines)} user and {len(assistant_lines)} assistant messages captured.)");
    return {
        "title": title or (first_ask[:80] if first_ask else "Captured conversation"),
        "content": "\n\n".join(parts),
        "tags": [],
        "engine": "basic",
        "note": note
    };
}


def _clean_tags(raw: any) -> list[str] {
    out: list[str] = [];
    for item in list(raw or []) {
        tag = text_of(item).strip().lower().replace(" ", "-");
        while tag.startswith("#") {
            tag = tag[1:];
        }
        tag = tag[:40];
        if tag and tag not in out {
            out.append(tag);
        }
    }
    return out[:MAX_TAGS];
}


async def _claude_summary(env: any, title: str, lines: list[dict]) -> dict {
    parts: list[str] = [];
    for line in lines {
        speaker = "User" if line["role"] == "user" else "Assistant";
        parts.append(speaker + ": " + str(line["text"]));
    }
    transcript = "\n\n".join(parts);
    header = "Conversation title: " + (title or "untitled") + "\n";
    if len(transcript) > MAX_TRANSCRIPT_CHARS {
        # Keep the most recent part of very long chats and say so.
        transcript = transcript[len(transcript) - MAX_TRANSCRIPT_CHARS:];
        header += "Note: this conversation is very long; only its most recent part is included below.\n";
    }
    sdk: any = Anthropic;
    reflect: any = Reflect;
    client: any = reflect.construct(sdk, [{"apiKey": text_of(env.ANTHROPIC_API_KEY), "timeout": 120000}]);
    response: any = await client.beta.messages.create(
        {
            "model": text_of(env.SHERRY_SUMMARY_MODEL) or DEFAULT_MODEL,
            "max_tokens": 16000,
            "betas": ["server-side-fallback-2026-07-01"],
            "fallbacks": "default",
            "system": SYSTEM_PROMPT,
            "output_config": {
                "effort": text_of(env.SHERRY_SUMMARY_EFFORT) or "medium",
                "format": {"type": "json_schema", "schema": SUMMARY_SCHEMA}
            },
            "messages": [
                {"role": "user", "content": header + "\n<conversation>\n" + transcript + "\n</conversation>"}
            ]
        }
    );
    if response.stop_reason == "refusal" {
        raise construct("Error", ["Claude declined to summarize this conversation."]) as Exception;
    }
    if response.stop_reason == "max_tokens" {
        raise construct("Error", ["Summary was cut off by max_tokens."]) as Exception;
    }
    text = "";
    for block in list(response.content) {
        b: any = block;
        if b.type == "text" {
            text = text_of(b.text);
            break;
        }
    }
    data: any = JSON.parse(text);
    points: list[str] = [];
    for p in list(data.key_points or []) {
        point = text_of(p).strip();
        if point {
            points.append(point);
        }
    }
    body = text_of(data.summary).strip();
    if len(points) > 0 {
        bullets: list[str] = [];
        for p in points[:6] {
            bullets.append("- " + p);
        }
        body += "\n\nKey points:\n" + "\n".join(bullets);
    }
    return {
        "title": text_of(data.title).strip()[:120] or title,
        "content": body,
        "tags": _clean_tags(data.tags),
        "engine": "claude",
        "note": ""
    };
}


"""`err instanceof Anthropic.<name>` (Jac has no instanceof operator)."""
def _is(err: any, name: str) -> bool {
    sdk: any = Anthropic;
    cls: any = sdk[name];
    return bool(cls) and bool(cls.prototype.isPrototypeOf(err));
}


"""Summarize a conversation. Never raises: failures degrade to the basic
summary with a `note` explaining why."""
async def:pub summarize(env: any, title: str, lines: list[dict]) -> dict {
    if text_of(env.SHERRY_SUMMARIES) == "off" {
        return basic_summary(title, lines, "AI summaries are turned off.");
    }
    if not text_of(env.ANTHROPIC_API_KEY) {
        return basic_summary(title, lines, "No Anthropic API key configured; used a basic summary.");
    }
    try {
        return await _claude_summary(env, title, lines);
    } except Exception as err {
        e: any = err;
        note = "Summary failed; used a basic summary.";
        if _is(e, "AuthenticationError") {
            note = "No valid Anthropic API key; used a basic summary.";
        } elif _is(e, "RateLimitError") {
            note = "Claude rate limit hit; used a basic summary.";
        } elif _is(e, "APIConnectionError") {
            note = "Couldn't reach Claude; used a basic summary.";
        } elif _is(e, "APIError") {
            note = f"Claude API error {e.status}; used a basic summary.";
        } else {
            note = "Summary failed (" + text_of(e.message)[:120] + "); used a basic summary.";
        }
        return basic_summary(title, lines, note);
    }
}
