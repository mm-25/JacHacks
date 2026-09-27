"""Typed wrappers over browser globals, so handler annexes stay type-checked."""

def:pub now_ms -> float {
    return Date.now();
}


def:pub now_iso -> str {
    return new(Date).toISOString();
}


def:pub is_online -> bool {
    g: any = globalThis;
    nav: any = g.navigator;
    return bool(nav.onLine) if nav else True;
}


def:pub page_hidden -> bool {
    g: any = globalThis;
    doc: any = g.document;
    return bool(doc.hidden) if doc else False;
}


def:pub is_narrow -> bool {
    return window.innerWidth < 900;
}


def:pub scroll_top {
    window.scrollTo(0, 0);
}


def:pub ask_confirm(message: str) -> bool {
    return bool(window.confirm(message));
}


"""True when focus is in a text field, so global shortcuts don't hijack typing."""
def:pub is_typing -> bool {
    g: any = globalThis;
    doc: any = g.document;
    el: any = doc.activeElement if doc else None;
    if not el {
        return False;
    }
    tag = str(el.tagName).lower();
    return tag == "input"
    or tag == "textarea"
    or tag == "select"
    or bool(el.isContentEditable);
}


def:pub focus_element(id: str) {
    g: any = globalThis;
    doc: any = g.document;
    el: any = doc.getElementById(id);
    if el {
        el.focus();
    }
}


def:pub load_list(key: str) -> list[dict] {
    try {
        raw = localStorage.getItem(key);
        if not raw {
            return [];
        }
        g: any = globalThis;
        j: any = g.JSON;
        parsed: any = j.parse(raw);
        if Array.isArray(parsed) {
            return parsed as list[dict];
        }
        return [];
    } except Exception {
        return [];
    }
}


def:pub save_list(key: str, items: list[dict]) {
    try {
        if len(items) > 0 {
            g: any = globalThis;
            j: any = g.JSON;
            localStorage.setItem(key, str(j.stringify(items)));
        } else {
            localStorage.removeItem(key);
        }
    } except Exception { }
}


"""The signed-in account's API key (Jac's per-account token). In this server
mode it is created at sign-up and never expires, so it doubles as the key the
Sherry MCP server uses to act on this user's behalf."""
def:pub api_key -> str {
    return str(localStorage.getItem("jac_token") or "");
}


"""Where this Sherry server is reachable from the browser's point of view."""
def:pub api_origin -> str {
    return str(window.location.origin);
}


"""Copy text to the clipboard; returns False when the browser refuses."""
async def:pub copy_text(text: str) -> bool {
    g: any = globalThis;
    try {
        await g.navigator.clipboard.writeText(text);
        return True;
    } except Exception {
        return False;
    }
}
