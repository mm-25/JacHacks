"""Client for the Sherry Jac API (`POST /function/<name>`), used by the
background worker. The API key is the Sherry account token shown in the web
app under "Connect an AI assistant"."""

import from .ext { load_settings }


def _clean_base(url: str) -> str {
    base = url.strip();
    while base.endswith("/") {
        base = base[:len(base) - 1];
    }
    return base;
}


"""Call one Sherry endpoint. Returns {ok, result} or {ok: False, error}."""
async def:pub call_sherry(name: str, body: dict) -> dict {
    settings = await load_settings();
    key = str(settings["apiKey"] or "").strip();
    base = _clean_base(str(settings["apiUrl"] or ""));
    if not base {
        return {"ok": False, "error": "Set the Sherry URL in the extension popup."};
    }
    if not key and name != "health" {
        return {"ok": False, "error": "Add your Sherry API key in the extension popup."};
    }
    headers: dict = {"Content-Type": "application/json"};
    if key {
        headers["Authorization"] = "Bearer " + key;
    }
    response: any = None;
    try {
        response = await fetch(
            base + "/function/" + name,
            {"method": "POST", "headers": headers, "body": JSON.stringify(body)}
        );
    } except Exception {
        return {"ok": False, "error": "Can't reach Sherry at " + base + "."};
    }
    if response.status == 401 {
        return {"ok": False, "error": "Sherry rejected the API key."};
    }
    payload: any = None;
    try {
        payload = await response.json();
    } except Exception {
        return {"ok": False, "error": f"Sherry answered with HTTP {response.status}."};
    }
    if not response.ok or not payload or not payload.ok {
        message = payload.error.message if payload and payload.error else f"HTTP {response.status}";
        return {"ok": False, "error": "Sherry error: " + str(message)};
    }
    data: any = payload.data or {};
    if data.error {
        return {"ok": False, "error": str(data.error)};
    }
    return {"ok": True, "result": data.result};
}
