"""Tiny async client for the Sherry Jac API (`POST /function/<name>`).

The MCP server never touches Sherry's database: every tool call goes through
the same API the web, mobile and desktop apps use, as the signed-in user."""

import os;
import httpx2 as httpx;

glob SHERRY_API_URL: str = os.environ.get("SHERRY_API_URL", "http://localhost:8000").rstrip("/");


"""POST JSON with a short-lived client. The checker can't see httpx2's lazily
exported types, so the boundary is typed `any` here and nowhere else."""
async def _post(url: str, body: dict, headers: dict, timeout: float) -> any {
    client: any = httpx.AsyncClient(timeout=timeout);
    try {
        return await client.post(url, json=body, headers=headers);
    } finally {
        await client.aclose();
    }
}


obj SherryError(Exception) {
    has message: str = "Sherry request failed.",
        status: int = 0;

    def __str__ -> str {
        return self.message;
    }
}


"""Exchange a Sherry email + password for the account's API token (None if
the credentials are wrong)."""
async def login(email: str, password: str) -> str | None {
    response = await _post(
        SHERRY_API_URL + "/user/login",
        {
            "identity": {"type": "username", "value": email},
            "credential": {"type": "password", "password": password}
        },
        {},
        10.0
    );
    if response.status_code != 200 {
        return None;
    }
    data: dict = (response.json().get("data") or {}) as dict;
    token = data.get("token");
    return str(token) if token else None;
}


"""Call one Sherry endpoint as the user and return its `result`."""
async def call(token: str, name: str, body: dict) -> any {
    response: any = None;
    try {
        response = await _post(
            SHERRY_API_URL + "/function/" + name,
            body,
            {"Authorization": "Bearer " + token},
            60.0
        );
    } except httpx.HTTPError {
        raise SherryError(message="Sherry is unreachable right now. Try again shortly.");
    }
    if response.status_code == 401 {
        raise SherryError(
            message="Your Sherry sign-in is no longer valid. Reconnect Sherry in your assistant's settings.",
            status=401
        );
    }
    payload: dict = {};
    try {
        payload = response.json() as dict;
    } except Exception {
        raise SherryError(message=f"Sherry answered with HTTP {response.status_code}.");
    }
    if not payload.get("ok") {
        err: dict = (payload.get("error") or {}) as dict;
        raise SherryError(message="Sherry error: " + str(err.get("message", "unknown")));
    }
    data: dict = (payload.get("data") or {}) as dict;
    if data.get("error") {
        raise SherryError(message=str(data["error"]));
    }
    return data.get("result");
}


"""Drop Jac wire bookkeeping (`_jac_*` keys) from API results."""
def clean(value: any) -> any {
    if isinstance(value, dict) {
        return {k: clean(v) for (k, v) in value.items() if not str(k).startswith("_jac")};
    }
    if isinstance(value, list) {
        return [clean(v) for v in value];
    }
    return value;
}
