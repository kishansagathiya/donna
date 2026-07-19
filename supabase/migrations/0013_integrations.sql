-- Granola / connector integrations: connections, OAuth state, imported items,
-- kb_sources embeddings + FTS, notes.source_type 'integration', and match_memory
-- that includes integration transcript chunks.

-- ---------------------------------------------------------------------------
-- notes: allow integration-sourced summary notes
-- ---------------------------------------------------------------------------
alter table notes drop constraint if exists notes_source_type_check;
alter table notes
  add constraint notes_source_type_check
  check (source_type in ('voice_turn', 'document', 'manual', 'integration'));

-- ---------------------------------------------------------------------------
-- kb_sources: embeddings + full-text search for integration transcript chunks
-- ---------------------------------------------------------------------------
alter table kb_sources add column if not exists embedding vector(1536);
alter table kb_sources add column if not exists search_vector tsvector
  generated always as (to_tsvector('english', coalesce(content, ''))) stored;

create index if not exists kb_sources_embedding_idx
  on kb_sources using hnsw (embedding vector_cosine_ops)
  with (m = 16, ef_construction = 64);

create index if not exists kb_sources_search_vector_idx
  on kb_sources using gin (search_vector);

create index if not exists kb_sources_user_type_idx
  on kb_sources (user_id, source_type);

-- ---------------------------------------------------------------------------
-- integration_connections
-- ---------------------------------------------------------------------------
create table if not exists integration_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null,
  status text not null default 'disconnected'
    check (status in (
      'disconnected', 'connecting', 'connected', 'syncing',
      'reauth_required', 'error', 'partial'
    )),
  account_label text,
  workspace_label text,
  workspace_identity text,
  encrypted_credentials text,
  credentials_key_version int not null default 1,
  oauth_client_id text,
  oauth_client_secret_enc text,
  token_endpoint text,
  authorization_endpoint text,
  resource_url text,
  capabilities jsonb not null default '{}'::jsonb,
  sync_enabled boolean not null default true,
  sync_cursor jsonb not null default '{}'::jsonb,
  initial_sync_status text not null default 'pending'
    check (initial_sync_status in ('pending', 'running', 'completed', 'partial', 'failed')),
  imported_meeting_count int not null default 0,
  imported_transcript_count int not null default 0,
  last_sync_at timestamptz,
  next_sync_at timestamptz,
  last_error text,
  sync_lease_owner text,
  sync_lease_until timestamptz,
  connected_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, provider)
);

create index if not exists integration_connections_next_sync_idx
  on integration_connections (provider, next_sync_at)
  where sync_enabled = true and status in ('connected', 'partial', 'syncing');

alter table integration_connections enable row level security;

-- ---------------------------------------------------------------------------
-- integration_oauth_states (one-time PKCE + state, max 10 minutes)
-- ---------------------------------------------------------------------------
create table if not exists integration_oauth_states (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null,
  state_hash text not null unique,
  code_verifier_enc text not null,
  return_to text not null check (return_to in ('web', 'mobile')),
  redirect_uri text not null,
  client_id text,
  client_secret_enc text,
  token_endpoint text,
  authorization_endpoint text,
  resource_url text,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists integration_oauth_states_expires_idx
  on integration_oauth_states (expires_at);

alter table integration_oauth_states enable row level security;

-- ---------------------------------------------------------------------------
-- integration_items (one row per remote meeting)
-- ---------------------------------------------------------------------------
create table if not exists integration_items (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references integration_connections(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null,
  external_id text not null,
  title text,
  occurred_at timestamptz,
  attendees jsonb not null default '[]'::jsonb,
  summary_hash text,
  transcript_hash text,
  summary_note_id uuid references notes(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (connection_id, external_id)
);

create index if not exists integration_items_user_provider_idx
  on integration_items (user_id, provider);

create index if not exists integration_items_note_idx
  on integration_items (summary_note_id);

alter table integration_items enable row level security;

-- ---------------------------------------------------------------------------
-- integration_item_sources (meeting → summary/transcript kb_sources)
-- ---------------------------------------------------------------------------
create table if not exists integration_item_sources (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references integration_items(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  kb_source_id uuid not null references kb_sources(id) on delete cascade,
  kind text not null check (kind in ('summary', 'transcript_chunk')),
  chunk_index int not null default 0,
  created_at timestamptz not null default now(),
  unique (item_id, kind, chunk_index)
);

create index if not exists integration_item_sources_kb_idx
  on integration_item_sources (kb_source_id);

create index if not exists integration_item_sources_user_idx
  on integration_item_sources (user_id);

alter table integration_item_sources enable row level security;

-- ---------------------------------------------------------------------------
-- match_memory: include integration kb_sources (transcripts) as 'granola'
-- ---------------------------------------------------------------------------
create or replace function match_memory(
  p_user_id uuid,
  p_query_embedding vector(1536),
  p_query_text text,
  p_limit int default 20
) returns table (
  source text,        -- 'fact' | 'note' | 'granola'
  id uuid,
  text text,
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
  -- Integration transcript/summary chunks stored in kb_sources.
  integ_vec as (
    select id, content as body, created_at,
      1 - (embedding <=> p_query_embedding) as vec_score
    from kb_sources
    where user_id = p_user_id
      and source_type = 'integration'
      and embedding is not null
    order by embedding <=> p_query_embedding
    limit p_limit
  ),
  integ_fts as (
    select id, content as body, created_at,
      ts_rank(search_vector, websearch_to_tsquery('english', p_query_text)) as fts_score
    from kb_sources
    where user_id = p_user_id
      and source_type = 'integration'
      and search_vector @@ websearch_to_tsquery('english', p_query_text)
    order by fts_score desc
    limit p_limit
  ),
  integ_blended as (
    select 'granola' as source, id, body,
      coalesce(v.vec_score, 0) * 0.5
        + coalesce(f.fts_score, 0) * 0.3
        + (1.0 / (1 + extract(epoch from now() - created_at) / 86400.0 / 30.0)) * 0.2
        as score
    from integ_vec v
    full outer join integ_fts f using (id, body, created_at)
  ),
  all_blended as (
    select source, id, body, score from fact_blended
    union all
    select source, id, body, score from note_blended
    union all
    select source, id, body, score from integ_blended
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
