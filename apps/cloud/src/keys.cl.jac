"""Sherry API keys: long-lived credentials for programs that can't do an
interactive Supabase login (browser extension, desktop sync, MCP connector).

A key is shown once when created; only its SHA-256 hash is stored. Keys can
only be created, listed or revoked from a signed-in Supabase session, so a
leaked key can't mint more keys.
"""

import from .util { now_iso, new_id, reject, text_of, random_token, sha256_hex, query_all, query_one, execute }
import from .auth { Principal, API_KEY_PREFIX }

glob MAX_KEYS: int = 20;


def _require_session(who: Principal) {
    if who.via != "session" {
        reject("API keys can only be managed from the Sherry web app.");
    }
}


def _view(row: any) -> dict {
    return {
        "id": text_of(row.id),
        "name": text_of(row.name),
        "prefix": text_of(row.prefix),
        "createdAt": text_of(row.created_at),
        "lastUsedAt": text_of(row.last_used_at) or None
    };
}


"""Create a key. Returns {key, apiKey}: `key` is the secret, shown only now."""
async def:pub create_api_key(env: any, who: Principal, ws: str, body: any) -> dict {
    _require_session(who);
    name = text_of(body.name).strip()[:60] or "API key";
    count: any = await query_one(
        env, "SELECT COUNT(*) AS n FROM api_keys WHERE user_id = ? AND revoked_at = ''", [who.userId]
    );
    if count and int(count.n) >= MAX_KEYS {
        reject(f"You already have {MAX_KEYS} active keys. Revoke one first.");
    }
    secret = API_KEY_PREFIX + random_token(32);
    id = new_id();
    stamp = now_iso();
    await execute(
        env,
        "INSERT INTO api_keys (id, user_id, name, prefix, key_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)",
        [id, who.userId, name, secret[:10], await sha256_hex(secret), stamp]
    );
    row: any = await query_one(env, "SELECT * FROM api_keys WHERE id = ?", [id]);
    return {"key": secret, "apiKey": _view(row)};
}


async def:pub list_api_keys(env: any, who: Principal, ws: str, body: any) -> list[dict] {
    _require_session(who);
    rows = await query_all(
        env,
        "SELECT * FROM api_keys WHERE user_id = ? AND revoked_at = '' ORDER BY created_at DESC",
        [who.userId]
    );
    return [_view(r) for r in rows];
}


async def:pub revoke_api_key(env: any, who: Principal, ws: str, body: any) -> bool {
    _require_session(who);
    result: any = await execute(
        env,
        "UPDATE api_keys SET revoked_at = ? WHERE id = ? AND user_id = ? AND revoked_at = ''",
        [now_iso(), text_of(body.id), who.userId]
    );
    return int(result.meta.changes or 0) > 0;
}
