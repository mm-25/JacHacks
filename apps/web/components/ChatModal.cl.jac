"""Chat details popup (UI_OVERHAUL_PRD 3.3): the pure transcript of one captured
chat from `get_conversation`, cleaned of scraper artifacts, with no summary
block. Actions: open the original chat, export it as JSON, delete it."""

import from react { useEffect }
import from .Icon { Icon }
import from .SourceChip { SourceChip }
import from ..lib.cloud { call_cloud }
import from ..lib.transcript { clean_text }
import from ..lib.format { full_time, platform_label }
import from ..lib.browser { ask_confirm }


"""Save `data` as a .json file in the browser."""
def download_json(name: str, data: any) {
    blob: any = new(Blob, [JSON.stringify(data, None, 2)], {"type": "application/json"});
    url_api: any = URL;
    href = str(url_api.createObjectURL(blob));
    link: any = document.createElement("a");
    link.href = href;
    link.download = name;
    document.body.appendChild(link);
    link.click();
    link.remove();
    url_api.revokeObjectURL(href);
}


def:pub ChatModal(
    chat: dict,
    onClose: Callable[[], None],
    onDeleted: Callable[[str, str], None],
    onExpired: Callable[[], None]
) -> JsxElement {
    has detail: dict | None = None,
        loading: bool = True,
        error: str = "",
        deleting: bool = False;

    chat_id = str(chat["id"]);

    async def load -> None {
        got = await call_cloud("get_conversation", {"id": chat_id});
        loading = False;
        if got["ok"] and got["result"] {
            detail = got["result"] as dict;
        } elif "session" in str(got["error"]) {
            onExpired();
        } else {
            error = str(got["error"]) or "This chat is no longer in Sherry.";
        }
    }

    async def remove -> None {
        if not ask_confirm("Delete this chat from Sherry? Its transcript is erased everywhere and Sherry stops capturing it.") {
            return;
        }
        deleting = True;
        got = await call_cloud("delete_conversation", {"id": chat_id});
        deleting = False;
        if got["ok"] {
            result: any = got["result"] or {};
            onDeleted(chat_id, str(result.memoryId or ""));
        } else {
            error = str(got["error"]);
        }
    }

    def export_chat {
        d: any = detail or {};
        messages: list = [];
        for m in list(d.messages or []) {
            messages.append({"role": m["role"], "text": clean_text(str(m["text"])), "sentAt": m["sentAt"]});
        }
        download_json(
            "sherry-chat-" + chat_id + ".json",
            {
                "id": chat_id,
                "platform": d.platform,
                "title": d.title,
                "url": d.url,
                "context": d.context,
                "capturedVia": d.capturedVia,
                "messages": messages
            }
        );
    }

    useEffect(
        lambda {
            load();
            on_key = lambda (e: KeyboardEvent) { if e.key == "Escape" { onClose(); } };
            window.addEventListener("keydown", on_key);
            return lambda { window.removeEventListener("keydown", on_key); };
        },
        []
    );

    d: any = detail or {};
    rows: list[dict] = [];
    for m in list(d.messages or []) {
        text = clean_text(str(m["text"]));
        if text {
            rows.append({"role": str(m["role"]), "text": text, "key": str(m["position"]) + str(m["role"])});
        }
    }
    title = str(chat["displayTitle"]);
    link = str(chat["url"] or "");

    return
        <div className="modal-backdrop" onClick={lambda e: MouseEvent { onClose(); }}>
            <div
                className="modal chat-modal"
                role="dialog"
                aria-modal="true"
                aria-label={title}
                onClick={lambda e: MouseEvent { e.stopPropagation(); }}
            >
                <div className="chat-modal-head">
                    <div className="chat-modal-titles">
                        <h2 className="modal-title chat-modal-title">{title}</h2>
                        <div className="conv-meta">
                            <SourceChip platform={str(chat["platform"])}/>
                            <span>{str(len(rows)) + (" message" if len(rows) == 1 else " messages")}</span>
                            <span className="card-meta-sep">·</span>
                            <span>{"Last active " + full_time(str(chat["updatedAt"]))}</span>
                        </div>
                    </div>
                    <button type="button" className="btn btn-ghost btn-icon" onClick={lambda e: MouseEvent { onClose(); }} aria-label="Close">
                        <Icon name="x"/>
                    </button>
                </div>
                <div className="chat-modal-actions">
                    {if link {
                        <a key="open" className="btn btn-sm" href={link} target="_blank" rel="noopener noreferrer">
                            Open original chat ↗
                        </a>
                    }}
                    <button type="button" className="btn btn-sm" onClick={lambda e: MouseEvent { export_chat(); }} disabled={detail is None}>
                        Export JSON
                    </button>
                    <button type="button" className="btn btn-sm chat-delete" onClick={lambda e: MouseEvent { remove(); }} disabled={deleting}>
                        {"Deleting…" if deleting else "Delete from Sherry"}
                    </button>
                </div>
                <div className="chat-modal-body">
                    <div className="transcript-label">Transcript</div>
                    {if loading {
                        <div key="loading" aria-busy="true" style={{"display": "grid", "gap": "8px"}}>
                            <div className="skeleton"/>
                            <div className="skeleton"/>
                        </div>
                    } elif error {
                        <div key="err" className="alert alert-error" role="alert">
                            <span className="alert-body">{error}</span>
                        </div>
                    } elif len(rows) == 0 {
                        <p key="none" className="dash-note">
                            {"No messages captured for this " + platform_label(str(chat["platform"])) + " chat yet."}
                        </p>
                    } else {
                        <ol key="list" className="bubbles">
                            {for r in rows {
                                <li key={r["key"]} className={"bubble bubble-" + r["role"]}>
                                    <div className="bubble-role">{"User" if r["role"] == "user" else "Assistant"}</div>
                                    <div className="bubble-text">{r["text"]}</div>
                                </li>
                            }}
                        </ol>
                    }}
                </div>
            </div>
        </div>;
}
