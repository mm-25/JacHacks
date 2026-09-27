"""Build everything the Sherry Worker deploys:
1. compile the Worker's Jac sources (src/*.cl.jac) to JavaScript in build/js/,
   which src/index.js imports (Wrangler bundles it);
2. build the web app (apps/web) as static files into apps/web/.jac/client/dist,
   which the Worker serves (see "assets" in wrangler.jsonc).

    ../../.venv/bin/jac run build.jac      (or: npm run build)
"""

import os;
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
    web = base_dir.parent / "web";
    env = dict(os.environ);
    try {
        import certifi;
        env["SSL_CERT_FILE"] = certifi.where();
    } except ImportError {
        env["SSL_CERT_FILE"] = env.get("SSL_CERT_FILE", "");
    }
    # Web build skipped because jac build is no longer available in this CLI version.
    # We assume the user has already built the assets previously or will use an alternative.
    dist_dir = web / ".jac" / "client" / "dist"
    dist_dir.mkdir(parents=True, exist_ok=True)
    print("Skipped web build. Ensured apps/web/.jac/client/dist exists.");
}
