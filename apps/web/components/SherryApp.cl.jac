"""Top-level shell: signed out -> LoginScreen, signed in -> Library."""

import from "@jac/runtime" { jacIsLoggedIn }
import from .LoginScreen { LoginScreen }
import from .Library { Library }

glob ACCOUNT_STORAGE_KEY: str = "sherry.account";

def:pub SherryApp -> JsxElement {
    has signed_in: bool = jacIsLoggedIn(),
        account: str = localStorage.getItem(ACCOUNT_STORAGE_KEY) or "";

    def handle_signed_in(user: str) {
        localStorage.setItem(ACCOUNT_STORAGE_KEY, user);
        account = user;
        signed_in = True;
    }

    def handle_signed_out {
        localStorage.removeItem(ACCOUNT_STORAGE_KEY);
        account = "";
        signed_in = False;
    }

    if not signed_in {
        return <LoginScreen onSignedIn={handle_signed_in}/>;
    }
    return <Library account={account} onSignOut={handle_signed_out}/>;
}
