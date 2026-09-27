"""Top-level shell: signed out -> LoginScreen, signed in -> Library.

Sign-in is Supabase Auth (lib/supabase.cl.jac). This shell also takes the
session from the email-confirmation link, and renews the access token every
minute so a long-open tab never hits an expired token."""

import from react { useEffect }
import from ..lib.supabase {
    has_session,
    session_email,
    keep_fresh,
    sign_out,
    take_session_from_url
}
import from .LoginScreen { LoginScreen }
import from .Library { Library }

glob ACCOUNT_STORAGE_KEY: str = "sherry.account";
glob REFRESH_CHECK_MS: int = 60000;


def:pub SherryApp -> JsxElement {
    has signed_in: bool = has_session(),
        account: str = session_email() or localStorage.getItem(ACCOUNT_STORAGE_KEY) or "",
        notice: str = "";

    def handle_signed_in(user: str) {
        localStorage.setItem(ACCOUNT_STORAGE_KEY, user);
        account = user;
        notice = "";
        signed_in = True;
    }

    def handle_signed_out {
        localStorage.removeItem(ACCOUNT_STORAGE_KEY);
        account = "";
        signed_in = False;
    }

    async def check_session -> None {
        if not has_session() {
            return;
        }
        still_valid = await keep_fresh();
        if not still_valid {
            await sign_out();
            notice = "Your session ended. Sign in again.";
            handle_signed_out();
        }
    }

    useEffect(
        lambda {
            taken = take_session_from_url();
            taken_email = str(taken["email"] or "");
            taken_error = str(taken["error"] or "");
            if taken_email {
                handle_signed_in(taken_email);
            } elif taken_error {
                notice = "That link didn't work (" + taken_error + "). Sign in, or request a new link.";
            }
            check_session();
            timer = setInterval(lambda { check_session(); }, REFRESH_CHECK_MS);
            return lambda { clearInterval(timer); };
        },
        []
    );

    if not signed_in {
        return <LoginScreen onSignedIn={handle_signed_in} notice={notice}/>;
    }
    return <Library account={account} onSignOut={handle_signed_out}/>;
}
