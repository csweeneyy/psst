-- Conversation history lives server side so the assistant keeps context even
-- if the app's local store is cleared. Habits are mirrored (not owned) so a
-- future push scheduler can reason about them without the app running.

CREATE TABLE IF NOT EXISTS messages (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  role        TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  text        TEXT NOT NULL,
  mutations   TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS messages_created ON messages (created_at DESC);

CREATE TABLE IF NOT EXISTS habits (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  nudge_text    TEXT NOT NULL,
  intensity     TEXT NOT NULL,
  schedule_json TEXT NOT NULL,
  is_paused     INTEGER NOT NULL DEFAULT 0,
  synced_at     TEXT NOT NULL DEFAULT (datetime('now'))
);
