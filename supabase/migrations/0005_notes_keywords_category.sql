-- Notes: AI-extracted keywords + category from the indexer.
-- Idempotent (uses IF NOT EXISTS). Builds on the notes table from 0000_init.sql.
-- Applied via Supabase GitHub Integration.

-- keyword + category columns (both optional; null until the indexer runs)
alter table notes add column if not exists keywords text[] not null default '{}';
alter table notes add column if not exists category text;

-- Index for filtering by category
create index if not exists notes_user_category_idx on notes (user_id, category);

-- Index for keyword-based filtering (GIN on text array)
create index if not exists notes_keywords_idx on notes using gin (keywords);