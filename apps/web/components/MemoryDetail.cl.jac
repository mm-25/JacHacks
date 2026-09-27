"""Full memory with provenance and a confirmed delete (FR-022, FR-050)."""

import from .Icon { Icon }
import from .SourceChip { SourceChip }
import from ..lib.format { full_time, platform_label, type_label, capture_label }

sv import from ..services.memories { MemoryView }
sv import from ..services.captures { ConversationView, get_conversation }

def:pub MemoryDetail(
    memory: MemoryView,
    deleting: bool,
    onClose: Callable[[], None],
    onDelete: Callable[[str], None]
) -> JsxElement {
    has confirming: bool = False,
        transcript: ConversationView | None = None,
        transcript_open: bool = False,
        transcript_loading: bool = False,
        transcript_error: str = "";

    # Reset per-memory UI whenever a different memory is opened.
    can with [memory.id] entry {
        confirming = False;
        transcript = None;
        transcript_open = False;
        transcript_error = "";
    }

    async def toggle_transcript -> None {
        view: ConversationView | None = None;
        if transcript_open {
            transcript_open = False;
            return;
        }
        transcript_open = True;
        transcript_loading = True;
        transcript_error = "";
        try {
            id = memory.source.conversationId or "";
            view = await get_conversation(id);
            transcript = view;
            if view is None {
                transcript_error = "The captured chat is no longer stored.";
            }
        } except Exception {
            transcript_error = "Couldn't load the captured chat. Try again.";
        }
        transcript_loading = False;
    }

    def handle_close(e: MouseEvent) {
        onClose();
    }

    def ask_delete(e: MouseEvent) {
        confirming = True;
    }

    def cancel_delete(e: MouseEvent) {
        confirming = False;
    }

    def confirm_delete(e: MouseEvent) {
        onDelete(memory.id);
    }

    src = memory.source;
    return
        <article className="detail" aria-labelledby="detail-heading">
            <div className="detail-top">
                <button
                    type="button"
                    className="btn btn-ghost btn-sm detail-back"
                    onClick={handle_close}
                >
                    <Icon name="back" size={16}/>
                    Library
                </button>
                <h2 id="detail-heading" className="sr-only">Memory details</h2>
                <SourceChip platform={src.platform}/>
                <span style={{"flex": "1"}}/>
                <button
                    type="button"
                    className="btn btn-ghost btn-sm"
                    onClick={ask_delete}
                    disabled={confirming or deleting}
                >
                    <Icon name="trash" size={16}/>
                    Delete
                </button>
                <button
                    type="button"
                    className="btn btn-ghost btn-icon btn-sm hide-narrow"
                    onClick={handle_close}
                    aria-label="Close details"
                >
                    <Icon name="x" size={16}/>
                </button>
            </div>
            {if confirming {
                <div
                    className="confirm"
                    role="alertdialog"
                    aria-labelledby="confirm-title"
                >
                    <p id="confirm-title" className="confirm-title">
                        Delete this memory?
                    </p>
                    <p>
                        It will disappear from Sherry on every device. You can undo right after.
                    </p>
                    <div className="confirm-actions">
                        <button
                            type="button"
                            className="btn"
                            onClick={cancel_delete}
                            autoFocus={True}
                        >
                            Keep it
                        </button>
                        <button
                            type="button"
                            className="btn btn-danger"
                            onClick={confirm_delete}
                            disabled={deleting}
                        >
                            {"Deleting…" if deleting else "Delete memory"}
                        </button>
                    </div>
                </div>
            }}
            <div className="detail-body">
                <p className="detail-content">{memory.content}</p>
                {if len(memory.tags) > 0 {
                    <div className="tags" style={{"marginBottom": "8px"}}>
                        {for t in memory.tags {
                            <span key={t} className="tag">{"#" + t}</span>
                        }}
                    </div>
                }}
            </div>
            <section className="provenance" aria-labelledby="prov-title">
                <h3 id="prov-title" className="provenance-title">Provenance</h3>
                <dl>
                    <dt>Source</dt>
                    <dd>{type_label(src.`type)}</dd>
                    <dt>Captured via</dt>
                    <dd>{capture_label(src.capturedVia)}</dd>
                    <dt>Platform</dt>
                    <dd>{platform_label(src.platform)}</dd>
                    {if src.label {
                        <dt key="label-t">Label</dt>
                        <dd key="label-d">{src.label}</dd>
                    }}
                    {if src.url {
                        <dt key="link-t">Link</dt>
                        <dd key="link-d">
                            <a href={src.url} target="_blank" rel="noopener noreferrer">
                                {src.url}
                            </a>
                        </dd>
                    }}
                    <dt>Saved</dt>
                    <dd>
                        <time dateTime={memory.createdAt}>
                            {full_time(memory.createdAt)}
                        </time>
                    </dd>
                    {if memory.updatedAt != memory.createdAt {
                        <dt key="upd-t">Updated</dt>
                        <dd key="upd-d">
                            <time dateTime={memory.updatedAt}>
                                {full_time(memory.updatedAt)}
                            </time>
                        </dd>
                    }}
                    <dt>ID</dt>
                    <dd className="mono">{memory.id}</dd>
                </dl>
            </section>
            {if src.conversationId {
                <section
                    key="transcript"
                    className="transcript"
                    aria-label="Captured chat"
                >
                    <button
                        type="button"
                        className="btn btn-sm"
                        onClick={lambda e: MouseEvent { toggle_transcript(); }}
                        aria-expanded={"true" if transcript_open else "false"}
                    >
                        {"Hide captured chat"
                            if transcript_open
                            else "Show captured chat"}
                    </button>
                    {if transcript_open and transcript_loading {
                        <p key="loading" className="transcript-meta">Loading…</p>
                    } elif transcript_open and transcript_error {
                        <p key="error" className="transcript-meta">
                            {transcript_error}
                        </p>
                    } elif transcript_open and transcript is not None {
                        <div key="body">
                            <p className="transcript-meta">
                                {str(transcript.messageCount) + " messages captured"}{" · summarized " + full_time(
                                    transcript.summarizedAt or ""
                                )
                                    if transcript.summarizedAt
                                    else ""}{" · " + (transcript.summaryNote or "")
                                    if transcript.summaryNote
                                    else ""}
                            </p>
                            <ol className="transcript-list">
                                {for m in transcript.messages {
                                    <li
                                        key={str(m.position) + m.role}
                                        className={"transcript-msg transcript-" + m.role}
                                    >
                                        <span className="transcript-role">
                                            {"You"
                                                if m.role == "user"
                                                else platform_label(
                                                    transcript.platform
                                                )}
                                        </span>
                                        <p>{m.text}</p>
                                    </li>
                                }}
                            </ol>
                        </div>
                    }  }
                </section>
            }}
        </article>;
}
