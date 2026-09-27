"""Cleaning captured chat text before showing it (UI_OVERHAUL_PRD 2.3).

Desktop logs carry scraper and agent metadata that isn't part of the
conversation: <environment_context> blocks, "Host notice: ... authorization."
lines, "[scraper.err]" markers and "Retained source order: N" lines."""

glob NOISE: list[str] = [
    "<environment_context>[\\s\\S]*?(?:</environment_context>|$)",
    "Host notice:[\\s\\S]*?authorization\\.?",
    "\\[scraper\\.err\\]",
    "Retained source order:\\s*\\d+"
];


def _replace(text: str, pattern: str, flags: str, repl: str) -> str {
    rx: any = new(RegExp, pattern, flags);
    proto: any = String.prototype;
    native: any = proto.replace;
    return str(native.call(text, rx, repl));
}


"""Text without scraper artifacts, with runs of blank lines collapsed."""
def:pub clean_text(text: str) -> str {
    out = text or "";
    for pattern in NOISE {
        out = _replace(out, pattern, "gi", "");
    }
    out = _replace(out, "\\n{3,}", "g", "\n\n");
    return out.strip();
}


"""First non-empty line of the cleaned text, shortened: a title for chats
that have none."""
def:pub first_line(text: str, limit: int) -> str {
    for line in clean_text(text).split("\n") {
        trimmed = line.strip();
        if trimmed {
            return (trimmed[:limit] + "…") if len(trimmed) > limit else trimmed;
        }
    }
    return "";
}
