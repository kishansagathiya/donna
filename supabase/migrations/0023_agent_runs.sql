-- Per-user cloud agent harness (Hermes-grade long-running runs).
-- Tables: agent_runs, agent_steps
-- Links approvals via action_runs.agent_run_id
-- Extends background_jobs target_kind for agent_run

-- Allow agent_run (and import if missing) as background job targets.
alter table background_jobs drop constraint if exists background_jobs_target_kind_check;
alter table background_jobs
  add constraint background_jobs_target_kind_check
  check (target_kind is null or target_kind in ('note', 'fact', 'conversation', 'source', 'import', 'agent_run'));

-- ---------------------------------------------------------------------------
-- agent_runs
-- ---------------------------------------------------------------------------

create table if not exists agent_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  intent_id uuid references intents(id) on delete set null,
  goal text not null,
  status text not null default 'queued'
    check (status in (
      'queued',
      'running',
      'waiting_for_user',
      'succeeded',
      'failed',
      'cancelled',
      'expired'
    )),
  plan jsonb not null default '[]'::jsonb,
  memory_snapshot jsonb not null default '{}'::jsonb,
  tool_allowlist text[] not null default '{}',
  max_steps int not null default 80,
  step_count int not null default 0,
  redirect_pending text,
  lease_owner text,
  lease_until timestamptz,
  last_heartbeat_at timestamptz,
  error text,
  result jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  finished_at timestamptz
);

create index if not exists agent_runs_user_id_status_idx
  on agent_runs (user_id, status, created_at desc);

create index if not exists agent_runs_lease_idx
  on agent_runs (status, lease_until)
  where status in ('queued', 'running');

create index if not exists agent_runs_intent_id_idx
  on agent_runs (intent_id)
  where intent_id is not null;

-- ---------------------------------------------------------------------------
-- agent_steps
-- ---------------------------------------------------------------------------

create table if not exists agent_steps (
  id uuid primary key default gen_random_uuid(),
  agent_run_id uuid not null references agent_runs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  seq int not null,
  kind text not null check (kind in (
    'thought',
    'tool_call',
    'tool_result',
    'memory_retrieve',
    'approval_request',
    'user_message',
    'status',
    'compress',
    'error'
  )),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (agent_run_id, seq)
);

create index if not exists agent_steps_run_seq_idx
  on agent_steps (agent_run_id, seq);

create index if not exists agent_steps_user_id_idx
  on agent_steps (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Link action_runs to agent approvals
-- ---------------------------------------------------------------------------

alter table action_runs
  add column if not exists agent_run_id uuid references agent_runs(id) on delete set null;

alter table action_runs
  add column if not exists approval_kind text;

create index if not exists action_runs_agent_run_id_idx
  on action_runs (agent_run_id)
  where agent_run_id is not null;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table agent_runs enable row level security;
alter table agent_steps enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'agent_runs' and policyname = 'agent_runs_owner_all'
  ) then
    create policy agent_runs_owner_all on agent_runs
      for all
      using (user_id = auth.uid())
      with check (user_id = auth.uid());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'agent_steps' and policyname = 'agent_steps_owner_all'
  ) then
    create policy agent_steps_owner_all on agent_steps
      for all
      using (user_id = auth.uid())
      with check (user_id = auth.uid());
  end if;
end $$;
