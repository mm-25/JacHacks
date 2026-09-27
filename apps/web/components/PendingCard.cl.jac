"""A capture that has not reached the server yet.

States: `saving` (request in flight), `offline` (queued until the browser is
back online) and `failed` (server refused or unreachable - the text is kept
and the user can retry with the same idempotency key, or discard it)."""

import from .SourceChip { SourceChip }

def:pub PendingCard(
    item: dict, onRetry: Callable[[str], None], onDiscard: Callable[[str], None]
) -> JsxElement {
    state = str(item["state"]);
    key = str(item["key"]);
    error = str(item["error"] or "");

    def handle_retry(e: MouseEvent) {
        onRetry(key);
    }

    def handle_discard(e: MouseEvent) {
        onDiscard(key);
    }

    state_label = "Saving…";
    if state == "offline" {
        state_label = "Offline · will sync when you reconnect";
    } elif state == "failed" {
        state_label = "Not saved";
    }

    return
        <div
            className={"card card-pending card-failed"
                if state == "failed"
                else "card card-pending"}
            role="status"
        >
            <p className="card-content">{item["content"]}</p>
            <div className="card-meta">
                <SourceChip platform={str(item["source_platform"])}/>
                <span className={"state state-" + state}>
                    <span className="sync-dot"/>
                    {state_label}
                </span>
            </div>
            {if state == "failed" and error {
                <p className="card-meta" style={{"marginTop": "8px"}}>{error}</p>
            }}
            {if state != "saving" {
                <div className="card-actions">
                    <button type="button" className="btn btn-sm" onClick={handle_retry}>
                        Retry now
                    </button>
                    <button
                        type="button"
                        className="btn btn-sm btn-ghost"
                        onClick={handle_discard}
                    >
                        Discard
                    </button>
                </div>
            }}
        </div>;
}
