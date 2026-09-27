"""Pure display helpers shared by the Sherry web components."""

glob PLATFORM_LABELS: dict[str, str] = {
         "web": "Web",
         "desktop": "Desktop",
         "mobile": "Mobile",
         "chatgpt": "ChatGPT",
         "claude": "Claude",
         "gemini": "Gemini"
     };

glob TYPE_LABELS: dict[str, str] = {
         "manual_note": "Note",
         "conversation_excerpt": "Conversation excerpt",
         "import": "Import"
     };


def:pub platform_label(platform: str) -> str {
    label = PLATFORM_LABELS[platform];
    return label if label else platform;
}


def:pub type_label(source_type: str) -> str {
    label = TYPE_LABELS[source_type];
    return label if label else source_type;
}


"""'just now', '5m ago', '3h ago', 'Yesterday', or a short date."""
def:pub relative_time(iso: str, now_ms: float) -> str {
    if not iso {
        return "";
    }
    then_ms = new(Date, iso).getTime();
    diff = (now_ms - then_ms) / 1000;
    if diff < 45 {
        return "just now";
    }
    if diff < 3600 {
        return str(Math.max(1, Math.round(diff / 60))) + "m ago";
    }
    if diff < 86400 {
        return str(Math.round(diff / 3600)) + "h ago";
    }
    if diff < 172800 {
        return "Yesterday";
    }
    return new(Date, iso).toLocaleDateString([], {"month": "short", "day": "numeric"});
}


"""Full local timestamp for provenance, e.g. 'Sep 26, 2026, 2:00 PM'."""
def:pub full_time(iso: str) -> str {
    if not iso {
        return "—";
    }
    return new(Date, iso).toLocaleString(
        [],
        {
            "year": "numeric",
            "month": "short",
            "day": "numeric",
            "hour": "numeric",
            "minute": "2-digit"
        }
    );
}


"""Client idempotency key. `crypto.randomUUID` only exists in secure contexts,
so fall back to time + randomness when served over a plain LAN address."""
def:pub new_idempotency_key -> str {
    g: any = globalThis;
    if g.crypto and g.crypto.randomUUID {
        return "web-" + str(g.crypto.randomUUID());
    }
    rand_a = str(Math.random())[2:];
    rand_b = str(Math.random())[2:];
    return "web-" + str(Date.now()) + "-" + rand_a + rand_b;
}


"""Split 'a, #b  c' style input into clean lowercase tags."""
def:pub parse_tags(raw: str) -> list[str] {
    out: list[str] = [];
    for part in raw.replace(",", " ").split(" ") {
        t = part.strip().lstrip("#").lower();
        if t and t not in out {
            out.append(t);
        }
    }
    return out;
}


"""How a memory got into Sherry, for the provenance table."""
def:pub capture_label(via: str) -> str {
    if via == "mcp" {
        return "AI assistant (MCP)";
    }
    if via == "extension" {
        return "Browser extension (auto-captured chat)";
    }
    if via == "import" {
        return "Import";
    }
    return "Sherry app";
}


"""Short list badge for memories that didn't come from typing in Sherry."""
def:pub capture_badge(via: str) -> str {
    if via == "mcp" {
        return "via MCP";
    }
    if via == "extension" {
        return "via extension";
    }
    return "";
}
