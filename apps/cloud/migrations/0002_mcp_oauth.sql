-- OAuth 2.1 for the Sherry MCP connector (claude.ai, ChatGPT, Gemini).
-- Assistants register themselves (Dynamic Client Registration), the user signs
-- in on Sherry's page (checked with Supabase), and the assistant exchanges a
-- one-time code (PKCE S256) for tokens. Codes and tokens are stored hashed.

CREATE TABLE oauth_clients (
  client_id           TEXT PRIMARY KEY,
  client_secret_hash  TEXT NOT NULL DEFAULT '',   -- empty for public clients
  client_name         TEXT NOT NULL DEFAULT '',
  redirect_uris       TEXT NOT NULL,              -- JSON array
  auth_method         TEXT NOT NULL DEFAULT 'none',
  metadata            TEXT NOT NULL DEFAULT '{}', -- the registration request, JSON
  created_at          TEXT NOT NULL
);

-- An authorization request waiting for the user to sign in (15 minutes).
CREATE TABLE oauth_requests (
  id          TEXT PRIMARY KEY,
  client_id   TEXT NOT NULL,
  params      TEXT NOT NULL,   -- JSON: redirect_uri, state, code_challenge, scope, resource
  created_at  REAL NOT NULL    -- unix seconds
);

-- One-time authorization codes (5 minutes).
CREATE TABLE oauth_codes (
  code_hash       TEXT PRIMARY KEY,
  client_id       TEXT NOT NULL,
  user_id         TEXT NOT NULL,
  email           TEXT NOT NULL DEFAULT '',
  redirect_uri    TEXT NOT NULL,
  code_challenge  TEXT NOT NULL,
  scope           TEXT NOT NULL,
  resource        TEXT NOT NULL DEFAULT '',
  expires_at      REAL NOT NULL
);

-- Access tokens (8 hours) and refresh tokens (30 days). A refresh rotates the
-- whole family: the old access and refresh tokens stop working.
CREATE TABLE oauth_tokens (
  token_hash  TEXT PRIMARY KEY,
  kind        TEXT NOT NULL,   -- 'access' | 'refresh'
  family      TEXT NOT NULL,
  client_id   TEXT NOT NULL,
  user_id     TEXT NOT NULL,
  email       TEXT NOT NULL DEFAULT '',
  scope       TEXT NOT NULL,
  resource    TEXT NOT NULL DEFAULT '',
  expires_at  REAL NOT NULL
);
CREATE INDEX oauth_tokens_by_family ON oauth_tokens (family);
