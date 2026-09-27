"""One memory in the library list: preview, source, timestamp, tags."""

import from .SourceChip { SourceChip }
import from ..lib.format { relative_time, full_time, capture_badge }

sv import from ..services.memories { MemoryView }

def:pub MemoryCard(
    memory: MemoryView, selected: bool, now_ms: float, onOpen: Callable[[str], None]
) -> JsxElement {
    def handle_open(e: MouseEvent) {
        onOpen(memory.id);
    }

    label = memory.source.label;
    badge = capture_badge(memory.source.capturedVia);
    return
        <button
            type="button"
            className={"card card-selected" if selected else "card"}
            onClick={handle_open}
            aria-current={"true" if selected else "false"}
        >
            <p className="card-content">{memory.content}</p>
            <div className="card-meta">
                <SourceChip platform={memory.source.platform}/>
                {if badge {
                    <span key="via" className="via-badge">{badge}</span>
                }}
                {if label {
                    <span key="label">{label}</span>
                    <span key="label-sep" className="card-meta-sep" aria-hidden="true">
                        ·
                    </span>
                }}
                <time dateTime={memory.createdAt} title={full_time(memory.createdAt)}>
                    {relative_time(memory.createdAt, now_ms)}
                </time>
                {if len(memory.tags) > 0 {
                    <span key="tags-sep" className="card-meta-sep" aria-hidden="true">
                        ·
                    </span>
                    <span key="tags" className="tags">
                        {for t in memory.tags[:3] {
                            <span key={t} className="tag">{"#" + t}</span>
                        }}
                    </span>
                }}
            </div>
        </button>;
}
