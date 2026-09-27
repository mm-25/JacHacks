"""Capture box. Type, then press Save (or Cmd/Ctrl+Enter): two actions max.

The draft is handed to the library immediately and shown as a pending card,
so text is never lost if the network fails (AT-06)."""

import from ..lib.format { parse_tags }

glob MAX_CONTENT: int = 20000;

glob SOURCE_OPTIONS: list[dict[str, str]] = [
         {"value": "web", "label": "Note"},
         {"value": "chatgpt", "label": "From ChatGPT"},
         {"value": "claude", "label": "From Claude"},
         {"value": "gemini", "label": "From Gemini"}
     ];

def:pub Composer(onSave: Callable[[str, list[str], str, str], None]) -> JsxElement {
    has content: str = "",
        tags_raw: str = "",
        source: str = "web",
        label: str = "";

    trimmed = content.strip();
    too_long = len(content) > MAX_CONTENT;
    can_save = len(trimmed) > 0 and not too_long;
    is_excerpt = source != "web";

    def submit {
        if not can_save {
            return;
        }
        onSave(trimmed, parse_tags(tags_raw), source, label.strip());
        content = "";
        tags_raw = "";
        label = "";
    }

    def handle_submit(e: FormEvent) {
        e.preventDefault();
        submit();
    }

    def handle_keydown(e: KeyboardEvent) {
        if e.key == "Enter" and (e.metaKey or e.ctrlKey) {
            e.preventDefault();
            submit();
        }
    }

    return
        <form className="composer" onSubmit={handle_submit} aria-label="Save a memory">
            <label htmlFor="composer-text" className="sr-only">Memory</label>
            <textarea
                id="composer-text"
                className="textarea"
                placeholder={"Paste the part of the conversation worth keeping…"
                    if is_excerpt
                    else "Save something worth remembering…"}
                value={content}
                onChange={lambda e: ChangeEvent { content = e.target.value; }}
                onKeyDown={handle_keydown}
                rows={3}
            />
            <div className="composer-row">
                <label htmlFor="composer-source" className="sr-only">Source</label>
                <select
                    id="composer-source"
                    className="select composer-source"
                    value={source}
                    onChange={lambda e: ChangeEvent { source = e.target.value; }}
                >
                    {for opt in SOURCE_OPTIONS {
                        <option key={opt["value"]} value={opt["value"]}>
                            {opt["label"]}
                        </option>
                    }}
                </select>
                <label htmlFor="composer-tags" className="sr-only">Tags</label>
                <input
                    id="composer-tags"
                    className="input composer-tags"
                    placeholder="Tags, e.g. preference, project"
                    value={tags_raw}
                    onChange={lambda e: ChangeEvent { tags_raw = e.target.value; }}
                />
                {if is_excerpt {
                    <label key="lbl" htmlFor="composer-label" className="sr-only">
                        Conversation title
                    </label>
                    <input
                        key="inp"
                        id="composer-label"
                        className="input composer-label"
                        placeholder="Conversation title (optional)"
                        maxLength={120}
                        value={label}
                        onChange={lambda e: ChangeEvent { label = e.target.value; }}
                    />
                }}
            </div>
            <div className="composer-footer">
                <span className="composer-hint hide-narrow">
                    ⌘/Ctrl + Enter to save
                </span>
                {if len(content) > MAX_CONTENT - 1000 {
                    <span
                        className={"char-count char-count-over"
                            if too_long
                            else "char-count"}
                    >
                        {str(len(content)) + " / " + str(MAX_CONTENT)}
                    </span>
                }}
                <button
                    type="submit"
                    className="btn btn-primary"
                    disabled={not can_save}
                >
                    Save memory
                </button>
            </div>
        </form>;
}
