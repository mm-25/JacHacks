"""Sign in / create account, plus a one-click shared demo workspace (FR-001).

Jac's built-in auth stores the email as the account's `username` identity,
so mobile and desktop sign in to the same workspace with the same email."""

import from "@jac/runtime" { jacLogin, jacSignup }
import from ..lib.demo { DEMO_EMAIL, DEMO_PASSWORD }

sv import from ..services.memories { MemoryPage, load_demo_data }


def:pub LoginScreen(onSignedIn: Callable[[str], None]) -> JsxElement {
    has mode: str = "signin",
        email: str = "",
        password: str = "",
        busy: bool = False,
        error: str = "";

    is_signup = mode == "signup";

    async def sign_in(user: str, secret: str, create: bool) -> None {
        ok: bool = False;
        signup_result: dict | None = None;
        busy = True;
        error = "";
        try {
            if create {
                signup_result = await jacSignup(user, secret);
                if not signup_result["success"] {
                    error = "Couldn't create that account. The email may already be registered.";
                    busy = False;
                    return;
                }
            }
            ok = await jacLogin(user, secret);
            if ok {
                onSignedIn(user);
                return;
            }
            error = "That email and password don't match.";
        } except Exception {
            error = "Can't reach Sherry right now. Check your connection and try again.";
        }
        busy = False;
    }

    async def handle_submit(e: FormEvent) -> None {
        e.preventDefault();
        user = email.strip().lower();
        if not user or not password {
            error = "Enter your email and password.";
            return;
        }
        if is_signup and len(password) < 8 {
            error = "Use at least 8 characters for your password.";
            return;
        }
        await sign_in(user, password, is_signup);
    }

    async def use_demo -> None {
        ok: bool = False;
        signup_result: dict | None = None;
        busy = True;
        error = "";
        try {
            ok = await jacLogin(DEMO_EMAIL, DEMO_PASSWORD);
            if not ok {
                signup_result = await jacSignup(DEMO_EMAIL, DEMO_PASSWORD);
                if signup_result["success"] {
                    ok = await jacLogin(DEMO_EMAIL, DEMO_PASSWORD);
                }
            }
            if ok {
                # Only the demo account gets sample data; real accounts start empty.
                _ = await load_demo_data();
                onSignedIn(DEMO_EMAIL);
                return;
            }
            error = "The demo workspace isn't available right now.";
        } except Exception {
            error = "Can't reach Sherry right now. Check your connection and try again.";
        }
        busy = False;
    }

    def toggle_mode(e: MouseEvent) {
        mode = "signin" if is_signup else "signup";
        error = "";
    }

    return
        <main className="auth">
            <div className="auth-card">
                <div className="auth-brand">
                    <div className="logo" aria-hidden="true">S</div>
                    <span className="wordmark">Sherry</span>
                </div>
                <h1 className="auth-title">
                    {"Create your memory." if is_signup else "Welcome back."}
                </h1>
                <p className="auth-sub">
                    Save once. Find anywhere. See the source. Stay in control.
                </p>
                <button
                    type="button"
                    className="btn btn-primary btn-block"
                    onClick={use_demo}
                    disabled={busy}
                >
                    {"Opening…" if busy else "Open the demo workspace"}
                </button>
                <p className="auth-note">
                    Shared demo data. Don't save anything private.
                </p>
                <div className="auth-divider">or use your account</div>
                <form className="auth-form" onSubmit={handle_submit} noValidate={True}>
                    <div className="field">
                        <label className="field-label" htmlFor="auth-email">
                            Email
                        </label>
                        <input
                            id="auth-email"
                            className="input"
                            type="email"
                            autoComplete="email"
                            value={email}
                            onChange={lambda e: ChangeEvent { email = e.target.value; }}
                        />
                    </div>
                    <div className="field">
                        <label className="field-label" htmlFor="auth-password">
                            Password
                        </label>
                        <input
                            id="auth-password"
                            className="input"
                            type="password"
                            autoComplete={"new-password"
                                if is_signup
                                else "current-password"}
                            value={password}
                            onChange={lambda e: ChangeEvent { password = e.target.value; }}
                        />
                    </div>
                    {if error {
                        <div className="alert alert-error" role="alert">{error}</div>
                    }}
                    <button type="submit" className="btn btn-block" disabled={busy}>
                        {"Create account" if is_signup else "Sign in"}
                    </button>
                </form>
                <p className="auth-switch">
                    {"Already have an account? " if is_signup else "New to Sherry? "}
                    <button type="button" className="link-btn" onClick={toggle_mode}>
                        {"Sign in" if is_signup else "Create an account"}
                    </button>
                </p>
            </div>
        </main>;
}
