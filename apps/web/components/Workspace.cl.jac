"""Signed-in shell: the sidebar (pages, account, settings, sign out) and the
current page. The page is kept in the URL hash (#dashboard, #chat, ...) so
reloads and the back button keep your place."""

import from react { useEffect }
import from .Icon { Icon }
import from .Dashboard { Dashboard }
import from .Library { Library }
import from .Conversations { Conversations }
import from .Diagnostics { Diagnostics }
import from .ConnectPanel { ConnectPanel }
import from ..lib.supabase { sign_out as end_session, refresh_session }

glob PAGES: list[dict] = [
    {"id": "dashboard", "label": "Dashboard", "icon": "dashboard"},
    {"id": "chat", "label": "Chat Memory", "icon": "panel"},
    {"id": "personal", "label": "Personal Memory", "icon": "sparkles"},
    {"id": "conversations", "label": "Connected Conversations", "icon": "branch"},
    {"id": "diagnostics", "label": "Diagnostics", "icon": "chart"}
];
glob PAGE_IDS: list[str] = ["dashboard", "chat", "personal", "conversations", "diagnostics"];
glob COLLAPSED_KEY: str = "sherry.sidebar.collapsed";
glob PENDING_STORAGE_KEY: str = "sherry.pending.v1";


def page_from_hash -> str {
    wanted = str(window.location.hash or "").replace("#", "");
    return wanted if wanted in PAGE_IDS else "dashboard";
}


def read_flag(key: str) -> bool {
    try {
        return localStorage.getItem(key) == "1";
    } except Exception {
        return False;
    }
}


def write_flag(key: str, on: bool) {
    try {
        localStorage.setItem(key, "1" if on else "0");
    } except Exception { }
}


"""'mufaddal.k@x.com' -> 'Mufaddal.k'."""
def display_name(account: str) -> str {
    local = account.split("@")[0] if account else "You";
    return local[:1].upper() + local[1:];
}


def:pub Workspace(account: str, onSignOut: Callable[[], None]) -> JsxElement {
    has page: str = page_from_hash(),
        collapsed: bool = read_flag(COLLAPSED_KEY),
        nav_open: bool = False,
        connect_open: bool = False,
        epoch: int = 0;

    useEffect(
        lambda {
            on_hash = lambda (e: Event) { page = page_from_hash(); };
            window.addEventListener("hashchange", on_hash);
            return lambda { window.removeEventListener("hashchange", on_hash); };
        },
        []
    );

    def go(target: str) {
        nav_open = False;
        if target == page {
            return;
        }
        window.location.hash = target;
        page = target;
        window.scrollTo(0, 0);
    }

    def toggle_collapsed {
        collapsed = not collapsed;
        write_flag(COLLAPSED_KEY, collapsed);
    }

    async def sign_out -> None {
        try {
            localStorage.removeItem(PENDING_STORAGE_KEY);
        } except Exception { }
        await end_session();
        onSignOut();
    }

    """A call came back unauthorized: renew the login, or sign out if that fails."""
    async def handle_expired -> None {
        renewed = await refresh_session();
        if renewed {
            epoch = epoch + 1;
            return;
        }
        await end_session();
        onSignOut();
    }

    name = display_name(account);
    current = [p for p in PAGES if p["id"] == page][0];

    return
        <div className={"shell" + (" shell-collapsed" if collapsed else "") + (" shell-nav-open" if nav_open else "")}>
            <aside className="sidebar-col" aria-label="Sherry">
                <div className="sidebar">
                <div className="sidebar-top">
                    <span className="sidebar-brand">Sherry</span>
                    <button
                        type="button"
                        className="btn btn-ghost btn-icon btn-sm sidebar-collapse"
                        onClick={lambda e: MouseEvent { toggle_collapsed(); }}
                        aria-label={"Expand sidebar" if collapsed else "Collapse sidebar"}
                        title={"Expand" if collapsed else "Collapse"}
                    >
                        <Icon name={"chevron-right" if collapsed else "chevron-left"} size={16}/>
                    </button>
                </div>
                <nav className="sidebar-nav">
                    {for p in PAGES {
                        <button
                            key={str(p["id"])}
                            type="button"
                            className={"nav-item" + (" nav-item-active" if p["id"] == page else "")}
                            aria-current={"page" if p["id"] == page else "false"}
                            title={str(p["label"])}
                            onClick={lambda e: MouseEvent { go(str(p["id"])); }}
                        >
                            <Icon name={str(p["icon"])} size={18}/>
                            <span className="nav-label">{str(p["label"])}</span>
                        </button>
                    }}
                </nav>
                <div className="sidebar-foot">
                    <div className="sidebar-user">
                        <span className="avatar" aria-hidden="true">{name[:1]}</span>
                        <span className="sidebar-name" title={account}>{name}</span>
                        <button
                            type="button"
                            className="btn btn-ghost btn-icon btn-sm"
                            onClick={lambda e: MouseEvent { connect_open = True; }}
                            aria-label="Settings: connect apps and assistants"
                            title="Connect apps and assistants"
                        >
                            <Icon name="settings" size={18}/>
                        </button>
                    </div>
                    <button type="button" className="sidebar-signout" onClick={lambda e: MouseEvent { sign_out(); }}>
                        Sign out
                    </button>
                </div>
                </div>
            </aside>
            <div className="shell-main">
                <header className="mobile-bar">
                    <button
                        type="button"
                        className="btn btn-ghost btn-icon"
                        onClick={lambda e: MouseEvent { nav_open = not nav_open; }}
                        aria-label="Menu"
                        aria-expanded={"true" if nav_open else "false"}
                    >
                        <Icon name="menu"/>
                    </button>
                    <span className="sidebar-brand">Sherry</span>
                    <span className="mobile-bar-page">{str(current["label"])}</span>
                </header>
                {if page == "dashboard" {
                    <Dashboard key={"dashboard-" + str(epoch)} onNavigate={go} onExpired={handle_expired}/>
                } elif page == "chat" {
                    <Library key={"chat-" + str(epoch)} account={account} kind="chat" title="Chat Memory" onConnect={lambda { connect_open = True; }} onSignOut={onSignOut}/>
                } elif page == "personal" {
                    <Library key={"personal-" + str(epoch)} account={account} kind="personal" title="Personal Memory" onConnect={lambda { connect_open = True; }} onSignOut={onSignOut}/>
                } elif page == "conversations" {
                    <Conversations key={"conversations-" + str(epoch)} onConnect={lambda { connect_open = True; }} onExpired={handle_expired}/>
                } else {
                    <Diagnostics key={"diagnostics-" + str(epoch)} account={account} onConnect={lambda { connect_open = True; }} onExpired={handle_expired}/>
                }}
            </div>
            {if nav_open {
                <div key="scrim" className="nav-scrim" onClick={lambda e: MouseEvent { nav_open = False; }}/>
            }}
            {if connect_open {
                <ConnectPanel key="connect" account={account} onClose={lambda { connect_open = False; }}/>
            }}
        </div>;
}
