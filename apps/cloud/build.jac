"""Compile the Sherry Worker's Jac sources (src/*.cl.jac) to JavaScript in
build/js/, which src/index.js imports. Wrangler then bundles it.

    ../../.venv/bin/jac run build.jac      (or: npm run build)
"""

import sys;
import shutil;
import subprocess;
import from pathlib { Path }


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


with entry {
    base_dir = Path(str(__file__)).resolve().parent;
    src = base_dir / "src";
    out = base_dir / "build" / "js";
    shutil.rmtree(base_dir / "build", ignore_errors=True);
    out.mkdir(parents=True);
    jac = find_jac();
    for source in sorted(src.glob("*.cl.jac")) {
        done = subprocess.run([jac, "jac2js", str(source)], capture_output=True, text=True);
        if done.returncode != 0 {
            raise RuntimeError(f"jac2js failed for {source.name}:\n{done.stdout}\n{done.stderr}");
        }
        target = out / source.name.replace(".cl.jac", ".js");
        target.write_text(done.stdout);
        print(f"compiled {source.name} -> build/js/{target.name}");
    }
}
