-- Donna database schema (run once in Supabase Dashboard → SQL Editor)
-- Order matters: conversations first, then knowledge tables.

-- ---------------------------------------------------------------------------
-- Voice conversation persistence
-- ---------------------------------------------------------------------------

create table if not exists conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  voice_session_id text not null,
  ended_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists conversations_user_id_idx on conversations (user_id);

create table if not exists conversation_turns (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations (id) on delete cascade,
  turn_index int not null,
  user_transcript text not null default '',
  assistant_transcript text not null default '',
  user_audio_path text,
  assistant_audio_path text,
  user_audio_mime text,
  assistant_audio_mime text,
  timings jsonb,
  created_at timestamptz not null default now(),
  unique (conversation_id, turn_index)
);

create index if not exists conversation_turns_conversation_id_idx
  on conversation_turns (conversation_id);

-- Storage bucket: create "conversation-audio" in Dashboard → Storage

-- ---------------------------------------------------------------------------
-- Knowledge base
-- ---------------------------------------------------------------------------

create table if not exists kb_sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  source_type text not null check (source_type in ('voice_turn', 'document', 'integration')),
  content text not null,
  conversation_id uuid references conversations (id) on delete set null,
  turn_index int,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (conversation_id, turn_index)
);

create index if not exists kb_sources_user_id_idx on kb_sources (user_id);

create table if not exists kb_user_profiles (
  user_id uuid primary key,
  summary text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists kb_facts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  fact text not null,
  entity_name text,
  topic text,
  source_id uuid references kb_sources (id) on delete set null,
  supersedes_id uuid references kb_facts (id) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists kb_facts_user_id_idx on kb_facts (user_id);
create index if not exists kb_facts_user_active_idx on kb_facts (user_id) where active = true;

alter table kb_facts add column if not exists search_vector tsvector
  generated always as (
    to_tsvector('english', coalesce(fact, '') || ' ' || coalesce(entity_name, '') || ' ' || coalesce(topic, ''))
  ) stored;

create index if not exists kb_facts_search_idx on kb_facts using gin (search_vector);

create table if not exists kb_compile_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  conversation_id uuid references conversations (id) on delete set null,
  status text not null check (status in ('pending', 'running', 'completed', 'failed')),
  turns_count int not null default 0,
  facts_added int not null default 0,
  error text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists kb_compile_log_user_id_idx on kb_compile_log (user_id);

-- Storage bucket: create "knowledge-assets" in Dashboard → Storage (for file uploads)
