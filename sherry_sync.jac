"""Sends the desktop scraper's sessions to the shared Sherry database.

`scraper.jac` emits one row per message ({id, content, createdAt, source}).
This groups the rows into sessions and stores each one in Sherry through
`capture_conversation` (captured_via="desktop"), then asks Sherry to summarize a
session once it has been quiet for a while. It follows the contract in
data-schema-specification.md, section 5.

Two ways to use it (both need SHERRY_URL and SHERRY_API_KEY):

    # 1. No code changes: watch the JSON file the scraper writes (newest 200 rows)
    SHERRY_URL=https://... SHERRY_API_KEY=... jac run sherry_sync.jac

    # 2. Inside scraper.jac: every row, not just the newest 200
    import from sherry_sync { SherrySync }
    sync = SherrySync.from_env();        # before the loop
    sync.push(all_mems);                 # each loop, before the rows are capped

Settings (environment variables):
    SHERRY_URL                 Sherry server, e.g. the address share.sh prints
    SHERRY_API_KEY             Sherry web -> account menu -> Connect an AI assistant
    SHERRY_SYNC_PLATFORMS      which tools to sync (default: claude,codex,antigravity)
    SHERRY_SYNC_CONTEXTS       optional: only sync these projects (comma-separated)
    SHERRY_SYNC_IDLE_SECONDS   quiet time before a session is summarized (default 20)
    SHERRY_SYNC_FILE           JSON file for mode 1
                               (default: desktop-app/public/scraped_data.json)
    SHERRY_SYNC_STATE          where to remember what was sent
                               (default: ~/.sherry/desktop-sync.json)

Nothing is sent without SHERRY_URL and SHERRY_API_KEY. Sherry being down never
stops the scraper: errors are printed and retried on the next push.
"""

import os;
import json;
import time;
import hashlib;
import ssl;
import from pathlib { Path }
import from urllib.request { Request, urlopen }
import from urllib.error { HTTPError, URLError }

glob PLATFORMS: list[str] = ["claude", "codex", "antigravity"];
glob BATCH: int = 300;
glob TITLE_CHARS: int = 80;
glob STATE_FILE: str = os.environ.get(
    "SHERRY_SYNC_STATE",
    os.path.join(os.path.expanduser("~"), ".sherry", "desktop-sync.json")
);


def _log(message: str) {
    print(f"[sherry-sync] {message}");
}


def _csv(value: str) -> list[str] {
    return [part.strip() for part in value.split(",") if part.strip()];
}


def _int(text: str, fallback: int) -> int {
    try {
        return int(text);
    } except ValueError {
        return fallback;
    }
}


"""HTTPS context that also works on python.org macOS builds (no system certs)."""
def _ssl_context -> ssl.SSLContext {
    try {
        import certifi;
        return ssl.create_default_context(cafile=certifi.where());
    } except ImportError {
        return ssl.create_default_context();
    }
}


"""One session parsed out of the scraper's rows."""
obj Session {
    has platform: str,
        external_id: str,
        context: str = "",
        messages: list[dict] = [];

    def postinit {
        self.messages = [];
    }

    def title -> str {
        if self.context {
            return self.context[:TITLE_CHARS];
        }
        for m in self.messages {
            if m["role"] == "user" {
                first_line = str(m["text"]).strip().split("\n")[0];
                return first_line[:TITLE_CHARS];
            }
        }
        return "";
    }

    def digest -> str {
        h = hashlib.sha256();
        for m in self.messages {
            h.update(f"{m['key']}\x1f{m['role']}\x1f{m['text']}\x1e".encode("utf-8"));
        }
        return h.hexdigest();
    }
}


"""(session id, position) from a scraper row id, per scraper.jac's formats:
antigravity `{step}-{conv}-user|ai`, claude `claude-{session}-{line}`,
codex `codex-{session}-{line}`. A row may also carry `session` directly."""
def _session_and_position(platform: str, row: dict) -> tuple[str, int] {
    row_id = str(row.get("id", ""));
    explicit = str(row.get("session", "") or "");
    if platform == "antigravity" {
        parts = row_id.split("-", 1);
        step = _int(parts[0], 0);
        rest = parts[1] if len(parts) > 1 else "";
        conv = rest.rsplit("-", 1)[0] if "-" in rest else rest;
        # user and ai rows can share a step; keep the user row first
        offset = 0 if row_id.endswith("-user") else 1;
        return (explicit or conv, step * 2 + offset);
    }
    prefix = platform + "-";
    rest = row_id[len(prefix):] if row_id.startswith(prefix) else row_id;
    if "-" in rest {
        pieces = rest.rsplit("-", 1);
        return (explicit or pieces[0], _int(pieces[1], 0));
    }
    return (explicit or rest, 0);
}


def _by_position(m: dict) -> int {
    return int(m["position"]);
}


def _role(row: dict) -> str {
    source: dict = (row.get("source") or {}) as dict;
    label = str(source.get("label", "")).strip().lower();
    return "user" if label.startswith("user") else "assistant";
}


obj SherrySync {
    has url: str,
        api_key: str,
        platforms: list[str] = [],
        contexts: list[str] = [],
        idle_seconds: int = 20,
        state: dict = {},
        warned: bool = False,
        paused_until: float = 0.0;

    def postinit {
        self.url = self.url.strip().rstrip("/");
        self.api_key = self.api_key.strip();
        self.platforms = [p for p in self.platforms if p in PLATFORMS] or list(PLATFORMS);
        self.state = self._load_state();
        self.warned = False;
        self.paused_until = 0.0;
    }

    static def from_env -> SherrySync {
        return SherrySync(
            url=os.environ.get("SHERRY_URL", ""),
            api_key=os.environ.get("SHERRY_API_KEY", ""),
            platforms=_csv(os.environ.get("SHERRY_SYNC_PLATFORMS", ",".join(PLATFORMS))),
            contexts=_csv(os.environ.get("SHERRY_SYNC_CONTEXTS", "")),
            idle_seconds=_int(os.environ.get("SHERRY_SYNC_IDLE_SECONDS", "20"), 20)
        );
    }

    def enabled -> bool {
        return bool(self.url) and bool(self.api_key);
    }

    # ---------- state (what was already sent), kept across restarts ----------

    def _load_state -> dict {
        try {
            return json.loads(Path(STATE_FILE).read_text()) as dict;
        } except Exception {
            return {};
        }
    }

    def _save_state {
        path = Path(STATE_FILE);
        try {
            path.parent.mkdir(parents=True, exist_ok=True);
            path.write_text(json.dumps(self.state));
            os.chmod(path, 0o600);
        } except OSError as err {
            _log(f"could not save {STATE_FILE}: {err}");
        }
    }

    def _entry(s: Session) -> dict {
        key = f"{self.url}|{s.platform}|{s.external_id}";
        if key not in self.state {
            self.state[key] = {"sent": "", "changed": 0.0, "summarized": "", "ignored": False};
        }
        return self.state[key] as dict;
    }

    # ---------- Sherry API ----------

    """POST /function/<name>; returns the result, or raises RuntimeError."""
    def _call(name: str, body: dict) -> any {
        request = Request(
            f"{self.url}/function/{name}",
            data=json.dumps(body).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}", "User-Agent": "SherrySync/1.0"
            },
            method="POST"
        );
        try {
            response: any = urlopen(request, timeout=20, context=_ssl_context());
            try {
                raw: bytes = response.read() as bytes;
            } finally {
                response.close();
            }
            payload: dict = json.loads(raw.decode("utf-8")) as dict;
        } except HTTPError as err {
            if err.code == 401 {
                raise RuntimeError("Sherry rejected the API key (check SHERRY_API_KEY).");
            }
            raise RuntimeError(f"Sherry answered HTTP {err.code}.");
        } except URLError as err {
            raise RuntimeError(f"can't reach Sherry at {self.url} ({err.reason}).");
        } except TimeoutError {
            raise RuntimeError(f"Sherry at {self.url} timed out.");
        }
        data: dict = (payload.get("data") or {}) as dict;
        if data.get("error") {
            raise RuntimeError(str(data["error"]));
        }
        return data.get("result");
    }

    # ---------- grouping ----------

    def sessions(rows: list) -> list[Session] {
        by_key: dict[str, Session] = {};
        for raw in rows {
            if not isinstance(raw, dict) {
                continue;
            }
            row: dict = raw as dict;
            source: dict = (row.get("source") or {}) as dict;
            platform = str(source.get("platform", ""));
            text = str(row.get("content", "")).strip();
            if platform not in self.platforms or not text or not row.get("id") {
                continue;
            }
            (external_id, position) = _session_and_position(platform, row);
            context = str(row.get("context", "") or "").strip();
            if self.contexts and context not in self.contexts {
                continue;
            }
            if not external_id {
                continue;
            }
            key = f"{platform}|{external_id}";
            if key not in by_key {
                by_key[key] = Session(platform=platform, external_id=external_id, context=context);
            }
            by_key[key].messages.append(
                {
                    "key": str(row["id"])[:200],
                    "role": _role(row),
                    "text": text,
                    "position": position,
                    "createdAt": str(row.get("createdAt", "") or "")
                }
            );
        }
        found = list(by_key.values());
        for s in found {
            s.messages.sort(key=_by_position);
        }
        return found;
    }

    # ---------- the one call the scraper makes ----------

    """Send every new or changed session, then summarize quiet ones. Never raises."""
    def push(rows: list) -> None {
        if not self.enabled() {
            if not self.warned {
                _log("off: set SHERRY_URL and SHERRY_API_KEY to send sessions to Sherry.");
                self.warned = True;
            }
            return;
        }
        now = time.time();
        if now < self.paused_until {
            return;
        }
        changed = False;
        try {
            for s in self.sessions(rows) {
                entry = self._entry(s);
                if entry["ignored"] {
                    continue;
                }
                digest = s.digest();
                if digest != entry["sent"] {
                    ignored = self._send(s);
                    entry["sent"] = digest;
                    entry["changed"] = now;
                    entry["ignored"] = ignored;
                    changed = True;
                    if ignored {
                        _log(f"{s.platform} session {s.external_id[:12]} was deleted in Sherry; no longer syncing it.");
                        continue;
                    }
                }
                changed_at: float = entry["changed"] as float;
                quiet = now - changed_at >= self.idle_seconds;
                if quiet and entry["summarized"] != entry["sent"] {
                    self._call(
                        "summarize_conversation",
                        {"platform": s.platform, "conversation_id": s.external_id}
                    );
                    entry["summarized"] = entry["sent"];
                    changed = True;
                    _log(f"summarized {s.platform} session {s.external_id[:12]} ({len(s.messages)} messages).");
                }
            }
        } except RuntimeError as err {
            _log(f"{err} Retrying in 30s.");
            self.paused_until = now + 30;
        }
        if changed {
            self._save_state();
        }
    }

    """Store one session (in batches). Returns True when Sherry says the user
    deleted it, so it must not be sent again."""
    def _send(s: Session) -> bool {
        added = 0;
        updated = 0;
        for start in range(0, max(len(s.messages), 1), BATCH) {
            result: dict = self._call(
                "capture_conversation",
                {
                    "platform": s.platform,
                    "conversation_id": s.external_id,
                    "title": s.title(),
                    "context": s.context,
                    "captured_via": "desktop",
                    "messages": s.messages[start:start + BATCH]
                }
            ) as dict;
            if result.get("ignored") {
                return True;
            }
            added += int(result.get("added", 0));
            updated += int(result.get("updated", 0));
        }
        if added or updated {
            _log(f"{s.platform} session {s.external_id[:12]}: {added} new, {updated} updated.");
        }
        return False;
    }
}


"""Mode 1: watch the scraper's JSON file and push it every 2 seconds."""
with entry:__main__ {
    sync = SherrySync.from_env();
    source_file = os.environ.get(
        "SHERRY_SYNC_FILE",
        os.path.join(os.getcwd(), "desktop-app", "public", "scraped_data.json")
    );
    _log(f"watching {source_file} -> {sync.url or '(SHERRY_URL not set)'}");
    last_mtime = 0.0;
    rows: list = [];
    while True {
        try {
            mtime = os.path.getmtime(source_file);
            if mtime != last_mtime {
                loaded = json.loads(Path(source_file).read_text());
                rows = loaded if isinstance(loaded, list) else [];
                last_mtime = mtime;
            }
        } except FileNotFoundError {
            rows = [];
        } except json.JSONDecodeError {
            # the scraper is mid-write; keep the previous rows until next time
            last_mtime = 0.0;
        }
        # Unchanged sessions aren't re-sent; this also summarizes quiet ones.
        sync.push(rows);
        time.sleep(2);
    }
}
