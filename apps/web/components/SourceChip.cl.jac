"""Coloured platform chip - the at-a-glance 'where did this come from'."""

import from ..lib.format { platform_label }

def:pub SourceChip(platform: str) -> JsxElement {
    return
        <span className={"chip chip-" + platform}>
            <span className="chip-dot"/>
            {platform_label(platform)}
        </span>;
}
