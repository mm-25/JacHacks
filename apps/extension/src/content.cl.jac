"""Sherry content script - runs inside chatgpt.com, claude.ai and gemini.google.com.

Watches the open chat and captures every message:
1. A MutationObserver notices page changes (debounced); a 5-second interval
   is the safety net (also catches in-app navigation between chats).
2. While the assistant is still streaming, capture waits.
3. Only new or changed messages are sent (via the background worker).
4. After the chat has been quiet for SUMMARY_IDLE_MS, the background worker
   asks Sherry to (re)summarize it. Sherry skips it if nothing changed.
"""

import from .lib.sites {
    detect_site,
    conversation_id,
    conversation_title,
    conversation_url,
    is_streaming,
    read_messages
}
import from .lib.ext { chrome_api, send_to_background }

glob SCAN_DEBOUNCE_MS: int = 1200;
glob SAFETY_SCAN_MS: int = 5000;
glob SUMMARY_IDLE_MS: int = 20000;
glob BATCH_SIZE: int = 100;

# Module state (not reactive): what has been sent for the open chat.
glob STATE: dict = {
    "site": "",
    "conversation": "",
    "sent": {},
    "scanTimer": None,
    "summaryTimer": None,
    "busy": False,
    "dead": False
};


def schedule_scan(delay: int) {
    if STATE["scanTimer"] {
        clearTimeout(STATE["scanTimer"] as float);
    }
    STATE["scanTimer"] = setTimeout(lambda { scan(); }, delay);
}


def schedule_summary(site: str, conv: str) {
    if STATE["summaryTimer"] {
        clearTimeout(STATE["summaryTimer"] as float);
    }
    STATE["summaryTimer"] = setTimeout(
        lambda { request_summary(site, conv, False); }, SUMMARY_IDLE_MS
    );
}


async def request_summary(site: str, conv: str, force: bool) -> dict {
    if STATE["dead"] {
        return {"ok": False, "error": "Extension was reloaded; refresh this page."};
    }
    try {
        return await send_to_background(
            {"type": "summarize", "platform": site, "conversation_id": conv, "force": force}
        );
    } except Exception {
        STATE["dead"] = True;
        return {"ok": False, "error": "Extension was reloaded; refresh this page."};
    }
}


def changed_messages(messages: list[dict]) -> list[dict] {
    sent: any = STATE["sent"];
    return [m for m in messages if sent[m["key"]] != m["text"]];
}


async def scan -> None {
    if STATE["busy"] or STATE["dead"] {
        return;
    }
    site = detect_site();
    conv = conversation_id(site);
    if not site or not conv {
        return;
    }
    if conv != STATE["conversation"] {
        STATE["conversation"] = conv;
        STATE["site"] = site;
        STATE["sent"] = {};
    }
    if is_streaming(site) {
        schedule_scan(SCAN_DEBOUNCE_MS);
        return;
    }
    pending = changed_messages(read_messages(site));
    if len(pending) == 0 {
        return;
    }
    STATE["busy"] = True;
    try {
        start = 0;
        while start < len(pending) {
            batch = pending[start:start + BATCH_SIZE];
            reply = await send_to_background(
                {
                    "type": "capture",
                    "platform": site,
                    "conversation_id": conv,
                    "url": conversation_url(),
                    "title": conversation_title(site),
                    "messages": batch
                }
            );
            if not reply["ok"] {
                # Leave these unsent; the next scan retries them.
                break;
            }
            sent: any = STATE["sent"];
            for m in batch {
                sent[m["key"]] = m["text"];
            }
            start += BATCH_SIZE;
        }
        if start > 0 {
            schedule_summary(site, conv);
        }
    } except Exception {
        # The extension was reloaded or removed: stop until the page reloads.
        STATE["dead"] = True;
    }
    STATE["busy"] = False;
}


"""Answers the popup: what's on this page, and 'summarize this chat now'."""
async def handle_popup(msg: any) -> dict {
    site = detect_site();
    conv = conversation_id(site);
    kind = str(msg.`type if msg else "");
    if kind == "page-info" {
        return {
            "ok": True,
            "site": site,
            "conversationId": conv,
            "title": conversation_title(site),
            "detected": len(read_messages(site)),
            "streaming": is_streaming(site)
        };
    }
    if kind == "summarize-now" {
        if not site or not conv {
            return {"ok": False, "error": "Open a saved chat first."};
        }
        await scan();
        return await request_summary(site, conv, True);
    }
    return {"ok": False, "error": "Unknown request."};
}


with entry {
    if detect_site() {
        on_change = lambda (records: any) { schedule_scan(SCAN_DEBOUNCE_MS); };
        observer: any = new(MutationObserver, on_change);  # jac:ignore[E1053]
        observer.observe(
            document.body, {"childList": True, "subtree": True, "characterData": True}
        );
        setInterval(lambda { scan(); }, SAFETY_SCAN_MS);
        chrome_api().runtime.onMessage.addListener(
            lambda (msg: any, sender: any, send: any) -> bool {
                pending: any = handle_popup(msg);
                pending.then(lambda (reply: any) { send.call(None, reply); });
                return True;
            }
        );
        schedule_scan(SCAN_DEBOUNCE_MS);
    }
}
