-- Notes: AI-extracted keywords + category from the indexer.
-- Idempotent (uses IF NOT EXISTS). Builds on the notes table from 0000_init.sql.
-- Applied via Supabase GitHub Integration.

-- keyword + category columns (both optional; null until the indexer runs)
alter table notes add column if not exists keywords text[] not null default '{}';
alter table notes add column if not exists category text;

-- Fold keywords + category into the FTS search_vector so tag/category terms match.
-- The search_vector is GENERATED ALWAYS, so we replace the expression.
drop index if exists notes_search_idx;
alter table notes alter column search_vector drop expression;
alter table notes alter column search_vector set generated always as (
  to_tsvector('english',
    coalesce(title, '') || ' ' ||
    coalesce(content, '') || ' ' ||
    coalesce(preview, '') || ' ' ||
    coalesce(array_to_string(keywords, ' '), '') || ' ' ||
    coalesce(category, '')
  )
) stored;
create index if not exists notes_search_idx on notes using gin (search_vector);

-- Index for filtering by category
create index if not exists notes_user_category_idx on notes (user_id, category);