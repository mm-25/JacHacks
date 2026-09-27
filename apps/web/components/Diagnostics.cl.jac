"""Diagnostics: each part of the Sherry pipeline with its status, plus
lookup counts and the demo reset. Uses the same `dashboard_stats` call as the
Dashboard."""

import from react { useEffect }
import from ..lib.cloud { call_cloud }
import from ..lib.format { platform_label, relative_time }
import from ..lib.browser { now_ms, ask_confirm }
import from ..lib.demo { is_demo_account }


def:pub Diagnostics(account: str, onConnect: Callable[[], None], onExpired: Callable[[], None]) -> JsxElement {
    has stats: dict | None = None,
        error: str = "",
        loading: bool = True,
        message: str = "";

    async def load -> None {
        loading = True;
        got = await call_cloud("dashboard_stats", {});
        loading = False;
        if got["ok"] {
            stats = got["result"] as dict;
            error = "";
        } elif "session" in str(got["error"]) {
            onExpired();
        } else {
            error = str(got["error"]);
        }
    }

    async def reset -> None {
        if not ask_confirm("Reset this workspace to the demo data? Your memories here will be replaced.") {
            return;
        }
        got = await call_cloud("reset_demo", {});
        message = "Workspace reset to demo data." if got["ok"] else str(got["error"]);
        load();
    }

    useEffect(
        lambda {
            load();
            return lambda { };
        },
        []
    );

    s: any = stats or {};
    health: any = s.health or {};
    checks: list = list(health.checks or []);
    lookups: list = list(s.lookups or []);
    now = now_ms();

    return
        <div className="page">
            <header className="page-head page-head-row">
                <div>
                    <h1 className="page-title">Diagnostics</h1>
                    <p className="page-sub">Whether each part of Sherry is working, and what to do when it isn't.</p>
                </div>
                <button type="button" className="btn" onClick={lambda e: MouseEvent { load(); }} disabled={loading}>
                    {"Checking…" if loading else "Check again"}
                </button>
            </header>
            {if error {
                <div key="err" className="alert alert-error" role="alert">
                    <span className="alert-body">{error}</span>
                </div>
            }}
            {if message {
                <div key="msg" className="alert alert-warn" role="status">
                    <span className="alert-body">{message}</span>
                </div>
            }}
            <section className="dash-card">
                <div className="dash-eyebrow-row">
                    <span className="dash-eyebrow">Pipeline health</span>
                </div>
                <h2 className="dash-title">
                    {(str(health.ready) + " of " + str(health.total) + " systems ready") if stats else "Checking systems…"}
                </h2>
                <ul className="diag-list">
                    {for c in checks {
                        <li key={str(c["id"])} className="diag-row">
                            <span className={"diag-dot" + ("" if c["status"] == "ok" else " diag-dot-warn")} aria-hidden="true"/>
                            <div className="diag-text">
                                <div className="diag-name">{str(c["name"])}</div>
                                <div className="diag-detail">
                                    {str(c["detail"]) + ((" " + relative_time(str(c["at"]), now)) if c["at"] else "")}
                                </div>
                            </div>
                            <span className={"diag-status" + ("" if c["status"] == "ok" else " diag-status-warn")}>
                                {"Ready" if c["status"] == "ok" else "Needs attention"}
                            </span>
                            {if c["status"] != "ok" and (c["id"] == "connector" or c["id"] == "capture") {
                                <button key="fix" type="button" className="btn btn-sm" onClick={lambda e: MouseEvent { onConnect(); }}>
                                    Connect
                                </button>
                            }}
                        </li>
                    }}
                </ul>
            </section>
            <section className="dash-card">
                <div className="dash-eyebrow-row">
                    <span className="dash-eyebrow">Memory retrieval</span>
                </div>
                <h2 className="dash-title">Lookups by assistant</h2>
                {if len(lookups) == 0 {
                    <p key="e" className="dash-note">No assistant has looked up a memory yet.</p>
                } else {
                    <ul key="l" className="dash-list">
                        {for l in lookups {
                            <li key={str(l["platform"])} className="dash-row dash-row-line">
                                <span className="dash-row-label">{platform_label(str(l["platform"]))}</span>
                                <span className="dash-row-value">{str(l["count"]) + (" lookup" if l["count"] == 1 else " lookups")}</span>
                            </li>
                        }}
                    </ul>
                }}
            </section>
            {if is_demo_account(account) {
                <section key="demo" className="dash-card">
                    <div className="dash-eyebrow-row">
                        <span className="dash-eyebrow">Demo account</span>
                    </div>
                    <h2 className="dash-title">Reset to demo data</h2>
                    <p className="dash-note">Replaces this workspace's memories with the demo set.</p>
                    <div>
                        <button type="button" className="btn" onClick={lambda e: MouseEvent { reset(); }}>
                            Reset to demo data
                        </button>
                    </div>
                </section>
            }}
        </div>;
}
