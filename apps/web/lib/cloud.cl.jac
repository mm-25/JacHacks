"""Calls to Sherry cloud endpoints that only exist on the Cloudflare Worker
(apps/cloud), such as API key management. Everything else goes through the
Jac client runtime's generated calls, which reach the same Worker."""

"""POST /function/<name> on this site with the signed-in user's token.
Returns {ok, result, error}."""
async def:pub call_cloud(name: str, body: dict) -> dict {
    token = str(localStorage.getItem("jac_token") or "");
    headers: dict = {"Content-Type": "application/json"};
    if token {
        headers["Authorization"] = "Bearer " + token;
    }
    response: any = None;
    try {
        response = await fetch(
            "/function/" + name,
            {"method": "POST", "headers": headers, "body": JSON.stringify(body)}
        );
    } except Exception {
        return {"ok": False, "result": None, "error": "Can't reach Sherry. Check your connection."};
    }
    payload: any = None;
    try {
        payload = await response.json();
    } except Exception {
        return {"ok": False, "result": None, "error": f"Sherry answered with HTTP {response.status}."};
    }
    if response.status == 401 {
        return {"ok": False, "result": None, "error": "Your session ended. Sign in again."};
    }
    if not payload or not payload.ok {
        message = payload.error.message if payload and payload.error else "Something went wrong.";
        return {"ok": False, "result": None, "error": str(message)};
    }
    data: any = payload.data or {};
    if data.error {
        return {"ok": False, "result": None, "error": str(data.error)};
    }
    return {"ok": True, "result": data.result, "error": ""};
}
