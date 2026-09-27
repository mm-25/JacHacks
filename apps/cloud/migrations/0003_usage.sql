-- Usage data for the dashboard: how often assistants look memories up through
-- the connector, and how often each memory is handed back to an assistant.

ALTER TABLE memories ADD COLUMN recall_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE memories ADD COLUMN last_recalled_at TEXT NOT NULL DEFAULT '';

-- One row per connector lookup (search_memories, list_recent_memories, get_memory).
CREATE TABLE memory_lookups (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  platform    TEXT NOT NULL,      -- claude | chatgpt | gemini
  tool        TEXT NOT NULL,
  results     INTEGER NOT NULL DEFAULT 0,
  created_at  TEXT NOT NULL
);
CREATE INDEX memory_lookups_by_user ON memory_lookups (user_id, created_at DESC);
CREATE INDEX conversations_by_user ON conversations (user_id, updated_at DESC);
