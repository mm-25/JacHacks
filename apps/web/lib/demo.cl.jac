"""The shared demo account. Fake, demo-only credentials: every client that
signs in with these sees the same seeded workspace for the cross-surface demo."""

glob:pub DEMO_EMAIL: str = "demo@sherry.app";
glob:pub DEMO_PASSWORD: str = "sherry-demo-2026";


def:pub is_demo_account(account: str) -> bool {
    return account == DEMO_EMAIL;
}
