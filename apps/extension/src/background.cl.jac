"""Sherry extension background worker.

Content scripts and the popup send it messages; it is the only part that
talks to the Sherry API (so the API key never touches the AI websites' pages).

Messages:
    {type: "capture", platform, conversation_id, url, title, messages}
    {type: "summarize", platform, conversation_id, force}
    {type: "test"}                      - check URL + key
"""

import from .lib.ext { chrome_api, load_settings, load_status, save_status, now_iso }
import from .lib.api { call_sherry }


async def record(update: dict) -> None {
    current = await load_status();
    await save_status({**current, **update, "updatedAt": now_iso()});
}


async def handle_capture(msg: any) -> dict {
    settings = await load_settings();
    platform = str(msg.platform);
    if settings["paused"] {
        return {"ok": False, "skipped": True, "error": "Capture is paused."};
    }
    if not settings["sites"][platform] {
        return {"ok": False, "skipped": True, "error": "Capture is off for this site."};
    }
    reply = await call_sherry(
        "capture_conversation",
        {
            "platform": platform,
            "conversation_id": msg.conversation_id,
            "url": msg.url,
            "title": msg.title,
            "messages": msg.messages
        }
    );
    if reply["ok"] {
        result: any = reply["result"];
        await record(
            {
                "lastCaptureAt": now_iso(),
                "lastPlatform": platform,
                "lastTitle": msg.title,
                "lastAdded": result.added,
                "lastTotal": result.totalMessages,
                "lastIgnored": result.ignored,
                "lastError": ""
            }
        );
    } else {
        await record({"lastError": reply["error"]});
    }
    return reply;
}


async def handle_summarize(msg: any) -> dict {
    settings = await load_settings();
    if settings["paused"] {
        return {"ok": False, "skipped": True, "error": "Capture is paused."};
    }
    reply = await call_sherry(
        "summarize_conversation",
        {
            "platform": msg.platform,
            "conversation_id": msg.conversation_id,
            "force": bool(msg.force)
        }
    );
    if reply["ok"] {
        result: any = reply["result"];
        await record(
            {
                "lastSummaryAt": now_iso(),
                "lastSummaryStatus": result.status,
                "lastSummaryEngine": result.engine,
                "lastSummaryNote": result.note,
                "lastError": ""
            }
        );
    } else {
        await record({"lastError": reply["error"]});
    }
    return reply;
}


async def handle_test -> dict {
    health = await call_sherry("health", {});
    if not health["ok"] {
        return health;
    }
    return await call_sherry("list_memories", {"query": "", "cursor": "", "limit": 1});
}


async def route(msg: any) -> dict {
    kind = str(msg.`type if msg else "");
    if kind == "capture" {
        return await handle_capture(msg);
    }
    if kind == "summarize" {
        return await handle_summarize(msg);
    }
    if kind == "test" {
        return await handle_test();
    }
    return {"ok": False, "error": "Unknown message type: " + kind};
}


with entry {
    chrome_api().runtime.onMessage.addListener(
        lambda (msg: any, sender: any, send: any) -> bool {
            pending: any = route(msg);
            pending.then(
                lambda (reply: any) { send.call(None, reply); }
            ).catch(
                lambda (err: any) { send.call(None, {"ok": False, "error": str(err)}); }
            );
            # Keep the channel open for the async reply.
            return True;
        }
    );
}
