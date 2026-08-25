-- Phase 3: scheduled agent goals (Hermes cron analogue) + agent_run link.
-- Also allows intents sourced from an agent run (calendar write-back).

alter table intents drop constraint if exists intents_source_type_check;
alter table intents
  add constraint intents_source_type_check
    check (source_type in ('note', 'conversation_turn', 'agent_run'));

-- ---------------------------------------------------------------------------
-- scheduled_agent_goals
-- ---------------------------------------------------------------------------

create table if not exists scheduled_agent_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  goal text not null,
  status text not null default 'active'
    check (status in ('active', 'paused', 'completed', 'archived')),
  cadence_minutes int not null default 1440
    check (cadence_minutes >= 0 and cadence_minutes <= 10080),
  selected_skills text[] not null default '{}',
  last_summary text not null default '',
  current_agent_run_id uuid,
  run_count int not null default 0,
  last_run_at timestamptz,
  next_run_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists scheduled_agent_goals_user_status_idx
  on scheduled_agent_goals (user_id, status, updated_at desc);

create index if not exists scheduled_agent_goals_due_idx
  on scheduled_agent_goals (status, next_run_at)
  where status = 'active' and next_run_at is not null;

-- ---------------------------------------------------------------------------
-- Link agent_runs to schedules
-- ---------------------------------------------------------------------------

alter table agent_runs
  add column if not exists schedule_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'agent_runs_schedule_id_fkey'
  ) then
    alter table agent_runs
      add constraint agent_runs_schedule_id_fkey
      foreign key (schedule_id) references scheduled_agent_goals(id) on delete set null;
  end if;
end $$;

create index if not exists agent_runs_schedule_id_idx
  on agent_runs (schedule_id, created_at desc)
  where schedule_id is not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'scheduled_agent_goals_current_agent_run_id_fkey'
  ) then
    alter table scheduled_agent_goals
      add constraint scheduled_agent_goals_current_agent_run_id_fkey
      foreign key (current_agent_run_id) references agent_runs(id) on delete set null;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table scheduled_agent_goals enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'scheduled_agent_goals'
      and policyname = 'scheduled_agent_goals_owner_all'
  ) then
    create policy scheduled_agent_goals_owner_all on scheduled_agent_goals
      for all
      using (user_id = auth.uid())
      with check (user_id = auth.uid());
  end if;
end $$;
