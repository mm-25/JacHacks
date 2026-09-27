"""Honest sync label for the top bar: Synced / Syncing / Offline / Can't reach
Sherry (with Retry). Plain words, per the product's 'honest states' rule."""

import from ..lib.format { relative_time }

def:pub SyncStatus(
    online: bool,
    syncing: bool,
    has_error: bool,
    unsaved: int,
    last_synced: float,
    now_ms: float,
    onRetry: Callable[[], None]
) -> JsxElement {
    def handle_retry(e: MouseEvent) {
        onRetry();
    }

    if not online {
        return
            <span className="sync sync-offline" role="status">
                <span className="sync-dot"/>
                Offline
            </span>;
    }
    if has_error {
        return
            <span className="sync sync-error" role="status">
                <span className="sync-dot"/>
                <span>Can't reach Sherry</span>
                <button type="button" className="link-btn" onClick={handle_retry}>
                    Retry
                </button>
            </span>;
    }
    if unsaved > 0 {
        return
            <span className="sync sync-error" role="status">
                <span className="sync-dot"/>
                {str(unsaved) + (" memory" if unsaved == 1 else " memories") + " not saved"}
            </span>;
    }
    if syncing or last_synced == 0 {
        return
            <span className="sync sync-syncing" role="status">
                <span className="sync-dot"/>
                Syncing…
            </span>;
    }
    synced_iso = new(Date, last_synced).toISOString();
    return
        <span className="sync sync-synced" role="status">
            <span className="sync-dot"/>
            Synced
            <span className="sync-text-muted hide-narrow">
                {relative_time(synced_iso, now_ms)}
            </span>
        </span>;
}
