"""Who is calling: a Supabase login or a Sherry API key.

- The web app signs in with Supabase Auth and sends the Supabase access token
  (a JWT). It is verified here against the project's public keys (JWKS:
  ES256/RS256) or, for older projects, the legacy shared secret (HS256). We
  check the signature, expiry, issuer, audience and role.
- Programs that can't do an interactive login (browser extension, desktop
  sync, MCP connector) send a Sherry API key (`shr_...`) created in the web
  app. Only its SHA-256 hash is stored.

Settings (Worker vars/secrets):
    SUPABASE_URL          https://<project>.supabase.co (required for logins)
    SUPABASE_JWT_SECRET   only for projects still on the legacy HS256 secret
    SUPABASE_JWKS         optional JSON override of the key set (local tests)
"""

import from .util {
    now_iso,
    now_seconds,
    b64url_bytes,
    b64url_text,
    sha256_hex,
    utf8,
    text_of,
    query_one,
    execute,
    new_id
}

glob:pub API_KEY_PREFIX: str = "shr_";
glob JWKS_TTL_SECONDS: float = 600.0;
glob jwks_cache: any = {"keys": [], "fetched": 0.0};


obj:pub Principal {
    has userId: str,
        email: str,
        via: str;
}


def _issuer(env: any) -> str {
    base = text_of(env.SUPABASE_URL).strip();
    while base.endswith("/") {
        base = base[:len(base) - 1];
    }
    return base + "/auth/v1" if base else "";
}


async def _load_jwks(env: any, force: bool) -> list {
    override = text_of(env.SUPABASE_JWKS);
    if override {
        parsed: any = JSON.parse(override);
        return list(parsed.keys or []);
    }
    fetched: float = jwks_cache.fetched as float;
    cached: list = jwks_cache.keys as list;
    if now_seconds() - fetched < JWKS_TTL_SECONDS and not force and len(cached) > 0 {
        return cached;
    }
    issuer = _issuer(env);
    if not issuer {
        return [];
    }
    response: any = await fetch(issuer + "/.well-known/jwks.json");
    if not response.ok {
        return [];
    }
    body: any = await response.json();
    keys: list = list(body.keys or []);
    jwks_cache.keys = keys;
    jwks_cache.fetched = now_seconds();
    return keys;
}


async def _find_key(env: any, kid: str) -> any {
    for force in [False, True] {
        for k in await _load_jwks(env, force) {
            candidate: any = k;
            if text_of(candidate.kid) == kid {
                return candidate;
            }
        }
    }
    return None;
}


async def _signature_ok(env: any, header: any, signed: str, signature: str) -> bool {
    g: any = globalThis;
    subtle: any = g.crypto.subtle;
    data: any = utf8(signed);
    sig: any = b64url_bytes(signature);
    alg = text_of(header.alg);
    if alg == "HS256" {
        secret = text_of(env.SUPABASE_JWT_SECRET);
        if not secret {
            return False;
        }
        hmac: any = await subtle.importKey(
            "raw",
            utf8(secret),
            {"name": "HMAC", "hash": "SHA-256"},
            False,
            ["verify"]
        );
        return bool(await subtle.verify("HMAC", hmac, sig, data));
    }
    if alg != "ES256" and alg != "RS256" {
        return False;
    }
    jwk: any = await _find_key(env, text_of(header.kid));
    if not jwk {
        return False;
    }
    if alg == "ES256" {
        ec: any = await subtle.importKey(
            "jwk", jwk, {"name": "ECDSA", "namedCurve": "P-256"}, False, ["verify"]
        );
        return bool(await subtle.verify({"name": "ECDSA", "hash": "SHA-256"}, ec, sig, data));
    }
    rsa: any = await subtle.importKey(
        "jwk", jwk, {"name": "RSASSA-PKCS1-v1_5", "hash": "SHA-256"}, False, ["verify"]
    );
    return bool(await subtle.verify("RSASSA-PKCS1-v1_5", rsa, sig, data));
}


def _audience_ok(aud: any) -> bool {
    if Array.isArray(aud) {
        return bool(aud.includes("authenticated"));
    }
    return text_of(aud) == "authenticated";
}


"""A verified Supabase access token's user, or None."""
async def:pub verify_supabase_token(env: any, token: str) -> Principal | None {
    parts = token.split(".");
    if len(parts) != 3 {
        return None;
    }
    header: any = None;
    claims: any = None;
    try {
        header = JSON.parse(b64url_text(parts[0]));
        claims = JSON.parse(b64url_text(parts[1]));
    } except Exception {
        return None;
    }
    if not await _signature_ok(env, header, parts[0] + "." + parts[1], parts[2]) {
        return None;
    }
    expires: float = (claims.exp or 0) as float;
    if expires < now_seconds() {
        return None;
    }
    issuer = _issuer(env);
    if issuer and text_of(claims.iss) != issuer {
        return None;
    }
    if not _audience_ok(claims.aud) or text_of(claims.role) != "authenticated" {
        return None;
    }
    if not text_of(claims.sub) {
        return None;
    }
    return Principal(userId=text_of(claims.sub), email=text_of(claims.email), via="session");
}


async def:pub verify_api_key(env: any, key: str) -> Principal | None {
    if not key.startswith(API_KEY_PREFIX) {
        return None;
    }
    digest = await sha256_hex(key);
    row: any = await query_one(
        env,
        "SELECT k.id, k.user_id, k.last_used_at, w.email FROM api_keys k "
        + "LEFT JOIN workspaces w ON w.user_id = k.user_id "
        + "WHERE k.key_hash = ? AND k.revoked_at = ''",
        [digest]
    );
    if not row {
        return None;
    }
    # Record use, at most every 10 minutes (saves D1 writes).
    last = text_of(row.last_used_at);
    if not last or Date.parse(last) < Date.now() - 600000 {
        await execute(env, "UPDATE api_keys SET last_used_at = ? WHERE id = ?", [now_iso(), row.id]);
    }
    return Principal(userId=text_of(row.user_id), email=text_of(row.email), via="api_key");
}


"""The caller of a request, or None when the credentials are missing/invalid."""
async def:pub authenticate(request: any, env: any) -> Principal | None {
    header = text_of(request.headers.get("Authorization"));
    if not header.startswith("Bearer ") {
        return None;
    }
    token = header[7:].strip();
    if token.startswith(API_KEY_PREFIX) {
        return await verify_api_key(env, token);
    }
    return await verify_supabase_token(env, token);
}


"""The caller's workspace id, creating the workspace on first use."""
async def:pub ensure_workspace(env: any, who: Principal) -> str {
    row: any = await query_one(env, "SELECT id, email FROM workspaces WHERE user_id = ?", [who.userId]);
    if row {
        if who.email and text_of(row.email) != who.email {
            await execute(env, "UPDATE workspaces SET email = ? WHERE user_id = ?", [who.email, who.userId]);
        }
        return text_of(row.id);
    }
    fresh = new_id();
    await execute(
        env,
        "INSERT INTO workspaces (user_id, id, email, created_at) VALUES (?, ?, ?, ?) "
        + "ON CONFLICT (user_id) DO NOTHING",
        [who.userId, fresh, who.email, now_iso()]
    );
    again: any = await query_one(env, "SELECT id FROM workspaces WHERE user_id = ?", [who.userId]);
    return text_of(again.id);
}
