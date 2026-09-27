"""Tiny inline SVG icon set (stroke icons, 24px grid, inherits currentColor).

Each icon is a list of SVG path strings; circles are written as two arcs."""

glob ICON_PATHS: dict[str, list[str]] = {
         "search": ["M4 11a7 7 0 1 0 14 0a7 7 0 1 0 -14 0", "m20 20-3.5-3.5"],
         "refresh": ["M21 12a9 9 0 1 1-2.64-6.36", "M21 4v5h-5"],
         "x": ["M18 6 6 18", "m6 6 12 12"],
         "back": ["m15 18-6-6 6-6"],
         "trash": ["M3 6h18", "M8 6V4h8v2", "M19 6l-1 14H6L5 6"],
         "user": ["M8 8a4 4 0 1 0 8 0a4 4 0 1 0 -8 0", "M4 21a8 8 0 0 1 16 0"],
         "dashboard": ["M3 3h7v9H3z", "M14 3h7v5h-7z", "M14 12h7v9h-7z", "M3 16h7v5H3z"],
         "panel": ["M4 4h16v16H4z", "M9 4v16"],
         "sparkles": [
             "M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9z",
             "M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"
         ],
         "branch": ["M6 3v12", "M18 9a3 3 0 1 0 0-6a3 3 0 1 0 0 6", "M6 21a3 3 0 1 0 0-6a3 3 0 1 0 0 6", "M18 9a9 9 0 0 1-9 9"],
         "chart": ["M3 3v18h18", "M8 17v-5", "M13 17V8", "M18 17v-8"],
         "arrow-up-right": ["M7 17 17 7", "M8 7h9v9"],
         "settings": [
             "M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0",
             "M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1Z"
         ],
         "message-square": ["M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"],
         "git-merge": ["M15 18a3 3 0 1 0 6 0a3 3 0 1 0 -6 0", "M3 6a3 3 0 1 0 6 0a3 3 0 1 0 -6 0", "M6 21V9a9 9 0 0 0 9 9"],
         "activity": ["M22 12h-4l-3 9L9 3l-3 9H2"],
         "chevron-left": ["m15 18-6-6 6-6"],
         "chevron-right": ["m9 18 6-6-6-6"],
         "menu": ["M4 6h16", "M4 12h16", "M4 18h16"],
         "memory": [
             "M12 3a6 6 0 0 0-6 6c0 2.2 1.2 3.6 2 4.6.6.8 1 1.6 1 2.4v1h6v-1c0-.8.4-1.6 1-2.4.8-1 2-2.4 2-4.6a6 6 0 0 0-6-6Z",
             "M9.5 21h5"
         ]
     };

def:pub Icon(name: str, size: int = 18) -> JsxElement {
    paths = ICON_PATHS[name] or [];
    return
        <svg
            width={size}
            height={size}
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
            focusable="false"
        >
            {for d in paths {
                <path key={d} d={d}/>
            }}
        </svg>;
}
