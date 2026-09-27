"""Shared helpers for the Sherry Worker: time, ids, hashing, D1 access, and
rejecting bad input.

This package is Jac compiled to JavaScript (`jac jac2js`) and runs on
Cloudflare Workers. Browser/Worker globals (crypto, Date, JSON, D1 bindings)
are reached through `any`-typed values, as in apps/extension.
"""

glob:pub MAX_LIMIT: int = 100;
glob:pub DEFAULT_LIMIT: int = 25;


"""A JavaScript global by name (Response, URL, TextEncoder, ...). Jac's type
checker doesn't know Worker globals, so they're reached through `any`."""
def:pub js(name: str) -> any {
    g: any = globalThis;
    return g[name];
}


"""`new <name>(...args)` for a JavaScript global class."""
def:pub construct(name: str, args: list) -> any {
    r: any = js("Reflect");
    return r.construct(js(name), args);
}


def:pub utf8(text: str) -> any {
    encoder: any = construct("TextEncoder", []);
    return encoder.encode(text);
}


def:pub is_plain_object(value: any) -> bool {
    o: any = js("Object");
    return str(o.prototype.toString.call(value)) == "[object Object]";
}


def:pub now_iso -> str {
    d: any = new(Date);
    return str(d.toISOString());
}


def:pub now_seconds -> float {
    return Date.now() / 1000;
}


"""A new random id: 32 hex characters, like the Jac graph's node ids."""
def:pub new_id -> str {
    g: any = globalThis;
    raw: any = g.crypto.randomUUID();
    return str(raw.replaceAll("-", ""));
}


def:pub to_hex(buffer: any) -> str {
    out = "";
    for b in list(new(Uint8Array, buffer)) {
        byte: any = b;
        out += str(byte.toString(16).padStart(2, "0"));
    }
    return out;
}


async def:pub sha256_hex(text: str) -> str {
    g: any = globalThis;
    encoded: any = utf8(text);
    digest: any = await g.crypto.subtle.digest("SHA-256", encoded);
    return to_hex(digest);
}


"""Base64url (JWT encoding) to raw bytes."""
def:pub b64url_bytes(text: str) -> any {
    b64 = text.replace("-", "+").replace("_", "/");
    while len(b64) % 4 != 0 {
        b64 += "=";
    }
    binary: any = atob(b64);
    size: int = binary.length as int;
    buf: any = new(Uint8Array, size);
    i = 0;
    while i < size {
        buf[i] = binary.charCodeAt(i);
        i += 1;
    }
    return buf;
}


def:pub b64url_text(text: str) -> str {
    decoder: any = construct("TextDecoder", []);
    decoded: any = decoder.decode(b64url_bytes(text));
    return str(decoded);
}


def:pub random_token(byte_count: int) -> str {
    g: any = globalThis;
    buf: any = new(Uint8Array, byte_count);
    g.crypto.getRandomValues(buf);
    binary = "";
    for b in list(buf) {
        binary += String.fromCharCode(b);
    }
    encoded: any = btoa(binary);
    return str(encoded.replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", ""));
}


"""Refuse a request with a message for the client. The router answers it the
way the Jac server answered a ValueError: HTTP 200 with `data.error`."""
def:pub reject(message: str) -> None {
    err: Exception = construct("Error", [message]) as Exception;
    tagged: any = err;
    tagged.sherryReject = True;
    raise err;
}


"""A value as text; null and undefined (missing JSON fields) become ""."""
def:pub text_of(value: any) -> str {
    missing: any = js("undefined");
    if value == None or value == missing {
        return "";
    }
    return str(value);
}


def:pub int_of(value: any, fallback: int) -> int {
    parsed: any = Number.parseInt(text_of(value), 10);
    return fallback if Number.isNaN(parsed) else int(parsed);
}


def:pub is_http_url(url: str) -> bool {
    return url.startswith("https://") or url.startswith("http://");
}


# ---------- D1 ----------

"""All rows of a query."""
async def:pub query_all(env: any, sql: str, params: list) -> list {
    stmt: any = env.DB.prepare(sql);
    bound: any = stmt.bind.apply(stmt, params);
    result: any = await bound.all();
    return list(result.results or []);
}


"""The first row of a query, or None."""
async def:pub query_one(env: any, sql: str, params: list) -> any {
    stmt: any = env.DB.prepare(sql);
    bound: any = stmt.bind.apply(stmt, params);
    row: any = await bound.first();
    return row;
}


async def:pub execute(env: any, sql: str, params: list) -> any {
    stmt: any = env.DB.prepare(sql);
    bound: any = stmt.bind.apply(stmt, params);
    return await bound.run();
}


"""A prepared statement for `env.DB.batch([...])` (runs atomically)."""
def:pub statement(env: any, sql: str, params: list) -> any {
    stmt: any = env.DB.prepare(sql);
    return stmt.bind.apply(stmt, params);
}
