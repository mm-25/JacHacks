"""Chat Memory (UI_OVERHAUL_PRD 3.2): every captured chat as a card grid, with
search and Platform / Devices / Date range filters. Clicking a card opens its
transcript (ChatModal). Data: `list_conversations` on the Worker."""

import from react { useEffect }
import from .Icon { Icon }
import from .ChatModal { ChatModal }
import from ..lib.cloud { call_cloud }
import from ..lib.transcript { clean_text, first_line }
import from ..lib.format { platform_label, relative_time }
import from ..lib.browser { now_ms }

glob PAGE_SIZE: int = 30;
glob TOAST_MS: int = 8000;
glob PLATFORM_OPTIONS: list[str] = ["chatgpt", "claude", "gemini", "antigravity", "codex"];
glob DEVICE_OPTIONS: list[list[str]] = [["browser", "Browser"], ["desktop", "Desktop"], ["mobile", "Mobile"]];
glob BADGES: dict[str, str] = {"chatgpt": "G", "claude": "C", "gemini": "Ge", "codex": "Cx", "antigravity": "Ag"};
glob DATE_OPTIONS: list[list[str]] = [["7", "Last 7 days"], ["30", "Last 30 days"]];


"""Card fields: a title (the chat's own, else its first message) and a clean preview."""
def with_display(c: dict) -> dict {
    first = str(c["firstMessage"] or "");
    title = str(c["title"] or "").strip() or first_line(first, 80) or "Untitled chat";
    preview = clean_text(first)[:280];
    # A title taken from the first message would just repeat a short preview.
    if len(preview) <= len(title) + 3 and preview.startswith(title.rstrip("…")) {
        preview = "";
    }
    return {**c, "displayTitle": title, "preview": preview};
}


def:pub ChatMemory(onConnect: Callable[[], None], onExpired: Callable[[], None]) -> JsxElement {
    has items: list[dict] = [],
        total: int = 0,
        next_cursor: str = "",
        loading: bool = True,
        error: str = "",
        query: str = "",
        platform: str = "",
        device: str = "",
        days: str = "",
        open_id: str = "",
        toast: dict | None = None;

    has request_seq: Ref[int] = Ref(0);

    async def load(cursor: str) -> None {
        request_seq.current = (request_seq.current or 0) + 1;
        mine = request_seq.current;
        loading = True;
        got = await call_cloud(
            "list_conversations",
            {"cursor": cursor, "limit": PAGE_SIZE, "query": query, "platform": platform, "device": device, "days": days}
        );
        if mine != request_seq.current {
            return;
        }
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
        fresh: list[dict] = [with_display(c) for c in list(page.data or [])];
        items = (items + fresh) if cursor else fresh;
        total = int(page.total or 0);
        next_cursor = str(page.nextCursor or "");
        error = "";
    }

    # Filters apply at once; typing in search waits a moment.
    useEffect(
        lambda {
            timer = setTimeout(lambda { load(""); }, 250 if query else 0);
            return lambda { clearTimeout(timer); };
        },
        [query, platform, device, days]
    );

    useEffect(
        lambda {
            timer = setTimeout(lambda { toast = None; }, TOAST_MS if toast else 0);
            return lambda { clearTimeout(timer); };
        },
        [toast]
    );

    def handle_deleted(id: str, memory_id: str) {
        open_id = "";
        items = [c for c in items if c["id"] != id];
        total = max(0, total - 1);
        toast = {"message": "Chat deleted from Sherry.", "undo": memory_id};
    }

    async def undo(memory_id: str) -> None {
        toast = None;
        got = await call_cloud("restore_memory", {"id": memory_id});
        if not got["ok"] {
            toast = {"message": "Couldn't undo. Check your connection.", "undo": ""};
        }
        load("");
    }

    filtered = bool(query or platform or device or days);
    selected: dict | None = None;
    for c in items {
        if c["id"] == open_id {
            selected = c;
        }
    }
    now = now_ms();
    toast_undo = str(toast["undo"]) if toast and toast["undo"] else "";

    return
        <div className="page page-wide">
            <header className="page-head">
                <h1 className="page-title">Chat Memory</h1>
                <p className="page-sub">
                    {"Every chat Sherry captured from your AI tools" + ((" · " + str(total) + (" chat" if total == 1 else " chats")) if not loading or total else "") + "."}
                </p>
            </header>
            <div className="chat-tools">
                <div className="search" role="search">
                    <span className="search-icon">
                        <Icon name="search"/>
                    </span>
                    <label htmlFor="chat-search" className="sr-only">Search chats</label>
                    <input
                        id="chat-search"
                        className="input"
                        type="search"
                        placeholder="Search chats, projects, messages…"
                        autoComplete="off"
                        value={query}
                        onChange={lambda e: ChangeEvent { query = e.target.value; }}
                    />
                </div>
                <div className="chat-filters">
                    <label className="sr-only" htmlFor="f-platform">Platform</label>
                    <select id="f-platform" className="select" value={platform} onChange={lambda e: ChangeEvent { platform = e.target.value; }}>
                        <option value="">All platforms</option>
                        {for p in PLATFORM_OPTIONS {
                            <option key={p} value={p}>{platform_label(p)}</option>
                        }}
                    </select>
                    <label className="sr-only" htmlFor="f-device">Devices</label>
                    <select id="f-device" className="select" value={device} onChange={lambda e: ChangeEvent { device = e.target.value; }}>
                        <option value="">All devices</option>
                        {for d in DEVICE_OPTIONS {
                            <option key={d[0]} value={d[0]}>{d[1]}</option>
                        }}
                    </select>
                    <label className="sr-only" htmlFor="f-date">Date range</label>
                    <select id="f-date" className="select" value={days} onChange={lambda e: ChangeEvent { days = e.target.value; }}>
                        <option value="">Any time</option>
                        {for d in DATE_OPTIONS {
                            <option key={d[0]} value={d[0]}>{d[1]}</option>
                        }}
                    </select>
                    {if filtered {
                        <button
                            key="clear"
                            type="button"
                            className="btn btn-ghost btn-sm"
                            onClick={lambda e: MouseEvent {
                                query = "";
                                platform = "";
                                device = "";
                                days = "";
                            }}
                        >
                            Clear filters
                        </button>
                    }}
                </div>
            </div>
            {if error {
                <div key="err" className="alert alert-error" role="alert">
                    <span className="alert-body">{error}</span>
                    <button type="button" className="btn btn-sm" onClick={lambda e: MouseEvent { load(""); }}>Retry</button>
                </div>
            }}
            {if len(items) == 0 and loading {
                <div key="loading" className="chat-grid" aria-busy="true" aria-label="Loading chats">
                    {for i in [1, 2, 3, 4, 5, 6] {
                        <div key={str(i)} className="chat-card chat-card-loading"/>
                    }}
                </div>
            } elif len(items) == 0 and filtered and not error {
                <div key="nomatch" className="empty">
                    <p className="empty-title">No chats match</p>
                    <p>Try other words, or clear the filters.</p>
                </div>
            } elif len(items) == 0 and not error {
                <div key="empty" className="empty">
                    <p className="empty-title">No chats captured yet</p>
                    <p>Install the browser extension or the desktop app, and your chats show up here.</p>
                    <button type="button" className="btn" onClick={lambda e: MouseEvent { onConnect(); }}>
                        Connect apps and assistants
                    </button>
                </div>
            } else {
                <ul key="grid" className="chat-grid" aria-label="Chats">
                    {for c in items {
                        <li key={str(c["id"])} className="chat-grid-item">
                            <button type="button" className="chat-card" onClick={lambda e: MouseEvent { open_id = str(c["id"]); }}>
                                <span className={"platform-icon platform-icon-" + str(c["platform"])} aria-hidden="true">
                                    {BADGES.get(str(c["platform"]), platform_label(str(c["platform"]))[:1])}
                                </span>
                                <span className="chat-card-title">{str(c["displayTitle"])}</span>
                                {if c["preview"] {
                                    <span key="p" className="chat-card-preview">{str(c["preview"])}</span>
                                }}
                                <span className="chat-card-foot">
                                    <span>{platform_label(str(c["platform"])) + (" · Desktop" if c["capturedVia"] == "desktop" else "")}</span>
                                    <span>{"Last active " + relative_time(str(c["updatedAt"]), now)}</span>
                                </span>
                            </button>
                        </li>
                    }}
                </ul>
            }}
            {if next_cursor and not loading {
                <button key="more" type="button" className="btn load-more" onClick={lambda e: MouseEvent { load(next_cursor); }}>
                    Load more
                </button>
            }}
            {if selected {
                <ChatModal
                    key={open_id}
                    chat={selected as dict}
                    onClose={lambda { open_id = ""; }}
                    onDeleted={handle_deleted}
                    onExpired={onExpired}
                />
            }}
            {if toast {
                <div key="toast" className="toast-wrap">
                    <div className="toast" role="status" aria-live="polite">
                        <span>{toast["message"]}</span>
                        {if toast_undo {
                            <button key="undo" type="button" className="btn btn-sm" onClick={lambda e: MouseEvent { undo(toast_undo); }}>
                                Undo
                            </button>
                        }}
                        <button type="button" className="btn btn-sm btn-icon" onClick={lambda e: MouseEvent { toast = None; }} aria-label="Dismiss">
                            <Icon name="x" size={14}/>
                        </button>
                    </div>
                </div>
            }}
        </div>;
}
