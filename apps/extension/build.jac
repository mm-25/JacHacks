"""Build the Sherry browser extension into dist/ (load it in Chrome with
"Load unpacked").

    ../../.venv/bin/jac run build.jac

Steps: compile every src/**/*.cl.jac to JavaScript with `jac jac2js`, bundle
each entry point (content, background, popup) into one self-contained script
with Bun, then copy static/ (manifest, popup.html, popup.css).

Bun is looked up in $SHERRY_BUN, then ../web/.jac/bin/bun (installed by
`jac install` in apps/web), then on PATH.
"""

import os;
import sys;
import shutil;
import subprocess;
import from pathlib { Path }

glob ENTRIES: list[str] = ["content", "background", "popup"];


def find_bun(base_dir: Path) -> str {
    env = os.environ.get("SHERRY_BUN", "");
    if env {
        return env;
    }
    local = base_dir.parent / "web" / ".jac" / "bin" / "bun";
    if local.exists() {
        return str(local);
    }
    found = shutil.which("bun");
    if found {
        return found;
    }
    raise RuntimeError("Bun not found. Run `jac install` in apps/web or set SHERRY_BUN.");
}


def find_jac -> str {
    beside = Path(sys.executable).parent / "jac";
    if beside.exists() {
        return str(beside);
    }
    found = shutil.which("jac");
    if found {
        return found;
    }
    raise RuntimeError("The jac CLI was not found.");
}


def run(cmd: list[str]) -> str {
    done = subprocess.run(cmd, capture_output=True, text=True);
    if done.returncode != 0 {
        raise RuntimeError(f"Command failed: {' '.join(cmd)}\n{done.stdout}\n{done.stderr}");
    }
    return done.stdout;
}


with entry {
    base_dir = Path(str(__file__)).resolve().parent;
    src = base_dir / "src";
    compiled = base_dir / "build" / "js";
    dist = base_dir / "dist";
    jac = find_jac();
    bun = find_bun(base_dir);

    shutil.rmtree(base_dir / "build", ignore_errors=True);
    shutil.rmtree(dist, ignore_errors=True);
    compiled.mkdir(parents=True);
    dist.mkdir(parents=True);

    sources = sorted(src.rglob("*.cl.jac"));
    for source in sources {
        rel = source.relative_to(src);
        target = compiled / str(rel).replace(".cl.jac", ".js");
        target.parent.mkdir(parents=True, exist_ok=True);
        target.write_text(run([jac, "jac2js", str(source)]));
    }
    print(f"compiled {len(sources)} Jac files");

    for name in ENTRIES {
        run(
            [
                bun,
                "build",
                str(compiled / f"{name}.js"),
                "--format",
                "iife",
                "--target",
                "browser",
                "--outfile",
                str(dist / f"{name}.js")
            ]
        );
        print(f"bundled dist/{name}.js");
    }

    for asset in (base_dir / "static").iterdir() {
        shutil.copy(asset, dist / asset.name);
    }
    print(f"copied static files -> {dist}");
    print("Load it in Chrome: chrome://extensions -> Developer mode -> Load unpacked -> apps/extension/dist");
}
