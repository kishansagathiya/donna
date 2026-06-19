-- Memory Quality Upgrade: pgvector + hybrid search RPC + bug-fix columns.
-- Idempotent (uses IF NOT EXISTS). Safe on existing prod DBs that ran
-- knowledge_base.sql + notes.sql, and on fresh DBs that ran 0000_init.sql.

-- ---------------------------------------------------------------------------
-- pgvector + embedding columns + HNSW indexes
-- ---------------------------------------------------------------------------

create extension if not exists vector;

alter table kb_facts add column if not exists embedding vector(1536);
alter table notes    add column if not exists embedding vector(1536);

create index if not exists kb_facts_embedding_idx
  on kb_facts using hnsw (embedding vector_cosine_ops)
  with (m = 16, ef_construction = 64);

create index if not exists notes_embedding_idx
  on notes using hnsw (embedding vector_cosine_ops)
  with (m = 16, ef_construction = 64);

-- ---------------------------------------------------------------------------
-- Bug-fix columns (Phase 4)
-- ---------------------------------------------------------------------------

-- identity_facts: machine-detected name/pronouns, always prepended to summary at read time.
alter table kb_user_profiles
  add column if not exists identity_facts text[] not null default '{}';

-- supersede_misses: record dropped supersedes for debugging.
alter table kb_compile_log
  add column if not exists supersede_misses jsonb;

-- ---------------------------------------------------------------------------
-- Hybrid memory search RPC
-- Blends vector similarity (0.5), FTS (0.3), and recency (0.2, 30-day half-life).
-- Query embedding is generated in Go and passed in; no pg_ai needed.
-- ---------------------------------------------------------------------------

create or replace function match_memory(
  p_user_id uuid,
  p_query_embedding vector(1536),
  p_query_text text,
  p_limit int default 20
) returns table (
  source text,        -- 'fact' | 'note'
  id uuid,
  text text,          -- formatted snippet
  score float
)
language sql stable as $$
  with fact_vec as (
    select id, fact as body, entity_name, topic, created_at,
      1 - (embedding <=> p_query_embedding) as vec_score
    from kb_facts
    where user_id = p_user_id and active = true
      and embedding is not null
    order by embedding <=> p_query_embedding
    limit p_limit
  ),
  fact_fts as (
    select id, fact as body, entity_name, topic, created_at,
      ts_rank(search_vector, websearch_to_tsquery('english', p_query_text)) as fts_score
    from kb_facts
    where user_id = p_user_id and active = true
      and search_vector @@ websearch_to_tsquery('english', p_query_text)
    order by fts_score desc
    limit p_limit
  ),
  fact_blended as (
    select 'fact' as source, id, body, entity_name, topic,
      coalesce(v.vec_score, 0) * 0.5
        + coalesce(f.fts_score, 0) * 0.3
        + (1.0 / (1 + extract(epoch from now() - created_at) / 86400.0 / 30.0)) * 0.2
        as score
    from fact_vec v
    full outer join fact_fts f using (id, body, entity_name, topic, created_at)
  ),
  note_vec as (
    select id, (coalesce(title, '') || ': ' || coalesce(preview, content)) as body, created_at,
      1 - (embedding <=> p_query_embedding) as vec_score
    from notes
    where user_id = p_user_id
      and embedding is not null
    order by embedding <=> p_query_embedding
    limit p_limit
  ),
  note_fts as (
    select id, (coalesce(title, '') || ': ' || coalesce(preview, content)) as body, created_at,
      ts_rank(search_vector, websearch_to_tsquery('english', p_query_text)) as fts_score
    from notes
    where user_id = p_user_id
      and search_vector @@ websearch_to_tsquery('english', p_query_text)
    order by fts_score desc
    limit p_limit
  ),
  note_blended as (
    select 'note' as source, id, body,
      coalesce(v.vec_score, 0) * 0.5
        + coalesce(f.fts_score, 0) * 0.3
        + (1.0 / (1 + extract(epoch from now() - created_at) / 86400.0 / 30.0)) * 0.2
        as score
    from note_vec v
    full outer join note_fts f using (id, body, created_at)
  ),
  all_blended as (
    select source, id, body, score from fact_blended
    union all
    select source, id, body, score from note_blended
  ),
  deduped as (
    select distinct on (id) source, id, body, score
    from all_blended
    order by id, score desc
  )
  select source, id, body as "text", score
  from deduped
  order by score desc
  limit p_limit;
$$;
