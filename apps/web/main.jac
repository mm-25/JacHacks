"""Sherry web - entry point.

Server endpoints live in services/; the browser UI lives in components/.
"""

# Import every endpoint explicitly so each one registers at /function/<name>
# for all clients (web, desktop, mobile).
import from services.memories {
    health,
    list_memories,
    get_memory,
    create_memory,
    delete_memory,
    restore_memory,
    reset_demo,
    load_demo_data,
    MemoryView,
    MemorySource,
    MemoryPage,
    HealthStatus
}
import from services.captures {
    capture_conversation,
    summarize_conversation,
    get_conversation,
    CaptureResult,
    SummaryResult,
    ConversationView,
    TranscriptMessage
}

cl {
    import "./styles/global.css";
    import from .components.SherryApp { SherryApp }

    def:pub app -> JsxElement {
        return <SherryApp/>;
    }
}
