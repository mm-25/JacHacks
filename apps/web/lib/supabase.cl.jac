"""Sign-in through Supabase Auth (email + password) for the hosted Sherry.

The Sherry API (Cloudflare Worker, apps/cloud) accepts the Supabase access
token. It is stored under `jac_token`, where the Jac client runtime reads it
for every `/function/<name>` call, so the rest of the app is unchanged.
Access tokens last about an hour; `keep_fresh` renews them with the refresh
token shortly before they expire.

Uses Supabase's Auth REST API directly with the project's publishable key,
which is safe to ship in browser code (it only identifies the project).
"""

import from "@jac/runtime" { jacSetToken, jacLogout, __jacClearCache }

glob:pub SUPABASE_URL: str = "https://uddwarzmnyuktwgzvbpd.supabase.co";
glob SUPABASE_KEY: str = "sb_publishable_00WzhaTLVhUsZpIAYg9Ytg_ZwQlMNRp";
glob SESSION_KEY: str = "sherry.session";
glob TOKEN_KEY: str = "jac_token";
glob REFRESH_MARGIN_SECONDS: float = 300.0;


def _now -> float {
    return Date.now() / 1000;
}


def _home -> str {
    return str(window.location.origin);
}


def _encode(text: str) -> str {
    g: any = globalThis;
    return str(g.encodeURIComponent(text));
}


"""POST to Supabase Auth. Returns {ok, status, data}; status 0 = unreachable."""
async def _auth(path: str, body: dict, token: str) -> dict {
    headers: dict = {"Content-Type": "application/json", "apikey": SUPABASE_KEY};
    if token {
        headers["Authorization"] = "Bearer " + token;
    }
    response: any = None;
    try {
        response = await fetch(
            SUPABASE_URL + "/auth/v1/" + path,
            {"method": "POST", "headers": headers, "body": JSON.stringify(body)}
        );
    } except Exception {
        return {"ok": False, "status": 0, "data": {}};
    }
    data: any = {};
    try {
        data = await response.json();
    } except Exception {
        data = {};
    }
    return {"ok": bool(response.ok), "status": int(response.status), "data": data};
}


def _code(res: dict) -> str {
    data: any = res["data"];
    return str(data.error_code or data.error or "");
}


"""A sentence the user can act on, from a failed Supabase Auth reply."""
def _message(res: dict) -> str {
    data: any = res["data"];
    code = _code(res);
    if res["status"] == 0 {
        return "Can't reach the sign-in service. Check your connection and try again.";
    }
    if code == "invalid_credentials" or code == "invalid_grant" {
        return "That email and password don't match.";
    }
    if code == "email_not_confirmed" {
        return "Confirm your email first: open the link we sent you (check spam too).";
    }
    if code == "over_email_send_rate_limit" or res["status"] == 429 {
        return "Too many attempts. Wait a few minutes and try again.";
    }
    if code == "weak_password" {
        return "Choose a stronger password (at least 8 characters, mixing letters and numbers).";
    }
    if code == "email_address_invalid" {
        return "That email address isn't valid.";
    }
    return str(data.msg or data.error_description or data.message or "Something went wrong. Try again.");
}


def _session -> any {
    raw: any = localStorage.getItem(SESSION_KEY);
    if not raw {
        return None;
    }
    try {
        return JSON.parse(raw as str);
    } except Exception {
        return None;
    }
}


def _email_from_token(token: str) -> str {
    parts = token.split(".");
    if len(parts) != 3 {
        return "";
    }
    try {
        b64 = parts[1].replace("-", "+").replace("_", "/");
        while len(b64) % 4 != 0 {
            b64 += "=";
        }
        g: any = globalThis;
        decoded: str = g.atob(b64) as str;
        claims: any = JSON.parse(decoded);
        return str(claims.email or "");
    } except Exception {
        return "";
    }
}


def _store(access_token: str, refresh_token: str, expires_at: float, email: str) {
    localStorage.setItem(
        SESSION_KEY,
        JSON.stringify({"refresh_token": refresh_token, "expires_at": expires_at, "email": email})
    );
    jacSetToken(access_token);
    __jacClearCache();
}


def _store_reply(data: any) {
    access = str(data.access_token);
    expires_in: float = (data.expires_in or 3600) as float;
    expires_at: float = (data.expires_at or (_now() + expires_in)) as float;
    email = str(data.user.email) if data.user and data.user.email else _email_from_token(access);
    _store(access, str(data.refresh_token), expires_at, email);
}


def:pub has_session -> bool {
    return bool(_session()) and bool(localStorage.getItem(TOKEN_KEY));
}


def:pub session_email -> str {
    s: any = _session();
    return str(s.email) if s and s.email else "";
}


async def:pub sign_in(email: str, password: str) -> dict {
    res = await _auth("token?grant_type=password", {"email": email, "password": password}, "");
    if not res["ok"] {
        return {"ok": False, "error": _message(res), "code": _code(res)};
    }
    _store_reply(res["data"]);
    return {"ok": True, "error": "", "code": ""};
}


"""Create an account. With email confirmation on (this project), no session
comes back: the user must open the emailed link, which returns to this site."""
async def:pub sign_up(email: str, password: str) -> dict {
    res = await _auth(
        "signup?redirect_to=" + _encode(_home()), {"email": email, "password": password}, ""
    );
    if not res["ok"] {
        return {"ok": False, "signedIn": False, "error": _message(res)};
    }
    data: any = res["data"];
    if data.access_token {
        _store_reply(data);
        return {"ok": True, "signedIn": True, "error": ""};
    }
    return {"ok": True, "signedIn": False, "error": ""};
}


async def:pub resend_confirmation(email: str) -> dict {
    res = await _auth("resend?redirect_to=" + _encode(_home()), {"type": "signup", "email": email}, "");
    if not res["ok"] {
        return {"ok": False, "error": _message(res)};
    }
    return {"ok": True, "error": ""};
}


"""Renew the access token. False only when the session is gone for good
(refresh token revoked or expired); an unreachable network keeps it."""
async def:pub refresh_session -> bool {
    s: any = _session();
    if not s or not s.refresh_token {
        return False;
    }
    res = await _auth("token?grant_type=refresh_token", {"refresh_token": str(s.refresh_token)}, "");
    if res["ok"] {
        _store_reply(res["data"]);
        return True;
    }
    return res["status"] == 0;
}


"""Renew the token if it expires within five minutes."""
async def:pub keep_fresh -> bool {
    s: any = _session();
    if not s {
        return False;
    }
    expires_at: float = (s.expires_at or 0) as float;
    if expires_at - _now() > REFRESH_MARGIN_SECONDS {
        return True;
    }
    return await refresh_session();
}


async def:pub sign_out -> None {
    token = str(localStorage.getItem(TOKEN_KEY) or "");
    localStorage.removeItem(SESSION_KEY);
    jacLogout();
    if token {
        await _auth("logout", {}, token);
    }
}


"""After the email confirmation link, Supabase sends the user back here with
the session in the URL fragment (#access_token=...). Store it and clean the
address bar. Returns {email} on success, {error} when the link was bad, or {}
when there is nothing to take."""
def:pub take_session_from_url -> dict {
    fragment = str(window.location.hash or "");
    if len(fragment) < 2 {
        return {};
    }
    g: any = globalThis;
    params: any = g.Reflect.construct(g.URLSearchParams, [fragment[1:]]);
    access = str(params.get("access_token") or "");
    problem = str(params.get("error_description") or params.get("error") or "");
    if not access and not problem {
        return {};
    }
    window.history.replaceState(None, "", window.location.pathname + window.location.search);
    if not access {
        return {"error": problem.replace("+", " ")};
    }
    expires_in: float = (Number(params.get("expires_in") or 3600)) as float;
    expires_at: float = (Number(params.get("expires_at") or (_now() + expires_in))) as float;
    email = _email_from_token(access);
    _store(access, str(params.get("refresh_token") or ""), expires_at, email);
    return {"email": email};
}
