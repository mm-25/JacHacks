"""OAuth 2.1 authorization server for the Sherry MCP connector (port of
apps/mcp/oauth.jac to the Worker).

claude.ai, ChatGPT and Gemini register themselves (Dynamic Client
Registration), send the user to Sherry's sign-in page, and exchange the
resulting one-time code (PKCE S256) for tokens. The sign-in page checks the
email and password with Supabase Auth, so a connector acts as that Supabase
user. Codes and tokens are stored hashed in D1; refreshing rotates the whole
token family.

Endpoints: /.well-known/oauth-protected-resource[/mcp],
/.well-known/oauth-authorization-server, /register, /authorize (the sign-in
page, GET + POST), /token, /revoke.
"""

import from .util {
    construct,
    now_iso,
    now_seconds,
    new_id,
    random_token,
    sha256_hex,
    utf8,
    text_of,
    query_one,
    execute,
    statement,
    is_plain_object
}
import from .auth { Principal }

glob:pub SCOPE: str = "sherry.memories";
glob ACCESS_TTL: float = 8.0 * 3600;
glob REFRESH_TTL: float = 30.0 * 24 * 3600;
glob CODE_TTL: float = 300.0;
glob REQUEST_TTL: float = 900.0;
glob ACCESS_PREFIX: str = "shm_";
glob REFRESH_PREFIX: str = "shm_rt_";
glob CORS: dict = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, content-type, mcp-protocol-version"
};


obj:pub McpCaller {
    has userId: str,
        email: str,
        clientId: str,
        clientName: str;
}


# ---------- responses ----------

def _json(payload: any, status: int, extra: dict) -> any {
    headers: dict = {**CORS, "Content-Type": "application/json", "Cache-Control": "no-store", **extra};
    return construct("Response", [JSON.stringify(payload), {"status": status, "headers": headers}]);
}


def _oauth_error(status: int, code: str, description: str) -> any {
    return _json({"error": code, "error_description": description}, status, {});
}


def _redirect(location: str) -> any {
    return construct("Response", [None, {"status": 302, "headers": {"Location": location, "Cache-Control": "no-store"}}]);
}


def:pub base_url(request: any) -> str {
    url: any = construct("URL", [request.url]);
    return text_of(url.origin);
}


def:pub resource_url(request: any) -> str {
    return base_url(request) + "/mcp";
}


"""The MCP resource the client named is this server (trailing slash allowed)."""
def _is_our_resource(request: any, resource: str) -> bool {
    trimmed = resource;
    while trimmed.endswith("/") {
        trimmed = trimmed[:len(trimmed) - 1];
    }
    return trimmed == resource_url(request) or trimmed == base_url(request);
}


def _with_params(target: str, params: dict) -> str {
    url: any = construct("URL", [target]);
    for key in Object.keys(params) {
        value = text_of(params[key]);
        if value {
            url.searchParams.set(key, value);
        }
    }
    return text_of(url.toString());
}


async def _pkce_ok(verifier: str, challenge: str) -> bool {
    g: any = globalThis;
    digest: any = await g.crypto.subtle.digest("SHA-256", utf8(verifier));
    binary = "";
    for b in list(construct("Uint8Array", [digest])) {
        binary += String.fromCharCode(b);
    }
    encoded: any = btoa(binary);
    computed = text_of(encoded.replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", ""));
    return len(verifier) >= 43 and computed == challenge;
}


"""Request parameters from a form, JSON or query body."""
async def _body_params(request: any) -> any {
    kind = text_of(request.headers.get("Content-Type")).lower();
    if "application/json" in kind {
        try {
            parsed: any = await request.json();
            return parsed if is_plain_object(parsed) else {};
        } except Exception {
            return {};
        }
    }
    try {
        form: any = await request.formData();
        out: any = {};
        form.forEach(lambda (value: any, key: any) { out[key] = value; });
        return out;
    } except Exception {
        return {};
    }
}


# ---------- metadata ----------

def:pub protected_resource_metadata(request: any) -> any {
    base = base_url(request);
    return _json(
        {
            "resource": base + "/mcp",
            "authorization_servers": [base],
            "scopes_supported": [SCOPE],
            "bearer_methods_supported": ["header"],
            "resource_name": "Sherry memory"
        },
        200,
        {}
    );
}


def:pub authorization_server_metadata(request: any) -> any {
    base = base_url(request);
    return _json(
        {
            "issuer": base,
            "authorization_endpoint": base + "/authorize",
            "token_endpoint": base + "/token",
            "registration_endpoint": base + "/register",
            "revocation_endpoint": base + "/revoke",
            "response_types_supported": ["code"],
            "grant_types_supported": ["authorization_code", "refresh_token"],
            "code_challenge_methods_supported": ["S256"],
            "token_endpoint_auth_methods_supported": ["none", "client_secret_post", "client_secret_basic"],
            "revocation_endpoint_auth_methods_supported": ["none", "client_secret_post", "client_secret_basic"],
            "scopes_supported": [SCOPE]
        },
        200,
        {}
    );
}


# ---------- client registration (RFC 7591) ----------

async def:pub register_client(request: any, env: any) -> any {
    meta: any = await _body_params(request);
    uris: list = list(meta.redirect_uris or []) if Array.isArray(meta.redirect_uris) else [];
    if len(uris) == 0 {
        return _oauth_error(400, "invalid_redirect_uri", "redirect_uris is required.");
    }
    for uri in uris {
        u = text_of(uri);
        local = u.startswith("http://localhost") or u.startswith("http://127.0.0.1");
        if not (u.startswith("https://") or local) {
            return _oauth_error(400, "invalid_redirect_uri", "Redirect URIs must use https.");
        }
    }
    method = text_of(meta.token_endpoint_auth_method) or "client_secret_basic";
    if method not in ["none", "client_secret_post", "client_secret_basic"] {
        return _oauth_error(400, "invalid_client_metadata", "Unsupported token_endpoint_auth_method.");
    }
    client_id = new_id();
    secret = "" if method == "none" else random_token(32);
    secret_hash = await sha256_hex(secret) if secret else "";
    name = text_of(meta.client_name).strip()[:120];
    issued = int(now_seconds());
    await execute(
        env,
        "INSERT INTO oauth_clients (client_id, client_secret_hash, client_name, redirect_uris, auth_method, metadata, created_at) "
        + "VALUES (?, ?, ?, ?, ?, ?, ?)",
        [client_id, secret_hash, name, JSON.stringify(uris), method, JSON.stringify(meta), now_iso()]
    );
    reply: dict = {
        "client_id": client_id,
        "client_id_issued_at": issued,
        "client_name": name,
        "redirect_uris": uris,
        "token_endpoint_auth_method": method,
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "scope": SCOPE
    };
    if secret {
        reply["client_secret"] = secret;
        reply["client_secret_expires_at"] = 0;
    }
    return _json(reply, 201, {});
}


async def _client(env: any, client_id: str) -> any {
    return await query_one(env, "SELECT * FROM oauth_clients WHERE client_id = ?", [client_id]);
}


def _client_uris(client: any) -> list {
    try {
        return list(JSON.parse(text_of(client.redirect_uris)));
    } except Exception {
        return [];
    }
}


"""Check the client's credentials on /token and /revoke."""
async def _client_authenticated(request: any, client: any, params: any) -> bool {
    method = text_of(client.auth_method);
    if method == "none" {
        return True;
    }
    secret = text_of(params.client_secret);
    header = text_of(request.headers.get("Authorization"));
    if header.startswith("Basic ") {
        try {
            decoded = text_of(atob(header[6:].strip()));
            pieces = decoded.split(":");
            if len(pieces) >= 2 {
                g: any = globalThis;
                secret = text_of(g.decodeURIComponent(":".join(pieces[1:])));
            }
        } except Exception {
            return False;
        }
    }
    return bool(secret) and (await sha256_hex(secret)) == text_of(client.client_secret_hash);
}


# ---------- authorize: the sign-in page ----------

glob PAGE_CSS: str = """
@import url("https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600&display=swap");
:root{--canvas:#fff;--canvas-soft-2:#f5f5f5;--hairline:#ebebeb;--hairline-strong:#a1a1a1;--ink:#171717;--body:#4d4d4d;--mute:#888;--primary:#171717;--primary-hover:#383838;--on-primary:#fff;--danger-deep:#c50000;--danger-soft:#f7d4d6;--focus:#0070f3;--link:#0070f3;--ring:0 0 0 1px rgba(0,0,0,.08);--mesh-opacity:.55;color-scheme:light}
@media (prefers-color-scheme:dark){:root{--canvas:#0a0a0a;--canvas-soft-2:#1a1a1a;--hairline:#2e2e2e;--hairline-strong:#5c5c5c;--ink:#ededed;--body:#a1a1a1;--mute:#7a7a7a;--primary:#ededed;--primary-hover:#cfcfcf;--on-primary:#0a0a0a;--danger-deep:#ff8a8e;--danger-soft:#3c1618;--focus:#52a8ff;--link:#52a8ff;--ring:0 0 0 1px rgba(255,255,255,.1);--mesh-opacity:.38;color-scheme:dark}}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:grid;place-items:center;padding:64px 16px;background:var(--canvas);color:var(--ink);font:15px/1.55 "Geist","Inter",ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;-webkit-font-smoothing:antialiased;position:relative;isolation:isolate;overflow-x:hidden}
body::before{content:"";position:absolute;z-index:-1;left:50%;top:-12%;width:min(1100px,150vw);height:70%;transform:translateX(-50%);background:radial-gradient(38% 55% at 18% 45%,#007cf0,transparent 70%),radial-gradient(30% 50% at 34% 70%,#00dfd8,transparent 70%),radial-gradient(34% 55% at 52% 35%,#7928ca,transparent 70%),radial-gradient(30% 50% at 66% 62%,#ff0080,transparent 70%),radial-gradient(32% 55% at 80% 40%,#ff4d4d,transparent 70%),radial-gradient(28% 45% at 90% 68%,#f9cb28,transparent 70%);filter:blur(60px) saturate(1.1);opacity:var(--mesh-opacity);pointer-events:none}
body::after{content:"";position:absolute;inset:0;z-index:-1;background:linear-gradient(to bottom,transparent 0%,transparent 35%,var(--canvas) 78%);pointer-events:none}
.card{width:100%;max-width:420px;background:var(--canvas);border-radius:12px;padding:32px;box-shadow:0 1px 1px rgba(0,0,0,.02),0 8px 16px -4px rgba(0,0,0,.04),0 24px 32px -8px rgba(0,0,0,.06),var(--ring)}
.brand{display:flex;align-items:center;gap:10px;margin-bottom:24px}
.logo{width:32px;height:32px;border-radius:6px;background:var(--primary);color:var(--on-primary);display:grid;place-items:center;font-weight:600;font-size:17px;letter-spacing:-.6px}
.wordmark{font-size:20px;line-height:28px;font-weight:600;letter-spacing:-.6px}
h1{font-size:32px;line-height:40px;font-weight:600;letter-spacing:-1.28px;margin:0 0 12px}
p{margin:0 0 16px;color:var(--body)}
a{color:var(--link);text-decoration:none}a:hover{text-decoration:underline}
.who{background:var(--canvas-soft-2);border-radius:8px;padding:12px 14px;margin-bottom:16px;font-size:14px;line-height:20px;color:var(--body)}.who b{color:var(--ink);font-weight:500}
label{display:block;font-size:13px;font-weight:500;color:var(--body);margin:12px 0 6px}
input{width:100%;height:40px;padding:0 12px;border-radius:6px;border:1px solid var(--hairline);background:var(--canvas);color:var(--ink);font:inherit;font-size:14px}
input:hover{border-color:var(--hairline-strong)}
input:focus{outline:none;border-color:var(--hairline-strong);box-shadow:0 0 0 3px color-mix(in srgb,var(--focus) 18%,transparent)}
.row{display:flex;gap:12px;margin-top:24px}
button{flex:1;min-height:44px;border-radius:100px;font-family:inherit;font-size:16px;line-height:24px;font-weight:500;cursor:pointer;border:none;background:var(--canvas);color:var(--ink);box-shadow:var(--ring)}
button:hover{background:var(--canvas-soft-2)}
button.primary{background:var(--primary);color:var(--on-primary);box-shadow:none}button.primary:hover{background:var(--primary-hover)}
button:focus-visible{outline:2px solid var(--focus);outline-offset:2px}
.error{background:var(--danger-soft);color:var(--danger-deep);border-radius:6px;padding:10px 12px;font-size:14px;line-height:20px;margin-bottom:8px}
.small{font-size:12px;line-height:16px;color:var(--mute);margin-top:16px;margin-bottom:0}
""";


def _escape(text: str) -> str {
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#x27;");
}


def _page(body: str, status: int) -> any {
    html = (
        "<!doctype html><html lang='en'><head><meta charset='utf-8'>"
        + "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        + "<title>Connect Sherry</title><style>" + PAGE_CSS + "</style></head><body>"
        + "<main class='card'><div class='brand'><div class='logo' aria-hidden='true'>S</div>"
        + "<span class='wordmark'>Sherry</span></div>" + body + "</main></body></html>"
    );
    return construct(
        "Response",
        [html, {"status": status, "headers": {"Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "X-Frame-Options": "DENY"}}]
    );
}


def _problem_page(title: str, message: str) -> any {
    return _page("<h1>" + _escape(title) + "</h1><p>" + _escape(message) + "</p>", 400);
}


def _form_page(request: any, request_id: str, client_name: str, redirect_uri: str, error: str, email: str) -> any {
    host = "";
    try {
        u: any = construct("URL", [redirect_uri]);
        host = text_of(u.hostname);
    } except Exception {
        host = redirect_uri;
    }
    error_html = "<div class='error' role='alert'>" + _escape(error) + "</div>" if error else "";
    return _page(
        "<h1>Connect your memory.</h1>"
        + "<div class='who'><b>" + _escape(client_name or "An AI assistant") + "</b> wants to save and search your Sherry memories."
        + "<br>After signing in you'll be sent back to <b>" + _escape(host) + "</b>.</div>"
        + error_html
        + "<form method='post' action='/authorize'>"
        + "<input type='hidden' name='request' value='" + _escape(request_id) + "'>"
        + "<label for='email'>Sherry email</label>"
        + "<input id='email' name='email' type='email' autocomplete='email' required value='" + _escape(email) + "'>"
        + "<label for='password'>Password</label>"
        + "<input id='password' name='password' type='password' autocomplete='current-password' required>"
        + "<div class='row'><button type='submit' name='action' value='deny' formnovalidate>Cancel</button>"
        + "<button class='primary' type='submit' name='action' value='allow'>Allow access</button></div>"
        + "</form><p class='small'>No account yet? <a href='" + _escape(base_url(request)) + "' target='_blank' rel='noopener'>Create one on Sherry</a>, then come back. "
        + "You can disconnect any time from your assistant's connector settings.</p>",
        200
    );
}


"""GET /authorize: validate the request, remember it, show the sign-in page."""
async def:pub authorize_start(request: any, env: any) -> any {
    url: any = construct("URL", [request.url]);
    q: any = url.searchParams;
    client_id = text_of(q.get("client_id"));
    client: any = await _client(env, client_id);
    if not client {
        console.log("sherry oauth: authorize rejected, unknown client " + client_id);
        return _problem_page("Unknown app.", "This connection request came from an app Sherry doesn't know. Try connecting again from your assistant.");
    }
    uris = _client_uris(client);
    redirect_uri = text_of(q.get("redirect_uri"));
    if not redirect_uri and len(uris) == 1 {
        redirect_uri = text_of(uris[0]);
    }
    if redirect_uri not in uris {
        console.log("sherry oauth: authorize rejected, redirect_uri not registered: " + redirect_uri);
        return _problem_page("Invalid redirect.", "The app asked to return to an address it didn't register.");
    }
    state = text_of(q.get("state"));
    if text_of(q.get("response_type")) != "code" {
        return _redirect(_with_params(redirect_uri, {"error": "unsupported_response_type", "state": state}));
    }
    challenge = text_of(q.get("code_challenge"));
    if not challenge or text_of(q.get("code_challenge_method")) != "S256" {
        console.log("sherry oauth: authorize rejected, no S256 PKCE");
        return _redirect(_with_params(redirect_uri, {"error": "invalid_request", "error_description": "PKCE with S256 is required.", "state": state}));
    }
    resource = text_of(q.get("resource"));
    if resource and not _is_our_resource(request, resource) {
        console.log("sherry oauth: authorize rejected, unknown resource " + resource);
        return _redirect(_with_params(redirect_uri, {"error": "invalid_target", "state": state}));
    }
    request_id = random_token(24);
    await execute(
        env,
        "INSERT INTO oauth_requests (id, client_id, params, created_at) VALUES (?, ?, ?, ?)",
        [
            request_id,
            client_id,
            JSON.stringify({"redirect_uri": redirect_uri, "state": state, "code_challenge": challenge, "scope": text_of(q.get("scope")) or SCOPE, "resource": resource}),
            now_seconds()
        ]
    );
    # Housekeeping: drop stale requests and codes.
    await execute(env, "DELETE FROM oauth_requests WHERE created_at < ?", [now_seconds() - REQUEST_TTL]);
    await execute(env, "DELETE FROM oauth_codes WHERE expires_at < ?", [now_seconds()]);
    return _form_page(request, request_id, text_of(client.client_name), redirect_uri, "", "");
}


"""Email + password checked with Supabase Auth. Returns {userId, email} or {error}."""
async def _supabase_sign_in(env: any, email: str, password: str) -> dict {
    base = text_of(env.SUPABASE_URL);
    key = text_of(env.SUPABASE_PUBLISHABLE_KEY);
    if not base or not key {
        return {"error": "Sign-in isn't configured on this Sherry server."};
    }
    response: any = None;
    try {
        response = await fetch(
            base + "/auth/v1/token?grant_type=password",
            {"method": "POST", "headers": {"Content-Type": "application/json", "apikey": key}, "body": JSON.stringify({"email": email, "password": password})}
        );
    } except Exception {
        return {"error": "Can't reach the sign-in service right now. Try again in a moment."};
    }
    data: any = {};
    try {
        data = await response.json();
    } except Exception {
        data = {};
    }
    if not response.ok {
        code = text_of(data.error_code or data.error);
        if code == "email_not_confirmed" {
            return {"error": "Confirm your email first: open the link Sherry sent you, then try again."};
        }
        if response.status == 429 {
            return {"error": "Too many attempts. Wait a few minutes and try again."};
        }
        return {"error": "That email and password don't match a Sherry account."};
    }
    user: any = data.user or {};
    return {"userId": text_of(user.id), "email": text_of(user.email) or email};
}


"""POST /authorize: the user allowed (after signing in) or cancelled."""
async def:pub authorize_submit(request: any, env: any) -> any {
    form: any = await _body_params(request);
    request_id = text_of(form.request);
    pending: any = await query_one(env, "SELECT * FROM oauth_requests WHERE id = ?", [request_id]);
    if not pending or now_seconds() - (pending.created_at as float) > REQUEST_TTL {
        return _problem_page("This sign-in link expired.", "Go back to your assistant and start connecting Sherry again.");
    }
    params: any = JSON.parse(text_of(pending.params));
    client: any = await _client(env, text_of(pending.client_id));
    if text_of(form.action) == "deny" {
        await execute(env, "DELETE FROM oauth_requests WHERE id = ?", [request_id]);
        return _redirect(_with_params(text_of(params.redirect_uri), {"error": "access_denied", "error_description": "The user declined to connect Sherry.", "state": text_of(params.state)}));
    }
    email = text_of(form.email).strip().lower();
    password = text_of(form.password);
    signed: dict = await _supabase_sign_in(env, email, password);
    if signed["error"] {
        return _form_page(request, request_id, text_of(client.client_name) if client else "", text_of(params.redirect_uri), str(signed["error"]), email);
    }
    code = random_token(32);
    await env.DB.batch(
        [
            statement(env, "DELETE FROM oauth_requests WHERE id = ?", [request_id]),
            statement(
                env,
                "INSERT INTO oauth_codes (code_hash, client_id, user_id, email, redirect_uri, code_challenge, scope, resource, expires_at) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    await sha256_hex(code), text_of(pending.client_id), str(signed["userId"]), str(signed["email"]),
                    text_of(params.redirect_uri), text_of(params.code_challenge), text_of(params.scope) or SCOPE,
                    text_of(params.resource), now_seconds() + CODE_TTL
                ]
            )
        ]
    );
    return _redirect(_with_params(text_of(params.redirect_uri), {"code": code, "state": text_of(params.state), "iss": base_url(request)}));
}


# ---------- token + revoke ----------

async def _issue(env: any, client_id: str, user_id: str, email: str, scope: str, resource: str) -> any {
    access = ACCESS_PREFIX + random_token(32);
    refresh = REFRESH_PREFIX + random_token(32);
    family = new_id();
    now = now_seconds();
    await env.DB.batch(
        [
            statement(
                env,
                "INSERT INTO oauth_tokens (token_hash, kind, family, client_id, user_id, email, scope, resource, expires_at) VALUES (?, 'access', ?, ?, ?, ?, ?, ?, ?)",
                [await sha256_hex(access), family, client_id, user_id, email, scope, resource, now + ACCESS_TTL]
            ),
            statement(
                env,
                "INSERT INTO oauth_tokens (token_hash, kind, family, client_id, user_id, email, scope, resource, expires_at) VALUES (?, 'refresh', ?, ?, ?, ?, ?, ?, ?)",
                [await sha256_hex(refresh), family, client_id, user_id, email, scope, resource, now + REFRESH_TTL]
            ),
            statement(env, "DELETE FROM oauth_tokens WHERE expires_at < ?", [now])
        ]
    );
    return _json(
        {"access_token": access, "token_type": "Bearer", "expires_in": int(ACCESS_TTL), "refresh_token": refresh, "scope": scope},
        200,
        {}
    );
}


async def:pub token(request: any, env: any) -> any {
    params: any = await _body_params(request);
    client_id = text_of(params.client_id);
    header = text_of(request.headers.get("Authorization"));
    if not client_id and header.startswith("Basic ") {
        try {
            decoded = text_of(atob(header[6:].strip()));
            g: any = globalThis;
            client_id = text_of(g.decodeURIComponent(decoded.split(":")[0]));
        } except Exception {
            client_id = "";
        }
    }
    client: any = await _client(env, client_id);
    if not client or not await _client_authenticated(request, client, params) {
        return _oauth_error(401, "invalid_client", "Unknown client or wrong client credentials.");
    }
    grant = text_of(params.grant_type);
    if grant == "authorization_code" {
        digest = await sha256_hex(text_of(params.code));
        row: any = await query_one(env, "SELECT * FROM oauth_codes WHERE code_hash = ?", [digest]);
        # One use only, even when the exchange below fails.
        await execute(env, "DELETE FROM oauth_codes WHERE code_hash = ?", [digest]);
        if not row or text_of(row.client_id) != client_id or (row.expires_at as float) < now_seconds() {
            return _oauth_error(400, "invalid_grant", "The authorization code is invalid or expired.");
        }
        redirect_uri = text_of(params.redirect_uri);
        if redirect_uri and redirect_uri != text_of(row.redirect_uri) {
            return _oauth_error(400, "invalid_grant", "redirect_uri doesn't match.");
        }
        if not await _pkce_ok(text_of(params.code_verifier), text_of(row.code_challenge)) {
            return _oauth_error(400, "invalid_grant", "PKCE verification failed.");
        }
        return await _issue(env, client_id, text_of(row.user_id), text_of(row.email), text_of(row.scope), text_of(row.resource));
    }
    if grant == "refresh_token" {
        digest = await sha256_hex(text_of(params.refresh_token));
        row: any = await query_one(env, "SELECT * FROM oauth_tokens WHERE token_hash = ? AND kind = 'refresh'", [digest]);
        if not row or text_of(row.client_id) != client_id or (row.expires_at as float) < now_seconds() {
            return _oauth_error(400, "invalid_grant", "The refresh token is invalid or expired.");
        }
        # Rotate: the old access + refresh tokens stop working.
        await execute(env, "DELETE FROM oauth_tokens WHERE family = ?", [row.family]);
        return await _issue(env, client_id, text_of(row.user_id), text_of(row.email), text_of(row.scope), text_of(row.resource));
    }
    return _oauth_error(400, "unsupported_grant_type", "Use authorization_code or refresh_token.");
}


async def:pub revoke(request: any, env: any) -> any {
    params: any = await _body_params(request);
    digest = await sha256_hex(text_of(params.token));
    row: any = await query_one(env, "SELECT family FROM oauth_tokens WHERE token_hash = ?", [digest]);
    if row {
        await execute(env, "DELETE FROM oauth_tokens WHERE family = ?", [row.family]);
    }
    return construct("Response", [None, {"status": 200, "headers": CORS}]);
}


# ---------- bearer check for /mcp ----------

"""The connector caller behind an MCP access token, or None."""
async def:pub mcp_caller(request: any, env: any) -> McpCaller | None {
    header = text_of(request.headers.get("Authorization"));
    if not header.startswith("Bearer ") {
        return None;
    }
    raw = header[7:].strip();
    if not raw.startswith(ACCESS_PREFIX) {
        return None;
    }
    row: any = await query_one(
        env,
        "SELECT t.user_id, t.email, t.client_id, t.resource, t.expires_at, c.client_name FROM oauth_tokens t "
        + "LEFT JOIN oauth_clients c ON c.client_id = t.client_id WHERE t.token_hash = ? AND t.kind = 'access'",
        [await sha256_hex(raw)]
    );
    if not row or (row.expires_at as float) < now_seconds() {
        return None;
    }
    audience = text_of(row.resource);
    if audience and not _is_our_resource(request, audience) {
        return None;
    }
    return McpCaller(
        userId=text_of(row.user_id),
        email=text_of(row.email),
        clientId=text_of(row.client_id),
        clientName=text_of(row.client_name)
    );
}


def:pub unauthorized_mcp(request: any) -> any {
    meta = base_url(request) + "/.well-known/oauth-protected-resource/mcp";
    return _json(
        {"jsonrpc": "2.0", "id": None, "error": {"code": -32001, "message": "Sign in to Sherry to use this connector."}},
        401,
        {"WWW-Authenticate": "Bearer error=\"invalid_token\", resource_metadata=\"" + meta + "\"", "Access-Control-Expose-Headers": "WWW-Authenticate"}
    );
}
