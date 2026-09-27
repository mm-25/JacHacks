"""Dashboard: live activity, memory usage and AI patterns, from one
`dashboard_stats` call (apps/cloud/src/dashboard.cl.jac), refreshed every 30s
while the tab is visible. Each card's arrow opens the page with the details."""

import from react { useEffect }
import from .Icon { Icon }
import from ..lib.cloud { call_cloud }
import from ..lib.format { platform_label }
import from ..lib.browser { page_hidden }

glob REFRESH_MS: int = 30000;


def plural(n: int, one: str, many: str) -> str {
    return str(n) + " " + (one if n == 1 else many);
}


def two_digits(i: int) -> str {
    return ("0" + str(i)) if i < 10 else str(i);
}


def percent_of(n: int, top: int) -> str {
    if top <= 0 {
        return "0%";
    }
    return str(Math.max(2, Math.round(n * 100 / top))) + "%";
}


def CardHead(eyebrow: str, title: str, target: str, onNavigate: Callable[[str], None]) -> JsxElement {
    return
        <div className="dash-card-head">
            <div className="dash-eyebrow-row">
                <span className="dash-eyebrow">{eyebrow}</span>
                <button
                    type="button"
                    className="dash-open"
                    aria-label={"Open " + (title or eyebrow)}
                    title="Open"
                    onClick={lambda e: MouseEvent { onNavigate(target); }}
                >
                    <Icon name="arrow-up-right" size={18}/>
                </button>
            </div>
            {if title {
                <h2 key="t" className="dash-title">{title}</h2>
            }}
        </div>;
}


def Bar(label: str, value: str, n: int, top: int) -> JsxElement {
    return
        <div className="dash-bar">
            <div className="dash-row">
                <span className="dash-row-label">{label}</span>
                <span className="dash-row-value">{value}</span>
            </div>
            <div className="dash-track">
                <div className="dash-fill" style={{"width": percent_of(n, top)}}/>
            </div>
        </div>;
}


def Empty(title: str, text: str) -> JsxElement {
    return
        <div className="dash-empty">
            <p className="dash-empty-title">{title}</p>
            <p>{text}</p>
        </div>;
}


def:pub Dashboard(onNavigate: Callable[[str], None], onExpired: Callable[[], None]) -> JsxElement {
    has stats: dict | None = None,
        error: str = "";

    async def load -> None {
        got = await call_cloud("dashboard_stats", {});
        if got["ok"] {
            stats = got["result"] as dict;
            error = "";
        } elif "session" in str(got["error"]) {
            onExpired();
        } else {
            error = str(got["error"]);
        }
    }

    useEffect(
        lambda {
            load();
            timer = setInterval(lambda { if not page_hidden() { load(); } }, REFRESH_MS);
            return lambda { clearInterval(timer); };
        },
        []
    );

    header =
        <header className="page-head">
            <h1 className="page-title">Dashboard</h1>
            <p className="page-sub">
                Live activity, memory usage, and AI patterns from your captured conversations.
            </p>
        </header>;

    if stats is None {
        return
            <div className="page">
                {header}
                {if error {
                    <div key="err" className="alert alert-error" role="alert">
                        <span className="alert-body">{error}</span>
                        <button type="button" className="btn btn-sm" onClick={lambda e: MouseEvent { load(); }}>
                            Retry
                        </button>
                    </div>
                } else {
                    <div key="loading" className="dash-grid" aria-busy="true" aria-label="Loading dashboard">
                        {for i in [1, 2, 3, 4, 5, 6, 7, 8, 9] {
                            <div key={str(i)} className="dash-card dash-card-loading"/>
                        }}
                    </div>
                }}
            </div>;
    }

    s: any = stats;
    chats: list = list(s.chatsByPlatform or []);
    mix: list = list(s.toolMix or []);
    top_memories: list = list(s.topMemories or []);
    use_cases: list = list(s.useCases or []);
    lookups: list = list(s.lookups or []);
    health: any = s.health or {};
    checks: list = list(health.checks or []);
    ready = int(health.ready or 0);
    total_checks = int(health.total or 0);
    top_platform: any = s.topPlatform;
    next_platform: any = s.nextPlatform;
    case_top = int(use_cases[0]["count"]) if len(use_cases) > 0 else 0;
    lookup_top = int(lookups[0]["count"]) if len(lookups) > 0 else 0;
    attention = "";
    for c in checks {
        if c["status"] != "ok" {
            attention += (", " if attention else "") + str(c["name"]).lower();
        }
    }

    return
        <div className="page">
            {header}
            {if error {
                <div key="stale" className="alert alert-warn" role="status">
                    <span className="alert-body">Can't refresh right now. Showing the last numbers.</span>
                </div>
            }}
            <div className="dash-grid">
                <section className="dash-card">
                    <CardHead eyebrow="Total chats" title="Chats across all AI tools" target="conversations" onNavigate={onNavigate}/>
                    <div className="dash-big-row">
                        <span className="dash-big">{str(s.totalChats)}</span>
                        <span className="dash-big-caption">captured conversations</span>
                    </div>
                    {if len(chats) == 0 {
                        <Empty key="e" title="No chats yet" text="Install the browser extension or desktop app to capture chats."/>
                    } else {
                        <ul key="l" className="dash-list">
                            {for c in chats {
                                <li key={str(c["platform"])} className="dash-row dash-row-line">
                                    <span className="dash-row-label">{platform_label(str(c["platform"]))}</span>
                                    <span className="dash-row-value">{plural(int(c["count"]), "chat", "chats")}</span>
                                </li>
                            }}
                        </ul>
                    }}
                </section>

                <section className="dash-card">
                    <CardHead eyebrow="Most used memories" title="Memories recalled most often" target="personal" onNavigate={onNavigate}/>
                    {if len(top_memories) == 0 {
                        <Empty key="e" title="No recalls yet" text="Each time Claude, ChatGPT or Gemini pulls a memory from Sherry, it counts here."/>
                    } else {
                        <ol key="l" className="dash-list">
                            {for (i, m) in enumerate(top_memories) {
                                <li key={str(m["id"])} className="dash-row dash-row-line">
                                    <span className="dash-rank">{two_digits(i + 1)}</span>
                                    <span className="dash-row-label dash-ellipsis" title={str(m["text"])}>{str(m["text"])}</span>
                                    <span className="dash-row-value">{plural(int(m["recalls"]), "recall", "recalls")}</span>
                                </li>
                            }}
                        </ol>
                    }}
                </section>

                <section className="dash-card">
                    <CardHead eyebrow="AI tool mix" title="Which AI tools you use and how much" target="conversations" onNavigate={onNavigate}/>
                    {if len(mix) == 0 {
                        <Empty key="e" title="Nothing to compare yet" text="Chats, saves and lookups from each assistant show up here."/>
                    } else {
                        <div key="l" className="dash-bars">
                            {for m in mix {
                                <Bar key={str(m["platform"])} label={platform_label(str(m["platform"]))} value={str(m["percent"]) + "%"} n={int(m["percent"])} top={100}/>
                            }}
                        </div>
                    }}
                </section>

                <section className="dash-card">
                    <CardHead eyebrow="AI use cases" title="What you use AI for" target="chat" onNavigate={onNavigate}/>
                    <p className="dash-note">
                        {"Based on " + str(s.summarizedChats) + " of " + str(s.totalChats) + " captured chats with active summaries."}
                    </p>
                    {if len(use_cases) == 0 {
                        <Empty key="e" title="No summaries yet" text="Chats get summarized after they go quiet for a moment."/>
                    } else {
                        <div key="l" className="dash-bars">
                            {for u in use_cases {
                                <Bar key={str(u["label"])} label={str(u["label"])} value={plural(int(u["count"]), "summary", "summaries")} n={int(u["count"])} top={case_top}/>
                            }}
                        </div>
                    }}
                </section>

                <section className="dash-card">
                    <CardHead eyebrow="Tool by use case" title="Which AI you use for each use case" target="chat" onNavigate={onNavigate}/>
                    {if len(use_cases) == 0 {
                        <Empty key="e" title="No use cases yet" text="Shows up once your chats have summaries."/>
                    } else {
                        <ul key="l" className="dash-list">
                            {for u in use_cases {
                                <li key={str(u["label"])} className="dash-row dash-row-line">
                                    <span className="dash-row-label">{str(u["label"])}</span>
                                    <span className="dash-row-value">{platform_label(str(u["platform"]))}</span>
                                </li>
                            }}
                        </ul>
                    }}
                </section>

                <section className="dash-card">
                    <CardHead eyebrow="Memory retrieval by AI" title="Memory lookups by AI" target="diagnostics" onNavigate={onNavigate}/>
                    {if len(lookups) == 0 {
                        <Empty key="e" title="No lookups yet" text="Connect Claude or ChatGPT to Sherry and they'll look up your memories on their own."/>
                    } else {
                        <div key="l" className="dash-bars">
                            {for l in lookups {
                                <Bar key={str(l["platform"])} label={platform_label(str(l["platform"]))} value={plural(int(l["count"]), "lookup", "lookups")} n={int(l["count"])} top={lookup_top}/>
                            }}
                        </div>
                    }}
                </section>

                <section className="dash-card">
                    <CardHead eyebrow="Top platform" title="Platform and AI used most" target="conversations" onNavigate={onNavigate}/>
                    {if top_platform {
                        <div key="t" className="dash-bottom">
                            <div className="dash-feature">
                                <div className="dash-feature-name">{platform_label(str(top_platform.platform))}</div>
                                <div className="dash-feature-sub">
                                    {str(top_platform.channel) + " · " + plural(int(top_platform.count), "conversation", "conversations")}
                                </div>
                            </div>
                            {if next_platform {
                                <p key="n" className="dash-note">
                                    {"Next: " + platform_label(str(next_platform.platform)) + " on " + str(next_platform.channel) + " (" + str(next_platform.count) + ")"}
                                </p>
                            }}
                        </div>
                    } else {
                        <Empty key="e" title="No chats yet" text="Your most used assistant shows up here."/>
                    }}
                </section>

                <section className="dash-card">
                    <CardHead eyebrow="Artifacts" title="Created artifacts by type" target="conversations" onNavigate={onNavigate}/>
                    <div className="dash-placeholder">
                        <p className="dash-empty-title">No artifact data yet</p>
                        <p>Artifact metadata is not indexed yet. Sherry will show types here once capture supports it.</p>
                    </div>
                </section>

                <section className="dash-card">
                    <CardHead eyebrow="Pipeline health" title="" target="diagnostics" onNavigate={onNavigate}/>
                    <div className="dash-big-row">
                        <span className="dash-big">{str(ready) + "/" + str(total_checks)}</span>
                        <span className="dash-big-caption">systems ready</span>
                    </div>
                    <div className="dash-segments" aria-hidden="true">
                        {for c in checks {
                            <span key={str(c["id"])} className={"dash-segment" + ("" if c["status"] == "ok" else " dash-segment-warn")} title={str(c["name"])}/>
                        }}
                    </div>
                    <p className="dash-health-text">
                        {"Everything is running normally" if not attention else "Needs attention: " + attention}
                    </p>
                </section>
            </div>
        </div>;
}
