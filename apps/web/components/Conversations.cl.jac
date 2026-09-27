"""Connected Conversations: every chat Sherry captured (browser extension or
desktop app), newest activity first, from `list_conversations`."""

import from react { useEffect }
import from .SourceChip { SourceChip }
import from ..lib.cloud { call_cloud }
import from ..lib.format { relative_time }
import from ..lib.browser { now_ms }

glob PAGE_SIZE: int = 30;


def:pub Conversations(onConnect: Callable[[], None], onExpired: Callable[[], None]) -> JsxElement {
    has items: list[dict] = [],
        total: int = 0,
        next_cursor: str = "",
        loading: bool = True,
        error: str = "";

    async def load(cursor: str) -> None {
        loading = True;
        got = await call_cloud("list_conversations", {"cursor": cursor, "limit": PAGE_SIZE});
        loading = False;
        if not got["ok"] {
            if "session" in str(got["error"]) {
                onExpired();
            } else {
                error = str(got["error"]);
            }
            return;
        }
        page: any = got["result"];
        fresh: list[dict] = list(page.data or []);
        items = (items + fresh) if cursor else fresh;
        total = int(page.total or 0);
        next_cursor = str(page.nextCursor or "");
        error = "";
    }

    useEffect(
        lambda {
            load("");
            return lambda { };
        },
        []
    );

    now = now_ms();

    return
        <div className="page">
            <header className="page-head">
                <h1 className="page-title">Connected Conversations</h1>
                <p className="page-sub">
                    {"Chats captured from your AI tools" + ((" · " + str(total) + " in total") if total else "") + "."}
                </p>
            </header>
            {if error {
                <div key="err" className="alert alert-error" role="alert">
                    <span className="alert-body">{error}</span>
                    <button type="button" className="btn btn-sm" onClick={lambda e: MouseEvent { load(""); }}>Retry</button>
                </div>
            }}
            {if len(items) == 0 and not loading and not error {
                <div key="empty" className="empty">
                    <p className="empty-title">No chats captured yet</p>
                    <p>Install the browser extension or the desktop app, and your chats will show up here.</p>
                    <button type="button" className="btn" onClick={lambda e: MouseEvent { onConnect(); }}>
                        Connect apps and assistants
                    </button>
                </div>
            }}
            <ul className="conv-list">
                {for c in items {
                    <li key={str(c["id"])} className="conv-row">
                        <div className="conv-main">
                            <div className="conv-title">{str(c["title"]) or "Untitled chat"}</div>
                            <div className="conv-meta">
                                <SourceChip platform={str(c["platform"])}/>
                                <span>{str(c["messages"]) + (" message" if c["messages"] == 1 else " messages")}</span>
                                <span className="card-meta-sep">·</span>
                                <span>{"Desktop" if c["capturedVia"] == "desktop" else "Web"}</span>
                                {if c["context"] {
                                    <span key="ctx" className="conv-context">{str(c["context"])}</span>
                                }}
                            </div>
                        </div>
                        <div className="conv-side">
                            <span className="conv-time">{relative_time(str(c["updatedAt"]), now)}</span>
                            {if c["url"] {
                                <a key="open" className="btn btn-sm" href={str(c["url"])} target="_blank" rel="noopener noreferrer">
                                    Open
                                </a>
                            }}
                        </div>
                    </li>
                }}
            </ul>
            {if loading {
                <div key="loading" aria-busy="true" style={{"display": "grid", "gap": "8px"}}>
                    <div className="skeleton"/>
                    <div className="skeleton"/>
                </div>
            } elif next_cursor {
                <button key="more" type="button" className="btn load-more" onClick={lambda e: MouseEvent { load(next_cursor); }}>
                    Load more
                </button>
            }}
        </div>;
}
