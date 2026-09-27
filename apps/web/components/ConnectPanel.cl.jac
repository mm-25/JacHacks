"""'Connect an AI assistant' dialog: the API URL and key the Sherry MCP server
needs so Claude, ChatGPT and other assistants can save and recall memories."""

import from .Icon { Icon }
import from ..lib.browser { api_key, api_origin, copy_text }

glob _NL: str = chr(10);

def:pub ConnectPanel(account: str, onClose: Callable[[], None]) -> JsxElement {
    has revealed: bool = False,
        copied: str = "";

    key = api_key();
    origin = api_origin();
    masked = key[:4] + "••••••••••••••••" + key[-4:] if len(key) > 8 else "••••••••";
    env_block = "SHERRY_API_URL=" + origin + _NL + "SHERRY_API_KEY=" + key;

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
                        Connect an AI assistant
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
                    Capture your chats on chatgpt.com and claude.ai into Sherry. Paste the URL
                    and key below into the Sherry browser extension (or, later, the Sherry MCP
                    server). Everything captured shows up here with its source, and you can
                    delete it any time.
                </p>
                <div className="field">
                    <span className="field-label">Sherry API URL</span>
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
                <div className="field">
                    <span className="field-label">
                        API key for {account or "this account"}
                    </span>
                    <div className="copy-row">
                        <code className="copy-value">
                            {key if revealed else masked}
                        </code>
                        <button
                            type="button"
                            className="btn btn-sm btn-ghost"
                            onClick={lambda e: MouseEvent { revealed = not revealed; }}
                        >
                            {"Hide" if revealed else "Show"}
                        </button>
                        <button
                            type="button"
                            className="btn btn-sm"
                            onClick={lambda e: MouseEvent { copy("key", key); }}
                        >
                            {"Copied" if copied == "key" else "Copy"}
                        </button>
                    </div>
                </div>
                <div className="field">
                    <span className="field-label">Environment (MCP server / scripts)</span>
                    <pre className="code-block">
                        {"SHERRY_API_URL=" + origin + _NL + "SHERRY_API_KEY=" + (
                            key if revealed else masked
                        )}
                    </pre>
                    <div>
                        <button
                            type="button"
                            className="btn btn-sm"
                            onClick={lambda e: MouseEvent { copy("env", env_block); }}
                        >
                            {"Copied" if copied == "env" else "Copy environment"}
                        </button>
                    </div>
                </div>
                {if copied == "failed" {
                    <div key="copy-failed" className="alert alert-warn" role="status">
                        Your browser blocked copying. Select the text and copy it manually.
                    </div>
                }}
                <div className="alert alert-warn" role="note">
                    <span className="alert-body">
                        This key gives full access to your memories. Only paste it into tools you trust. It is tied to your account and can't be revoked separately yet.
                    </span>
                </div>
            </div>
        </div>;
}
