"""Sherry extension popup: connection settings, per-site toggles, status of
the current page, and "Summarize this chat now". Plain DOM (no React)."""

import from .lib.ext {
    chrome_api,
    load_settings,
    save_settings,
    load_status,
    send_to_background,
    DEFAULT_API_URL
}

glob SITE_NAMES: dict[str, str] = {"chatgpt": "ChatGPT", "claude": "Claude"};


def el(id: str) -> any {
    g: any = globalThis;
    return g.document.getElementById(id);
}


def set_text(id: str, text: str, tone: str) {
    target = el(id);
    target.textContent = text;
    target.className = ("small " + tone).strip() if id != "page-info" else tone;
}


def ago(iso: str) -> str {
    if not iso {
        return "";
    }
    seconds = (Date.now() - new(Date, iso).getTime()) / 1000;
    if seconds < 60 {
        return "just now";
    }
    if seconds < 3600 {
        return str(Math.round(seconds / 60)) + " min ago";
    }
    return new(Date, iso).toLocaleString();
}


async def active_tab -> any {
    tabs = (await chrome_api().tabs.query({"active": True, "currentWindow": True})) as list[any];
    return tabs[0] if tabs and len(tabs) > 0 else None;
}


async def ask_page(message: dict) -> dict {
    tab = await active_tab();
    if not tab {
        return {"ok": False, "error": "no-tab"};
    }
    try {
        reply: any = await chrome_api().tabs.sendMessage(tab.id, message);
        if reply {
            return reply as dict;
        }
        return {"ok": False, "error": "no-reply"};
    } except Exception {
        # No content script: not a supported site, or opened before install.
        return {"ok": False, "error": "no-content-script"};
    }
}


async def render_page -> None {
    info = await ask_page({"type": "page-info"});
    button = el("summarize");
    if not info["ok"] {
        set_text(
            "page-info",
            "Open a chat on chatgpt.com or claude.ai. If one is already open, reload it.",
            "muted"
        );
        button.disabled = True;
        return;
    }
    site_name = SITE_NAMES[str(info["site"])] or str(info["site"]);
    if not info["conversationId"] {
        set_text("page-info", site_name + ": start or open a saved chat to capture it.", "muted");
        button.disabled = True;
        return;
    }
    title = str(info["title"] or "Untitled chat");
    detected = int(info["detected"]);
    note = " · assistant is typing" if info["streaming"] else "";
    set_text(
        "page-info",
        f"{site_name} · “{title}” · {detected} messages on this page{note}",
        "" if detected > 0 else "err"
    );
    button.disabled = detected == 0;
}


async def render_status -> None {
    status = await load_status();
    lines: list[str] = [];
    if status["lastCaptureAt"] {
        added = int(status["lastAdded"] or 0);
        total = int(status["lastTotal"] or 0);
        where = SITE_NAMES[str(status["lastPlatform"])] or str(status["lastPlatform"]);
        if status["lastIgnored"] {
            lines.append(f"{where}: this chat's summary was deleted in Sherry, so it isn't captured.");
        } else {
            lines.append(
                f"Captured {added} new message(s) from {where} {ago(str(status['lastCaptureAt']))} · {total} stored for that chat."
            );
        }
    }
    if status["lastSummaryAt"] {
        engine = "Claude" if status["lastSummaryEngine"] == "claude" else "basic";
        lines.append(
            f"Summary {status['lastSummaryStatus']} ({engine}) {ago(str(status['lastSummaryAt']))}."
        );
        if status["lastSummaryNote"] {
            lines.append(str(status["lastSummaryNote"]));
        }
    }
    if status["lastError"] {
        lines.append("Problem: " + str(status["lastError"]));
    }
    set_text(
        "status",
        " ".join(lines) if len(lines) > 0 else "Nothing captured yet.",
        "err" if status["lastError"] else "muted"
    );
}


async def fill_settings -> None {
    settings = await load_settings();
    el("api-url").value = settings["apiUrl"] or DEFAULT_API_URL;
    el("api-key").value = settings["apiKey"] or "";
    el("site-chatgpt").checked = bool(settings["sites"]["chatgpt"]);
    el("site-claude").checked = bool(settings["sites"]["claude"]);
    el("paused").checked = bool(settings["paused"]);
}


async def store_settings -> None {
    await save_settings(
        {
            "apiUrl": str(el("api-url").value).strip() or DEFAULT_API_URL,
            "apiKey": str(el("api-key").value).strip(),
            "paused": bool(el("paused").checked),
            "sites": {
                "chatgpt": bool(el("site-chatgpt").checked),
                "claude": bool(el("site-claude").checked)
            }
        }
    );
}


async def save_and_test -> None {
    set_text("save-result", "Testing…", "muted");
    await store_settings();
    reply = await send_to_background({"type": "test"});
    if reply["ok"] {
        set_text("save-result", "Connected ✓", "ok");
    } else {
        set_text("save-result", str(reply["error"]), "err");
    }
}


async def summarize_now -> None {
    el("summarize").disabled = True;
    set_text("summarize-result", "Summarizing…", "muted");
    reply = await ask_page({"type": "summarize-now"});
    if reply["ok"] {
        result: any = reply["result"];
        engine = "Claude" if result.engine == "claude" else "a basic summary";
        text = f"Done ({result.status}, using {engine}). It's in your Sherry library.";
        if result.note {
            text = text + " " + str(result.note);
        }
        set_text("summarize-result", text, "ok");
    } else {
        set_text("summarize-result", str(reply["error"]), "err");
    }
    el("summarize").disabled = False;
    render_status();
}


with entry {
    fill_settings();
    render_page();
    render_status();
    el("save").addEventListener("click", lambda (e: any) { save_and_test(); });
    el("summarize").addEventListener("click", lambda (e: any) { summarize_now(); });
    for id in ["site-chatgpt", "site-claude", "paused"] {
        el(id).addEventListener("change", lambda (e: any) { store_settings(); });
    }
}
