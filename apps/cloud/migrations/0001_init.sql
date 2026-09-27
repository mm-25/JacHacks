-- Sherry on Cloudflare D1. Same records as the Jac graph in apps/web
-- (data-schema-specification.md): one workspace per user, memories, captured
-- conversations with their messages, plus API keys for programs that can't do
-- an interactive Supabase login (extension, desktop sync, MCP connector).
-- user_id is the Supabase auth user id (the JWT `sub`).

CREATE TABLE workspaces (
  user_id     TEXT PRIMARY KEY,
  id          TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL DEFAULT 'My workspace',
  email       TEXT NOT NULL DEFAULT '',
  is_demo     INTEGER NOT NULL DEFAULT 0,
  created_at  TEXT NOT NULL
);

CREATE TABLE memories (
  id               TEXT PRIMARY KEY,
  user_id          TEXT NOT NULL,
  content          TEXT NOT NULL,
  tags             TEXT NOT NULL DEFAULT '[]',   -- JSON array of strings
  source_type      TEXT NOT NULL DEFAULT 'manual_note',
  source_platform  TEXT NOT NULL DEFAULT 'web',
  source_label     TEXT NOT NULL DEFAULT '',
  source_url       TEXT NOT NULL DEFAULT '',
  source_context   TEXT NOT NULL DEFAULT '',
  captured_via     TEXT NOT NULL DEFAULT 'app',
  conversation_id  TEXT NOT NULL DEFAULT '',
  idempotency_key  TEXT NOT NULL,
  created_at       TEXT NOT NULL,
  updated_at       TEXT NOT NULL,
  deleted_at       TEXT NOT NULL DEFAULT '',
  UNIQUE (user_id, idempotency_key)
);
CREATE INDEX memories_by_user_time ON memories (user_id, deleted_at, created_at DESC);
CREATE INDEX memories_by_conversation ON memories (user_id, conversation_id);

CREATE TABLE conversations (
  id               TEXT PRIMARY KEY,
  user_id          TEXT NOT NULL,
  platform         TEXT NOT NULL,
  external_id      TEXT NOT NULL,
  url              TEXT NOT NULL DEFAULT '',
  title            TEXT NOT NULL DEFAULT '',
  context          TEXT NOT NULL DEFAULT '',
  captured_via     TEXT NOT NULL DEFAULT 'extension',
  created_at       TEXT NOT NULL,
  updated_at       TEXT NOT NULL,
  summarized_hash  TEXT NOT NULL DEFAULT '',
  summarized_at    TEXT NOT NULL DEFAULT '',
  summary_engine   TEXT NOT NULL DEFAULT '',
  summary_note     TEXT NOT NULL DEFAULT '',
  ignored          INTEGER NOT NULL DEFAULT 0,
  UNIQUE (user_id, platform, external_id)
);

CREATE TABLE messages (
  conversation_id  TEXT NOT NULL,
  key              TEXT NOT NULL,
  role             TEXT NOT NULL,
  text             TEXT NOT NULL,
  position         INTEGER NOT NULL DEFAULT 0,
  sent_at          TEXT NOT NULL DEFAULT '',
  captured_at      TEXT NOT NULL,
  updated_at       TEXT NOT NULL,
  PRIMARY KEY (conversation_id, key)
);

CREATE TABLE api_keys (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL,
  name          TEXT NOT NULL,
  prefix        TEXT NOT NULL,           -- first characters, to recognise a key
  key_hash      TEXT NOT NULL UNIQUE,    -- SHA-256 of the full key; the key itself is never stored
  created_at    TEXT NOT NULL,
  last_used_at  TEXT NOT NULL DEFAULT '',
  revoked_at    TEXT NOT NULL DEFAULT ''
);
CREATE INDEX api_keys_by_user ON api_keys (user_id);
