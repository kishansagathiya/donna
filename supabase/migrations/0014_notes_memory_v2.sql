-- Notes & Memory V2 foundation: additive schema, durable background jobs, feature-flag columns.
-- Idempotent (IF NOT EXISTS / ADD COLUMN IF NOT EXISTS). No backfill or re-extraction triggers.

-- ---------------------------------------------------------------------------
-- Notes: optimistic versioning + async enrichment state (legacy rows default safely)
-- ---------------------------------------------------------------------------

alter table notes add column if not exists content_version bigint not null default 1;

alter table notes add column if not exists enrichment_status text not null default 'idle'
  check (enrichment_status in ('idle', 'queued', 'running', 'succeeded', 'failed'));

alter table notes add column if not exists enrichment_version bigint not null default 0;

create index if not exists notes_user_enrichment_status_idx
  on notes (user_id, enrichment_status)
  where enrichment_status in ('queued', 'running');

-- ---------------------------------------------------------------------------
-- Memory facts: structured V2 fields (nullable; legacy facts unchanged)
-- ---------------------------------------------------------------------------

alter table kb_facts add column if not exists content_version bigint not null default 1;

alter table kb_facts add column if not exists memory_kind text
  check (memory_kind is null or memory_kind in (
    'identity', 'preference', 'relationship', 'goal', 'project',
    'habit', 'location', 'event', 'fact', 'other'
  ));

alter table kb_facts add column if not exists predicate text;
alter table kb_facts add column if not exists object_value jsonb;
alter table kb_facts add column if not exists confidence real
  check (confidence is null or (confidence >= 0 and confidence <= 1));
alter table kb_facts add column if not exists sensitivity text not null default 'normal'
  check (sensitivity in ('normal', 'sensitive', 'restricted'));
alter table kb_facts add column if not exists valid_from timestamptz;
alter table kb_facts add column if not exists valid_until timestamptz;
alter table kb_facts add column if not exists review_status text not null default 'active'
  check (review_status in ('active', 'pending_review', 'rejected', 'superseded'));

-- ---------------------------------------------------------------------------
-- Tags: canonical smart-tag metadata (additive; existing tag rows keep working)
-- ---------------------------------------------------------------------------

alter table tags add column if not exists normalized_name text;
alter table tags add column if not exists alias_of text;
alter table tags add column if not exists pinned boolean not null default false;

alter table note_tags add column if not exists origin text not null default 'manual'
  check (origin in ('manual', 'hashtag', 'auto'));
alter table note_tags add column if not exists locked boolean not null default false;

-- ---------------------------------------------------------------------------
-- Evidence, chunks, suggestions, feedback, retrieval telemetry
-- ---------------------------------------------------------------------------

create table if not exists kb_memory_evidence (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  fact_id uuid not null references kb_facts (id) on delete cascade,
  source_kind text not null check (source_kind in (
    'conversation_turn', 'note', 'kb_source', 'integration_item', 'manual'
  )),
  source_id uuid,
  excerpt text not null default '',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists kb_memory_evidence_fact_id_idx on kb_memory_evidence (fact_id);
create index if not exists kb_memory_evidence_user_id_idx on kb_memory_evidence (user_id);

create table if not exists note_chunks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  note_id uuid not null references notes (id) on delete cascade,
  chunk_index int not null,
  content text not null,
  embedding vector(1536),
  content_version bigint not null default 1,
  created_at timestamptz not null default now(),
  unique (note_id, chunk_index)
);

create index if not exists note_chunks_note_id_idx on note_chunks (note_id);
create index if not exists note_chunks_user_id_idx on note_chunks (user_id);

create table if not exists memory_suggestions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  suggestion_kind text not null check (suggestion_kind in ('memory', 'tag')),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected', 'expired')),
  target_note_id uuid references notes (id) on delete cascade,
  target_fact_id uuid references kb_facts (id) on delete set null,
  payload jsonb not null default '{}'::jsonb,
  confidence real check (confidence is null or (confidence >= 0 and confidence <= 1)),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists memory_suggestions_user_status_idx
  on memory_suggestions (user_id, status, created_at desc);

create table if not exists memory_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  fact_id uuid references kb_facts (id) on delete set null,
  suggestion_id uuid references memory_suggestions (id) on delete set null,
  action text not null check (action in ('confirm', 'reject', 'edit', 'merge', 'tag_correction')),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists memory_feedback_user_id_idx on memory_feedback (user_id, created_at desc);

create table if not exists memory_retrieval_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  session_id text,
  query_text text not null default '',
  plan jsonb not null default '{}'::jsonb,
  result_summary jsonb not null default '{}'::jsonb,
  latency_ms int,
  created_at timestamptz not null default now()
);

create index if not exists memory_retrieval_events_user_id_idx
  on memory_retrieval_events (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Durable background jobs (retries + dead letter)
-- ---------------------------------------------------------------------------

create table if not exists background_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  job_type text not null,
  dedupe_key text,
  payload jsonb not null default '{}'::jsonb,
  target_kind text check (target_kind is null or target_kind in ('note', 'fact', 'conversation', 'source')),
  target_id uuid,
  target_version bigint,
  status text not null default 'pending'
    check (status in ('pending', 'running', 'succeeded', 'failed', 'dead_letter')),
  attempt_count int not null default 0,
  max_attempts int not null default 5,
  run_after timestamptz not null default now(),
  locked_at timestamptz,
  locked_by text,
  lock_expires_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  finished_at timestamptz
);

create index if not exists background_jobs_claim_idx
  on background_jobs (status, run_after, created_at)
  where status = 'pending';

create unique index if not exists background_jobs_active_dedupe_unique
  on background_jobs (job_type, dedupe_key)
  where dedupe_key is not null and status in ('pending', 'running');

-- ---------------------------------------------------------------------------
-- Per-user feature-flag overrides (null = inherit server default)
-- ---------------------------------------------------------------------------

alter table user_preferences add column if not exists flag_notes_v2_feed boolean;
alter table user_preferences add column if not exists flag_notes_v2_smart_tagging boolean;
alter table user_preferences add column if not exists flag_memory_v2_extraction boolean;
alter table user_preferences add column if not exists flag_memory_v2_retrieval boolean;

-- ---------------------------------------------------------------------------
-- Job RPCs: idempotent claim, complete, fail-with-retry, enqueue
-- ---------------------------------------------------------------------------

create or replace function release_expired_background_job_leases()
returns void
language sql
as $$
  update background_jobs
  set
    status = 'pending',
    locked_at = null,
    locked_by = null,
    lock_expires_at = null,
    updated_at = now()
  where status = 'running'
    and lock_expires_at is not null
    and lock_expires_at < now();
$$;

create or replace function claim_background_jobs(
  p_worker_id text,
  p_limit int default 10,
  p_lease_seconds int default 300
)
returns setof background_jobs
language plpgsql
as $$
begin
  perform release_expired_background_job_leases();

  return query
  with candidates as (
    select j.id
    from background_jobs j
    where j.status = 'pending'
      and j.run_after <= now()
      and j.attempt_count < j.max_attempts
    order by j.run_after asc, j.created_at asc
    limit greatest(p_limit, 0)
    for update skip locked
  ),
  claimed as (
    update background_jobs j
    set
      status = 'running',
      locked_at = now(),
      locked_by = p_worker_id,
      lock_expires_at = now() + make_interval(secs => p_lease_seconds),
      updated_at = now()
    from candidates c
    where j.id = c.id
    returning j.*
  )
  select * from claimed;
end;
$$;

create or replace function complete_background_job(
  p_job_id uuid,
  p_worker_id text
)
returns setof background_jobs
language plpgsql
as $$
declare
  row background_jobs;
begin
  update background_jobs
  set
    status = 'succeeded',
    locked_at = null,
    locked_by = null,
    lock_expires_at = null,
    updated_at = now(),
    finished_at = now()
  where id = p_job_id
    and status = 'running'
    and locked_by = p_worker_id
  returning * into row;

  if row.id is null then
    raise exception 'job not found or not locked by worker';
  end if;

  return query select row.*;
end;
$$;

create or replace function fail_background_job(
  p_job_id uuid,
  p_worker_id text,
  p_error text,
  p_retry_delay_seconds int default 60
)
returns setof background_jobs
language plpgsql
as $$
declare
  row background_jobs;
  next_attempt int;
begin
  update background_jobs
  set attempt_count = attempt_count + 1
  where id = p_job_id
    and status = 'running'
    and locked_by = p_worker_id
  returning * into row;

  if row.id is null then
    raise exception 'job not found or not locked by worker';
  end if;

  next_attempt := row.attempt_count;

  if next_attempt >= row.max_attempts then
    update background_jobs
    set
      status = 'dead_letter',
      last_error = left(coalesce(p_error, ''), 4000),
      locked_at = null,
      locked_by = null,
      lock_expires_at = null,
      updated_at = now(),
      finished_at = now()
    where id = p_job_id
    returning * into row;
  else
    update background_jobs
    set
      status = 'pending',
      last_error = left(coalesce(p_error, ''), 4000),
      run_after = now() + make_interval(secs => greatest(p_retry_delay_seconds, 1)),
      locked_at = null,
      locked_by = null,
      lock_expires_at = null,
      updated_at = now()
    where id = p_job_id
    returning * into row;
  end if;

  return query select row.*;
end;
$$;

create or replace function enqueue_background_job(
  p_user_id uuid,
  p_job_type text,
  p_dedupe_key text,
  p_payload jsonb default '{}'::jsonb,
  p_target_kind text default null,
  p_target_id uuid default null,
  p_target_version bigint default null,
  p_run_after timestamptz default now()
)
returns setof background_jobs
language plpgsql
as $$
declare
  row background_jobs;
  key text := nullif(trim(p_dedupe_key), '');
begin
  if key is not null then
    select * into row
    from background_jobs
    where job_type = p_job_type
      and dedupe_key = key
      and status in ('pending', 'running')
    limit 1
    for update;

    if row.id is not null then
      update background_jobs
      set
        payload = coalesce(p_payload, '{}'::jsonb),
        target_kind = coalesce(p_target_kind, target_kind),
        target_id = coalesce(p_target_id, target_id),
        target_version = coalesce(p_target_version, target_version),
        run_after = least(run_after, coalesce(p_run_after, now())),
        updated_at = now()
      where id = row.id
      returning * into row;
      return query select row.*;
      return;
    end if;
  end if;

  insert into background_jobs (
    user_id, job_type, dedupe_key, payload,
    target_kind, target_id, target_version, run_after
  )
  values (
    p_user_id, p_job_type, key, coalesce(p_payload, '{}'::jsonb),
    p_target_kind, p_target_id, p_target_version, coalesce(p_run_after, now())
  )
  returning * into row;

  return query select row.*;
end;
$$;

-- Returns true when the job's captured target_version is older than the live row.
create or replace function background_job_target_is_stale(p_job_id uuid)
returns boolean
language plpgsql stable
as $$
declare
  j background_jobs;
  live_version bigint;
begin
  select * into j from background_jobs where id = p_job_id;
  if j.id is null or j.target_kind is null or j.target_id is null or j.target_version is null then
    return false;
  end if;

  if j.target_kind = 'note' then
    select content_version into live_version from notes where id = j.target_id;
  elsif j.target_kind = 'fact' then
    select content_version into live_version from kb_facts where id = j.target_id;
  else
    return false;
  end if;

  if live_version is null then
    return true;
  end if;

  return live_version > j.target_version;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS (service role bypasses; policies protect direct client access)
-- ---------------------------------------------------------------------------

alter table kb_memory_evidence enable row level security;
alter table note_chunks enable row level security;
alter table memory_suggestions enable row level security;
alter table memory_feedback enable row level security;
alter table memory_retrieval_events enable row level security;
alter table background_jobs enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'kb_memory_evidence' and policyname = 'kb_memory_evidence_owner_all'
  ) then
    create policy kb_memory_evidence_owner_all on kb_memory_evidence
      for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'note_chunks' and policyname = 'note_chunks_owner_all'
  ) then
    create policy note_chunks_owner_all on note_chunks
      for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'memory_suggestions' and policyname = 'memory_suggestions_owner_all'
  ) then
    create policy memory_suggestions_owner_all on memory_suggestions
      for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'memory_feedback' and policyname = 'memory_feedback_owner_all'
  ) then
    create policy memory_feedback_owner_all on memory_feedback
      for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'memory_retrieval_events' and policyname = 'memory_retrieval_events_owner_all'
  ) then
    create policy memory_retrieval_events_owner_all on memory_retrieval_events
      for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
end $$;

-- background_jobs: no direct client access (server-only via service role).
