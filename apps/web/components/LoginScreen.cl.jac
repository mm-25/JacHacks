"""Sign in / create account through Supabase Auth, plus a one-click shared demo
workspace (FR-001).

This Supabase project requires email confirmation: after signing up, the user
opens the emailed link, which brings them back here already signed in
(SherryApp picks the session up from the URL)."""

import from ..lib.demo { DEMO_EMAIL, DEMO_PASSWORD }
import from ..lib.supabase { sign_in, sign_up, resend_confirmation }

sv import from ..services.memories { MemoryPage, load_demo_data }


def:pub LoginScreen(onSignedIn: Callable[[str], None], notice: str = "") -> JsxElement {
    has mode: str = "signin",
        email: str = "",
        password: str = "",
        busy: bool = False,
        error: str = "",
        info: str = "",
        unconfirmed: bool = False,
        check_email: str = "";

    is_signup = mode == "signup";

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
        busy = True;
        error = "";
        info = "";
        unconfirmed = False;
        if is_signup {
            created = await sign_up(user, password);
            busy = False;
            if not created["ok"] {
                error = str(created["error"]);
                return;
            }
            if created["signedIn"] {
                onSignedIn(user);
                return;
            }
            check_email = user;
            password = "";
            return;
        }
        result = await sign_in(user, password);
        busy = False;
        if result["ok"] {
            onSignedIn(user);
            return;
        }
        error = str(result["error"]);
        unconfirmed = result["code"] == "email_not_confirmed";
    }

    async def resend(target: str) -> None {
        busy = True;
        sent = await resend_confirmation(target);
        busy = False;
        if sent["ok"] {
            error = "";
            info = "Sent. Check your inbox (and spam) for the new link.";
        } else {
            error = str(sent["error"]);
        }
    }

    async def use_demo -> None {
        busy = True;
        error = "";
        info = "";
        result = await sign_in(DEMO_EMAIL, DEMO_PASSWORD);
        if not result["ok"] {
            busy = False;
            error = (
                "The demo account isn't set up yet."
                if result["code"] == "invalid_credentials"
                else str(result["error"])
            );
            return;
        }
        try {
            # Only the demo account gets sample data; real accounts start empty.
            _ = await load_demo_data();
        } except Exception {
            busy = False;
            error = "Signed in, but Sherry isn't reachable right now. Try again in a moment.";
            return;
        }
        onSignedIn(DEMO_EMAIL);
    }

    def toggle_mode(e: MouseEvent) {
        mode = "signin" if is_signup else "signup";
        error = "";
        info = "";
        unconfirmed = False;
    }

    if check_email {
        return
            <main className="auth">
                <div className="auth-card">
                    <div className="auth-brand">
                        <div className="logo" aria-hidden="true">S</div>
                        <span className="wordmark">Sherry</span>
                    </div>
                    <h1 className="auth-title">Check your email.</h1>
                    <p className="auth-sub">
                        We sent a confirmation link to <strong>{check_email}</strong>. Open it
                        on this device and you'll come back here signed in.
                    </p>
                    {if error {
                        <div key="err" className="alert alert-error" role="alert">{error}</div>
                    } elif info {
                        <div key="info" className="alert alert-warn" role="status">{info}</div>
                    }}
                    <button
                        type="button"
                        className="btn btn-block"
                        onClick={lambda e: MouseEvent { resend(check_email); }}
                        disabled={busy}
                    >
                        {"Sending…" if busy else "Resend the link"}
                    </button>
                    <p className="auth-switch">
                        Already confirmed?{" "}
                        <button
                            type="button"
                            className="link-btn"
                            onClick={lambda e: MouseEvent {
                                email = check_email;
                                check_email = "";
                                mode = "signin";
                                error = "";
                                info = "";
                            }}
                        >
                            Sign in
                        </button>
                    </p>
                </div>
            </main>;
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
                {if notice {
                    <div key="notice" className="alert alert-warn" role="status">{notice}</div>
                }}
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
                        <div key="err" className="alert alert-error" role="alert">
                            <span className="alert-body">{error}</span>
                            {if unconfirmed {
                                <button
                                    key="resend"
                                    type="button"
                                    className="btn btn-sm"
                                    onClick={lambda e: MouseEvent { resend(email.strip().lower()); }}
                                    disabled={busy}
                                >
                                    Resend link
                                </button>
                            }}
                        </div>
                    } elif info {
                        <div key="info" className="alert alert-warn" role="status">{info}</div>
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
