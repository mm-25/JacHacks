"""Handler bodies for the Library shell (see Library.cl.jac)."""

# Imports used here are declared in Library.cl.jac (the annex shares its scope).

# ---------- Loading ----------
impl Library.refresh(background: bool) -> None {
    page: MemoryPage | None = None;
    request_seq.current = (request_seq.current or 0) + 1;
    my_seq = request_seq.current;
    cursor = "";
    limit = max(PAGE_SIZE, len(memories));
    if not background {
        syncing = True;
    }
    try {
        # Reads are cached client-side for 60s; a sync must hit the server.
        __jacClearCache();
        page = await list_memories(query, cursor, limit, kind);
        if my_seq != request_seq.current {
            return;
        }
        if page is not None {
            memories = page.data;
            total = page.total;
            next_cursor = page.nextCursor;
        }
        load_error = False;
        last_synced = now_ms();
    } except Exception as err {
        if my_seq != request_seq.current {
            return;
        }
        if "nauthorized" in str(err) {
            handle_expired();
            return;
        }
        load_error = True;
    }
    loading = False;
    syncing = False;
}

impl Library.load_more -> None {
    page: MemoryPage | None = None;
    if not next_cursor {
        return;
    }
    cursor = next_cursor;
    limit = PAGE_SIZE;
    loading_more = True;
    try {
        page = await list_memories(query, cursor, limit, kind);
        if page is not None {
            seen = [m.id for m in memories];
            fresh: list[MemoryView] = page.data;
            memories = memories + [
                m
                for m in fresh
                if m.id not in seen
            ];
            next_cursor = page.nextCursor;
            total = page.total;
        }
    } except Exception {
        toast = {"message": "Couldn't load more. Try again in a moment.", "undo": ""};
    }
    loading_more = False;
}

# ---------- Capture + offline queue ----------
impl Library.save_new(content: str, tags: list[str], source: str, label: str) -> None {
    is_note = source == "web";
    key = new_idempotency_key();
    item = {
        "key": key,
        "content": content,
        "tags": tags,
        "source_type": "manual_note" if is_note else "conversation_excerpt",
        "source_platform": source,
        "source_label": (label or "Quick capture") if is_note else label,
        "created_at": now_iso(),
        "state": "saving",
        "error": ""
    };
    set_pending([item] + (pending_ref.current or []));
    await send_pending(key);
}

impl Library.send_pending(key: str) -> None {
    result: MemoryView | None = None;
    matches = [
        p
        for p in (pending_ref.current or [])
        if p["key"] == key
    ];
    if len(matches) == 0 {
        return;
    }
    item = matches[0];
    if not is_online() {
        update_pending(key, "offline", "");
        return;
    }
    update_pending(key, "saving", "");
    # Local names must match the server parameter names (they become JSON keys).
    content = str(item["content"]);
    source_platform = str(item["source_platform"]);
    idempotency_key = key;
    tags: list[str] = (item["tags"] or []) as list[str];
    source_type = str(item["source_type"]);
    source_label = str(item["source_label"] or "");
    source_url = "";
    try {
        result = await create_memory(
            content,
            source_platform,
            idempotency_key,
            tags,
            source_type,
            source_label,
            source_url
        );
        if result is not None and result.id {
            set_pending(
                [
                    p
                    for p in (pending_ref.current or [])
                    if p["key"] != key
                ]
            );
            await refresh(True);
            return;
        }
        update_pending(
            key, "failed", "Sherry couldn't accept this memory. Edit it and try again."
        );
    } except Exception as err {
        if "nauthorized" in str(err) {
            handle_expired();
            return;
        }
        if not is_online() {
            update_pending(key, "offline", "");
        } else {
            update_pending(
                key,
                "failed",
                "Couldn't reach Sherry. Your text is kept here - retry when ready."
            );
        }
    }
}

impl Library.flush_pending{
    for p in (pending_ref.current or []) {
        if p["state"] != "saving" {
            send_pending(str(p["key"]));
        }
    }
}

impl Library.restore_pending{
    # Anything that was mid-flight when the tab closed is retried.
    restored = [
        {** p, "state": "offline"}
        for p in load_list(PENDING_STORAGE_KEY)
        if p["key"]
    ];
    if len(restored) > 0 {
        set_pending(restored);
    }
}

impl Library.set_pending(items: list[dict]) {
    pending_ref.current = items;
    pending = items;
    save_list(PENDING_STORAGE_KEY, items);
}

impl Library.update_pending(key: str, state: str, error: str) {
    set_pending(
        [
            {** p, "state": state, "error": error} if p["key"] == key else p
            for p in (pending_ref.current or [])
        ]
    );
}

impl Library.discard_pending(key: str) {
    set_pending(
        [
            p
            for p in (pending_ref.current or [])
            if p["key"] != key
        ]
    );
}

# ---------- Delete / undo / reset ----------
impl Library.remove_memory(id: str) -> None {
    ok: bool = False;
    deleting = True;
    try {
        ok = await delete_memory(id);
    } except Exception as err {
        if "nauthorized" in str(err) {
            handle_expired();
            return;
        }
        deleting = False;
        toast = {
            "message": "Couldn't delete - check your connection and try again.",
            "undo": ""
        };
        return;
    }
    deleting = False;
    selected_id = "";
    if ok {
        memories = [
            m
            for m in memories
            if m.id != id
        ];
        total = max(0, total - 1);
        toast = {"message": "Memory deleted everywhere.", "undo": id};
    } else {
        toast = {"message": "That memory was already deleted.", "undo": ""};
    }
    refresh(True);
}

impl Library.undo_delete(id: str) -> None {
    restored: MemoryView | None = None;
    toast = None;
    try {
        restored = await restore_memory(id);
        if restored is not None {
            selected_id = restored.id;
        }
        await refresh(True);
    } except Exception {
        toast = {"message": "Couldn't undo - check your connection.", "undo": ""};
    }
}

impl Library.reset_workspace -> None {
    page: MemoryPage | None = None;
    menu_open = False;
    if not ask_confirm(
        "Reset this workspace to the demo data? Your memories here will be replaced."
    ) {
        return;
    }
    syncing = True;
    try {
        page = await reset_demo();
        if page is not None {
            memories = page.data;
            total = page.total;
            next_cursor = page.nextCursor;
        }
        query = "";
        selected_id = "";
        set_pending([]);
        last_synced = now_ms();
        load_error = False;
        toast = {"message": "Workspace reset to demo data.", "undo": ""};
    } except Exception {
        toast = {"message": "Couldn't reset right now.", "undo": ""};
    }
    syncing = False;
}

# ---------- Session / navigation ----------
impl Library.sign_out -> None {
    menu_open = False;
    set_pending([]);
    await end_session();
    onSignOut();
}

"""A request came back unauthorized: the login token may just have expired
(e.g. the laptop slept). Renew it and retry; sign out only if that fails."""
impl Library.handle_expired -> None {
    renewed = await refresh_session();
    if renewed {
        tick = now_ms();
        return;
    }
    await end_session();
    onSignOut();
}

impl Library.handle_global_key(e: KeyboardEvent) {
    typing = is_typing();
    if e.key == "/" and not typing {
        e.preventDefault();
        focus_element("search");
    } elif e.key == "Escape" {
        menu_open = False;
        if not typing {
            selected_id = "";
        }
    }
}

impl Library.open_memory(id: str) {
    selected_id = id;
    menu_open = False;
    if is_narrow() {
        scroll_top();
    }
}

impl Library.close_detail{
    selected_id = "";
}
