"""Tiny inline SVG icon set (stroke icons, 24px grid, inherits currentColor).

Each icon is a list of SVG path strings; circles are written as two arcs."""

glob ICON_PATHS: dict[str, list[str]] = {
         "search": ["M4 11a7 7 0 1 0 14 0a7 7 0 1 0 -14 0", "m20 20-3.5-3.5"],
         "refresh": ["M21 12a9 9 0 1 1-2.64-6.36", "M21 4v5h-5"],
         "x": ["M18 6 6 18", "m6 6 12 12"],
         "back": ["m15 18-6-6 6-6"],
         "trash": ["M3 6h18", "M8 6V4h8v2", "M19 6l-1 14H6L5 6"],
         "user": ["M8 8a4 4 0 1 0 8 0a4 4 0 1 0 -8 0", "M4 21a8 8 0 0 1 16 0"],
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
