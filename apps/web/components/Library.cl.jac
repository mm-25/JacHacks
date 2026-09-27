"""The signed-in Sherry command center: search, capture, library, detail.

This is the page's stateful shell - it owns every reactive field and passes
data + callbacks into stateless sections. Handler bodies are in
Library.impl.jac.

Sync model (TECHNICAL.md section 14, timed-refresh fallback):
- the list is re-fetched every few seconds while the tab is visible, on
  window focus, when the browser comes back online, and on Refresh;
- new captures are optimistic 'pending' items persisted in localStorage and
  retried with the same idempotency key until the server accepts them.
"""

import from react { useEffect }
import from "@jac/runtime" { jacLogout, __jacClearCache }
import from .Icon { Icon }
import from .Composer { Composer }
import from .MemoryCard { MemoryCard }
import from .PendingCard { PendingCard }
import from .MemoryDetail { MemoryDetail }
import from .SyncStatus { SyncStatus }
import from .ConnectPanel { ConnectPanel }
import from ..lib.demo { is_demo_account }
import from ..lib.format { new_idempotency_key }
import from ..lib.browser {
    now_ms,
    now_iso,
    is_online,
    is_narrow,
    page_hidden,
    scroll_top,
    ask_confirm,
    is_typing,
    focus_element,
    load_list,
    save_list
}

sv import from ..services.memories {
    MemoryView,
    MemoryPage,
    list_memories,
    create_memory,
    delete_memory,
    restore_memory,
    reset_demo
}

glob PENDING_STORAGE_KEY: str = "sherry.pending.v1";
glob POLL_MS: int = 5000;
glob PAGE_SIZE: int = 25;
glob TOAST_MS: int = 8000;

def:pub Library(account: str, onSignOut: Callable[[], None]) -> JsxElement {
    has memories: list[MemoryView] = [],
        total: int = 0,
        next_cursor: str | None = None,
        query: str = "",
        loading: bool = True,
        syncing: bool = False,
        loading_more: bool = False,
        load_error: bool = False,
        online: bool = True,
        last_synced: float = 0,
        tick: float = 0,
        selected_id: str = "",
        deleting: bool = False,
        pending: list[dict] = [],
        toast: dict | None = None,
        menu_open: bool = False,
        connect_open: bool = False;

    # Latest-request guard and a synchronous mirror of `pending` for async code.
    has request_seq: Ref[int] = Ref(0),
        pending_ref: Ref[list[dict]] = Ref([]);

    # Mount: restore queued captures, wire browser events and the poll timer.
    useEffect(
        lambda {
            restore_pending();
            online = is_online();
            tick = now_ms();
            on_focus = lambda (e: Event) { tick = now_ms(); };
            on_online = lambda (e: Event) {
                online = True;
                tick = now_ms();
            };
            on_offline = lambda (e: Event) { online = False; };
            on_key = lambda (e: KeyboardEvent) { handle_global_key(e); };
            window.addEventListener("focus", on_focus);
            window.addEventListener("online", on_online);
            window.addEventListener("offline", on_offline);
            window.addEventListener("keydown", on_key);
            timer = setInterval(lambda { tick = now_ms(); }, POLL_MS);
            return lambda {
                clearInterval(timer);
                window.removeEventListener("focus", on_focus);
                window.removeEventListener("online", on_online);
                window.removeEventListener("offline", on_offline);
                window.removeEventListener("keydown", on_key);
            };
        },
        []
    );

    # Search: debounce typing, fetch immediately when the box is cleared.
    useEffect(
        lambda {
            wait_ms = 220 if query else 0;
            timer = setTimeout(lambda { refresh(False); }, wait_ms);
            return lambda { clearTimeout(timer); };
        },
        [query]
    );

    # Background poll tick (also bumped by focus / online events).
    can with [tick] entry {
        if tick > 0 and not page_hidden() and not loading {
            refresh(True);
        }
    }

    # Flush the offline queue as soon as connectivity returns.
    can with [online] entry {
        if online {
            flush_pending();
        }
    }

    # Toasts dismiss themselves.
    useEffect(
        lambda {
            timer = setTimeout(lambda { toast = None; }, TOAST_MS if toast else 0);
            return lambda { clearTimeout(timer); };
        },
        [toast]
    );

    async def refresh(background: bool) -> None;
    async def load_more -> None;
    async def save_new(content: str, tags: list[str], source: str, label: str) -> None;
    async def send_pending(key: str) -> None;
    def flush_pending;
    def restore_pending;
    def set_pending(items: list[dict]);
    def update_pending(key: str, state: str, error: str);
    def discard_pending(key: str);
    async def remove_memory(id: str) -> None;
    async def undo_delete(id: str) -> None;
    async def reset_workspace -> None;
    def sign_out;
    def handle_expired;
    def handle_global_key(e: KeyboardEvent);
    def open_memory(id: str);
    def close_detail;

    selected: MemoryView | None = None;
    for m in memories {
        if m.id == selected_id {
            selected = m;
        }
    }
    unsaved = len(
        [
            p
            for p in pending
            if p["state"] == "failed"
        ]
    );
    toast_undo = str(toast["undo"]) if toast and toast["undo"] else "";
    demo = is_demo_account(account);

    return
        <div className="app">
            <header className="topbar">
                <div className="topbar-brand">
                    <div className="logo" aria-hidden="true">S</div>
                    <span className="wordmark">Sherry</span>
                </div>
                <div className="topbar-spacer"/>
                <SyncStatus
                    online={online}
                    syncing={syncing}
                    has_error={load_error}
                    unsaved={unsaved}
                    last_synced={last_synced}
                    now_ms={tick}
                    onRetry={lambda { refresh(False); }}
                />
                <div className="topbar-actions">
                    <button
                        type="button"
                        className="btn btn-ghost btn-icon"
                        onClick={lambda e: MouseEvent { refresh(False); }}
                        aria-label="Refresh library"
                        title="Refresh"
                        disabled={syncing}
                    >
                        <Icon name="refresh"/>
                    </button>
                    <button
                        type="button"
                        className="btn btn-ghost btn-icon"
                        onClick={lambda e: MouseEvent { menu_open = not menu_open; }}
                        aria-label="Account menu"
                        aria-haspopup="menu"
                        aria-expanded={"true" if menu_open else "false"}
                    >
                        <Icon name="user"/>
                    </button>
                    {if menu_open {
                        <div key="slot1" className="menu" role="menu">
                            <div className="menu-header">
                                <div className="menu-header-label">Signed in as</div>
                                <div className="menu-header-value">
                                    {account or "Your account"}
                                </div>
                            </div>
                            <button
                                type="button"
                                role="menuitem"
                                className="menu-item"
                                onClick={lambda e: MouseEvent {
                                    menu_open = False;
                                    connect_open = True;
                                }}
                            >
                                Connect an AI assistant
                            </button>
                            {if demo {
                                <button
                                    key="reset"
                                    type="button"
                                    role="menuitem"
                                    className="menu-item"
                                    onClick={lambda e: MouseEvent { reset_workspace(); }}
                                >
                                    Reset to demo data
                                </button>
                            }}
                            <button
                                type="button"
                                role="menuitem"
                                className="menu-item menu-item-danger"
                                onClick={lambda e: MouseEvent { sign_out(); }}
                            >
                                Sign out
                            </button>
                        </div>
                    }}
                </div>
            </header>
            <main className={"layout has-detail" if selected_id else "layout"}>
                <section className="pane-list" aria-label="Library">
                    <div className="search" role="search">
                        <span className="search-icon">
                            <Icon name="search"/>
                        </span>
                        <label htmlFor="search" className="sr-only">
                            Search memories
                        </label>
                        <input
                            id="search"
                            className="input"
                            type="search"
                            placeholder="Search memories, tags, sources…"
                            autoComplete="off"
                            value={query}
                            onChange={lambda e: ChangeEvent { query = e.target.value; }}
                        />
                        {if query {
                            <button
                                key="slot101"
                                type="button"
                                className="btn btn-ghost btn-icon btn-sm search-clear"
                                onClick={lambda e: MouseEvent { query = ""; }}
                                aria-label="Clear search"
                            >
                                <Icon name="x" size={16}/>
                            </button>
                        } else {
                            <kbd
                                key="slot2"
                                className="search-kbd hide-narrow"
                                aria-hidden="true"
                            >
                                /
                            </kbd>
                        } }
                    </div>
                    <Composer onSave={save_new}/>
                    {if load_error and len(memories) > 0 {
                        <div key="slot3" className="alert alert-warn" role="status">
                            <span className="alert-body">
                                Can't reach Sherry. Showing your last synced library.
                            </span>
                            <button
                                type="button"
                                className="btn btn-sm"
                                onClick={lambda e: MouseEvent { refresh(False); }}
                            >
                                Retry
                            </button>
                        </div>
                    }}
                    {if len(pending) > 0 {
                        <ul key="slot4" className="list" aria-label="Waiting to sync">
                            {for p in pending {
                                <li key={str(p["key"])}>
                                    <PendingCard
                                        item={p}
                                        onRetry={lambda k: str { send_pending(k); }}
                                        onDiscard={discard_pending}
                                    />
                                </li>
                            }}
                        </ul>
                    }}
                    <div className="list-head">
                        <h2 className="list-title">
                            {"Results" if query else "Library"}
                        </h2>
                        {if not loading {
                            <span key="slot5" className="list-count" aria-live="polite">
                                {str(total) + (" match" if total == 1 else " matches")
                                    if query
                                    else str(total) + (
                                        " memory" if total == 1 else " memories"
                                    )}
                            </span>
                        }}
                    </div>
                    {if len(memories) == 0 and loading and not load_error {
                        <div
                            key="slot102"
                            aria-busy="true"
                            aria-label="Loading memories"
                            style={{"display": "grid", "gap": "8px"}}
                        >
                            <div className="skeleton"/>
                            <div className="skeleton"/>
                            <div className="skeleton"/>
                        </div>
                    } elif len(memories) == 0 and load_error {
                        <div key="slot6" className="alert alert-error" role="alert">
                            <span className="alert-body">
                                Can't reach Sherry. Check your connection, then try again.
                            </span>
                            <button
                                type="button"
                                className="btn btn-sm"
                                onClick={lambda e: MouseEvent { refresh(False); }}
                            >
                                Retry
                            </button>
                        </div>
                    } elif len(memories) == 0 and query {
                        <div key="slot7" className="empty">
                            <p className="empty-title">
                                {"Nothing matches “" + query + "”"}
                            </p>
                            <p>Search looks at memory text, tags, and source names.</p>
                            <button
                                type="button"
                                className="btn"
                                onClick={lambda e: MouseEvent { query = ""; }}
                            >
                                Clear search
                            </button>
                        </div>
                    } elif len(memories) == 0 {
                        <div key="slot8" className="empty">
                            <p className="empty-title">Your memory is empty</p>
                            <ol className="empty-steps">
                                <li>Type or paste something worth keeping above.</li>
                                <li>Pick where it came from and add a tag or two.</li>
                                <li>Press Save, then find it here or on your phone.</li>
                            </ol>
                            <p style={{"marginTop": "14px"}}>
                                Or let Claude and ChatGPT save chat summaries here.
                            </p>
                            <button
                                type="button"
                                className="btn"
                                onClick={lambda e: MouseEvent { connect_open = True; }}
                            >
                                Connect an AI assistant
                            </button>
                        </div>
                    } else {
                        <ul key="slot9" className="list" aria-label="Memories">
                            {for m in memories {
                                <li key={m.id}>
                                    <MemoryCard
                                        memory={m}
                                        selected={m.id == selected_id}
                                        now_ms={tick}
                                        onOpen={open_memory}
                                    />
                                </li>
                            }}
                        </ul>
                    }    }
                    {if next_cursor {
                        <button
                            key="slot103"
                            type="button"
                            className="btn load-more"
                            onClick={lambda e: MouseEvent { load_more(); }}
                            disabled={loading_more}
                        >
                            {"Loading…" if loading_more else "Load more"}
                        </button>
                    }}
                </section>
                <section className="pane-detail" aria-label="Memory details">
                    {if selected {
                        <MemoryDetail
                            key="slot104"
                            memory={selected as MemoryView}
                            deleting={deleting}
                            onClose={close_detail}
                            onDelete={lambda id: str { remove_memory(id); }}
                        />
                    } elif selected_id and not loading {
                        <div key="slot10" className="detail-placeholder">
                            <div>
                                <p className="detail-placeholder-title">
                                    This memory is gone
                                </p>
                                <p>It was deleted, possibly on another device.</p>
                                <button
                                    type="button"
                                    className="btn"
                                    onClick={lambda e: MouseEvent { close_detail(); }}
                                >
                                    Back to library
                                </button>
                            </div>
                        </div>
                    } else {
                        <div key="slot11" className="detail-placeholder">
                            <div>
                                <Icon name="memory" size={30}/>
                                <p className="detail-placeholder-title">
                                    Pick a memory
                                </p>
                                <p>
                                    Its full text and where it came from will show up here.
                                </p>
                            </div>
                        </div>
                    }  }
                </section>
            </main>
            {if connect_open {
                <ConnectPanel
                    key="connect"
                    account={account}
                    onClose={lambda { connect_open = False; }}
                />
            }}
            {if toast {
                <div key="slot12" className="toast-wrap">
                    <div className="toast" role="status" aria-live="polite">
                        <span>{toast["message"]}</span>
                        {if toast_undo {
                            <button
                                key="slot105"
                                type="button"
                                className="btn btn-sm"
                                onClick={lambda e: MouseEvent { undo_delete(
                                    toast_undo
                                ); }}
                            >
                                Undo
                            </button>
                        }}
                        <button
                            type="button"
                            className="btn btn-sm btn-icon"
                            onClick={lambda e: MouseEvent { toast = None; }}
                            aria-label="Dismiss"
                        >
                            <Icon name="x" size={14}/>
                        </button>
                    </div>
                </div>
            }}
        </div>;
}
