"""'Connect apps and assistants' dialog: the Sherry address plus API keys for
programs that can't sign in interactively (browser extension, desktop sync,
MCP connector). A new key is shown once; only its hash is stored, and each
key can be revoked on its own."""

import from react { useEffect }
import from .Icon { Icon }
import from ..lib.browser { api_origin, copy_text }
import from ..lib.format { relative_time }
import from ..lib.cloud { call_cloud }

glob _NL: str = chr(10);


def:pub ConnectPanel(account: str, onClose: Callable[[], None]) -> JsxElement {
    has keys: list[dict] = [],
        loading: bool = True,
        busy: bool = False,
        error: str = "",
        name: str = "",
        new_key: str = "",
        copied: str = "";

    origin = api_origin();

    async def load_keys -> None {
        listed = await call_cloud("list_api_keys", {});
        loading = False;
        if listed["ok"] {
            keys = (listed["result"] or []) as list[dict];
        } else {
            error = str(listed["error"]);
        }
    }

    useEffect(
        lambda {
            load_keys();
            return lambda { };
        },
        []
    );

    async def create_key(e: FormEvent) -> None {
        e.preventDefault();
        busy = True;
        error = "";
        made = await call_cloud("create_api_key", {"name": name.strip() or "API key"});
        busy = False;
        if not made["ok"] {
            error = str(made["error"]);
            return;
        }
        result: any = made["result"];
        new_key = str(result.key);
        name = "";
        copied = "";
        await load_keys();
    }

    async def revoke(id: str, label: str) -> None {
        g: any = globalThis;
        if not g.confirm("Revoke '" + label + "'? Anything using it stops working.") {
            return;
        }
        busy = True;
        done = await call_cloud("revoke_api_key", {"id": id});
        busy = False;
        if not done["ok"] {
            error = str(done["error"]);
            return;
        }
        await load_keys();
    }

    async def copy(label: str, text: str) -> None {
        ok: bool = False;
        ok = await copy_text(text);
        copied = label if ok else "failed";
    }

    def handle_backdrop(e: MouseEvent) {
        if e.target == e.currentTarget {
            onClose();
        }
    }

    def handle_key(e: KeyboardEvent) {
        if e.key == "Escape" {
            onClose();
        }
    }

    env_block = "SHERRY_URL=" + origin + _NL + "SHERRY_API_KEY=" + (new_key or "<your key>");

    return
        <div
            className="modal-backdrop"
            onClick={handle_backdrop}
            onKeyDown={handle_key}
        >
            <div
                className="modal"
                role="dialog"
                aria-modal="true"
                aria-labelledby="connect-title"
            >
                <div className="modal-head">
                    <h2 id="connect-title" className="modal-title">
                        Connect apps and assistants
                    </h2>
                    <button
                        type="button"
                        className="btn btn-ghost btn-icon btn-sm"
                        onClick={lambda e: MouseEvent { onClose(); }}
                        aria-label="Close"
                        autoFocus={True}
                    >
                        <Icon name="x" size={16}/>
                    </button>
                </div>
                <p className="modal-text">
                    The browser extension, the desktop sync and AI connectors reach your
                    Sherry with the address below and an API key. Create one key per app, so
                    you can revoke each on its own.
                </p>
                <div className="field">
                    <span className="field-label">Sherry URL</span>
                    <div className="copy-row">
                        <code className="copy-value">{origin}</code>
                        <button
                            type="button"
                            className="btn btn-sm"
                            onClick={lambda e: MouseEvent { copy("url", origin); }}
                        >
                            {"Copied" if copied == "url" else "Copy"}
                        </button>
                    </div>
                </div>
                {if new_key {
                    <div key="new-key" className="field">
                        <span className="field-label">New API key: copy it now, it won't be shown again</span>
                        <div className="copy-row">
                            <code className="copy-value">{new_key}</code>
                            <button
                                type="button"
                                className="btn btn-sm btn-primary"
                                onClick={lambda e: MouseEvent { copy("key", new_key); }}
                            >
                                {"Copied" if copied == "key" else "Copy"}
                            </button>
                        </div>
                        <pre className="code-block">{env_block}</pre>
                        <div>
                            <button
                                type="button"
                                className="btn btn-sm"
                                onClick={lambda e: MouseEvent { copy("env", env_block); }}
                            >
                                {"Copied" if copied == "env" else "Copy for the desktop sync"}
                            </button>
                        </div>
                    </div>
                }}
                <form className="key-create" onSubmit={create_key}>
                    <input
                        className="input"
                        placeholder="Key name, e.g. Browser extension"
                        maxLength={60}
                        value={name}
                        onChange={lambda e: ChangeEvent { name = e.target.value; }}
                        aria-label="Key name"
                    />
                    <button type="submit" className="btn btn-primary" disabled={busy}>
                        {"Creating…" if busy else "Create key"}
                    </button>
                </form>
                {if error {
                    <div key="err" className="alert alert-error" role="alert">{error}</div>
                } elif copied == "failed" {
                    <div key="copy-failed" className="alert alert-warn" role="status">
                        Your browser blocked copying. Select the text and copy it manually.
                    </div>
                }}
                <div className="field">
                    <span className="field-label">Your API keys</span>
                    {if loading {
                        <p key="loading" className="modal-text">Loading…</p>
                    } elif len(keys) == 0 {
                        <p key="none" className="modal-text">No keys yet.</p>
                    } else {
                        <ul key="list" className="key-list">
                            {[
                                <li key={k["id"]} className="key-row">
                                    <div className="key-main">
                                        <span className="key-name">{k["name"]}</span>
                                        <span className="mono">{str(k["prefix"]) + "…"}</span>
                                    </div>
                                    <span className="key-meta">
                                        {"used " + relative_time(str(k["lastUsedAt"]), Date.now())
                                            if k["lastUsedAt"]
                                            else "never used"}
                                    </span>
                                    <button
                                        type="button"
                                        className="btn btn-sm btn-ghost"
                                        onClick={lambda e: MouseEvent { revoke(str(k["id"]), str(k["name"])); }}
                                        disabled={busy}
                                    >
                                        Revoke
                                    </button>
                                </li> for k in keys
                            ]}
                        </ul>
                    }}
                </div>
                <div className="alert alert-warn" role="note">
                    <span className="alert-body">
                        A key gives full access to the memories of {account or "this account"}.
                        Only paste it into tools you trust, and revoke it if it leaks.
                    </span>
                </div>
            </div>
        </div>;
}
