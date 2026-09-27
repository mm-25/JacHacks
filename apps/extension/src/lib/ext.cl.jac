"""Typed wrappers over the Chrome extension APIs used by Sherry.

`chrome.*` is not known to the Jac type checker, so it is reached through an
`any`-typed handle here and nowhere else."""

glob:pub SETTINGS_KEY: str = "sherry.settings";
glob:pub STATUS_KEY: str = "sherry.status";
glob:pub DEFAULT_API_URL: str = "http://localhost:8000";


def:pub chrome_api -> any {
    g: any = globalThis;
    return g.chrome;
}


def:pub default_settings -> dict {
    return {
        "apiUrl": DEFAULT_API_URL,
        "apiKey": "",
        "paused": False,
        "sites": {"chatgpt": True, "claude": True}
    };
}


async def:pub load_settings -> dict {
    stored: any = await chrome_api().storage.local.get(SETTINGS_KEY);
    saved: any = stored[SETTINGS_KEY] if stored else None;
    base = default_settings();
    if not saved {
        return base;
    }
    return {
        **base,
        **saved,
        "sites": {**base["sites"], **(saved["sites"] or {})}
    };
}


async def:pub save_settings(settings: dict) -> None {
    payload: dict = {};
    payload[SETTINGS_KEY] = settings;
    await chrome_api().storage.local.set(payload);
}


async def:pub load_status -> dict {
    stored: any = await chrome_api().storage.local.get(STATUS_KEY);
    saved: any = stored[STATUS_KEY] if stored else None;
    if saved {
        return saved as dict;
    }
    return {};
}


async def:pub save_status(status: dict) -> None {
    payload: dict = {};
    payload[STATUS_KEY] = status;
    await chrome_api().storage.local.set(payload);
}


"""Send a message to the background worker; resolves to its reply."""
async def:pub send_to_background(message: dict) -> dict {
    reply: any = await chrome_api().runtime.sendMessage(message);
    if reply {
        return reply as dict;
    }
    return {"ok": False, "error": "No reply from the Sherry extension."};
}


def:pub now_iso -> str {
    return new(Date).toISOString();
}
