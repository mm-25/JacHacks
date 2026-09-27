"""Conversation summarizer for captured AI chats.

Uses Claude through the official Anthropic Python SDK when credentials are
available (ANTHROPIC_API_KEY, or any source the SDK resolves). Without them -
or if the call fails - it falls back to a simple extractive summary, so the
capture pipeline and the demo never depend on a paid API call.

Configuration (environment):
    SHERRY_SUMMARY_MODEL   Claude model id (default: claude-opus-5)
    SHERRY_SUMMARY_EFFORT  low | medium | high (default: medium)
    SHERRY_SUMMARIES       set to "off" to always use the basic summary
"""

import os;
import json;
import anthropic;

glob DEFAULT_MODEL: str = "claude-opus-5";
glob MAX_TRANSCRIPT_CHARS: int = 400000;
glob MAX_TAGS: int = 5;

glob SYSTEM_PROMPT: str = (
         "You write entries for Sherry, a personal memory layer that follows the user " + "across AI assistants. You receive one conversation between the user and an " + "AI assistant. Write the memory the user would want to find later: the " + "decisions made, facts and preferences the user stated about themselves or " + "their work, conclusions reached, and open questions or next steps. Skip " + "small talk and the assistant's generic explanations unless the user relied " + "on them. Be specific: keep names, numbers, versions and dates. Write in the " + "same language the user wrote in. Never invent details that are not in the " + "conversation."
     );

glob SUMMARY_SCHEMA: dict = {
         "type": "object",
         "properties": {
             "title": {
                 "type": "string",
                 "description": "Short title for the conversation, at most 80 characters."
             },
             "summary": {
                 "type": "string",
                 "description": "2-5 sentence summary of what matters from this conversation."
             },
             "key_points": {
                 "type": "array",
                 "items": {"type": "string"},
                 "description": "Up to 6 specific decisions, facts, preferences or next steps."
             },
             "tags": {
                 "type": "array",
                 "items": {"type": "string"},
                 "description": "Up to 5 short lowercase topic tags without '#'."
             }
         },
         "required": ["title", "summary", "key_points", "tags"],
         "additionalProperties": False
     };


obj TranscriptLine {
    has role: str,
        text: str;
}


obj ConversationSummary {
    has title: str,
        content: str,
        tags: list[str],
        engine: str,
        model: str = "",
        note: str = "";
}


def _transcript(lines: list[TranscriptLine]) -> tuple[str, bool] {
    parts: list[str] = [];
    for line in lines {
        speaker = "User" if line.role == "user" else "Assistant";
        parts.append(f"{speaker}: {line.text}");
    }
    text = "\n\n".join(parts);
    if len(text) <= MAX_TRANSCRIPT_CHARS {
        return (text, False);
    }
    # Keep the most recent part of very long chats and say so in the prompt.
    return (text[len(text) - MAX_TRANSCRIPT_CHARS:], True);
}


def _clean_tags(raw: list[str]) -> list[str] {
    out: list[str] = [];
    for t in raw {
        tag = t.strip().lstrip("#").lower().replace(" ", "-")[:40];
        if tag and tag not in out {
            out.append(tag);
        }
    }
    return out[:MAX_TAGS];
}


def _basic_summary(
    title: str, lines: list[TranscriptLine], note: str
) -> ConversationSummary {
    user_lines = [
        l.text
        for l in lines
        if l.role == "user"
    ];
    assistant_lines = [
        l.text
        for l in lines
        if l.role != "user"
    ];
    first_ask = user_lines[0] if len(user_lines) > 0 else "";
    last_answer = assistant_lines[-1] if len(assistant_lines) > 0 else "";
    parts: list[str] = [];
    if first_ask {
        parts.append(
            "Asked: " + first_ask[:400] + ("…" if len(first_ask) > 400 else "")
        );
    }
    last_ask = user_lines[-1] if len(user_lines) > 1 else "";
    if last_ask {
        parts.append(
            "Latest ask: " + last_ask[:400] + ("…" if len(last_ask) > 400 else "")
        );
    }
    if last_answer {
        parts.append(
            "Latest answer: " + last_answer[:600] + (
                "…" if len(last_answer) > 600 else ""
            )
        );
    }
    parts.append(
        f"({len(user_lines)} user and {len(
            assistant_lines
        )} assistant messages captured.)"
    );
    return ConversationSummary(
        title=title or (first_ask[:80] if first_ask else "Captured conversation"),
        content="\n\n".join(parts),
        tags=[],
        engine="basic",
        note=note
    );
}


def _claude_summary(title: str, lines: list[TranscriptLine]) -> ConversationSummary {
    model = os.environ.get("SHERRY_SUMMARY_MODEL", DEFAULT_MODEL);
    effort = os.environ.get("SHERRY_SUMMARY_EFFORT", "medium");
    (transcript, truncated) = _transcript(lines);
    header = f"Conversation title: {title or 'untitled'}\n";
    if truncated {
        header += "Note: this conversation is very long; only its most recent part is included below.\n";
    }
    client = anthropic.Anthropic(timeout=120.0);
    response: any = client.beta.messages.create(
        model=model,
        max_tokens=16000,
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        system=SYSTEM_PROMPT,
        output_config={
            "effort": effort,
            "format": {"type": "json_schema", "schema": SUMMARY_SCHEMA}
        },
        messages=[
            {
                "role": "user",
                "content": header + "\n<conversation>\n" + transcript + "\n</conversation>"
            }
        ]
    );
    if response.stop_reason == "refusal" {
        raise ValueError("Claude declined to summarize this conversation.");
    }
    if response.stop_reason == "max_tokens" {
        raise ValueError("Summary was cut off by max_tokens.");
    }
    text = "";
    for block in response.content {
        if block.type == "text" {
            text = str(block.text);
            break;
        }
    }
    data: dict = json.loads(text) as dict;
    points: list[str] = [
        str(p).strip()
        for p in data.get("key_points", [])
        if str(p).strip()
    ];
    body = str(data.get("summary", "")).strip();
    if len(points) > 0 {
        body += "\n\nKey points:\n" + "\n".join(["- " + p for p in points[:6]]);
    }
    return ConversationSummary(
        title=str(data.get("title", "")).strip()[:120] or title,
        content=body,
        tags=_clean_tags([str(t) for t in data.get("tags", [])]),
        engine="claude",
        model=str(response.model)
    );
}


"""Summarize a conversation. Never raises: failures degrade to the basic
summary with a `note` explaining why."""
def summarize(title: str, lines: list[TranscriptLine]) -> ConversationSummary {
    if os.environ.get("SHERRY_SUMMARIES", "") == "off" {
        return _basic_summary(title, lines, "AI summaries are turned off.");
    }
    try {
        return _claude_summary(title, lines);
    } except anthropic.AuthenticationError {
        return _basic_summary(
            title, lines, "No valid Anthropic API key; used a basic summary."
        );
    } except anthropic.RateLimitError {
        return _basic_summary(
            title, lines, "Claude rate limit hit; used a basic summary."
        );
    } except anthropic.APIStatusError as err {
        return _basic_summary(
            title, lines, f"Claude API error {err.status_code}; used a basic summary."
        );
    } except anthropic.APIConnectionError {
        return _basic_summary(
            title, lines, "Couldn't reach Claude; used a basic summary."
        );
    } except TypeError as err {
        # The SDK raises TypeError when it finds no credentials at all.
        if "authentication" in str(err) {
            return _basic_summary(
                title, lines, "No Anthropic API key configured; used a basic summary."
            );
        }
        return _basic_summary(
            title, lines, f"Summary failed ({str(err)[:120]}); used a basic summary."
        );
    } except Exception as err {
        return _basic_summary(
            title, lines, f"Summary failed ({str(err)[:120]}); used a basic summary."
        );
    }
}
