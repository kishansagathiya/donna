-- AI employees: durable goal-driven workers that spawn agent_run shifts.
-- Extends agent_runs with employee_id and background_jobs target_kind.

alter table background_jobs drop constraint if exists background_jobs_target_kind_check;
alter table background_jobs
  add constraint background_jobs_target_kind_check
    check (target_kind is null or target_kind in (
      'note', 'fact', 'conversation', 'source', 'import', 'agent_run', 'ai_employee'
    ));

-- ---------------------------------------------------------------------------
-- ai_employees
-- ---------------------------------------------------------------------------

create table if not exists ai_employees (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  role text not null default '',
  goal text not null,
  status text not null default 'active'
    check (status in ('active', 'paused', 'completed', 'archived')),
  cadence_minutes int not null default 0
    check (cadence_minutes >= 0 and cadence_minutes <= 10080),
  max_steps_per_shift int not null default 40
    check (max_steps_per_shift > 0 and max_steps_per_shift <= 200),
  tool_allowlist text[] not null default '{}',
  progress_summary text not null default '',
  progress jsonb not null default '{}'::jsonb,
  current_agent_run_id uuid,
  shift_count int not null default 0,
  last_shift_at timestamptz,
  next_shift_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists ai_employees_user_status_idx
  on ai_employees (user_id, status, updated_at desc);

create index if not exists ai_employees_due_idx
  on ai_employees (status, next_shift_at)
  where status = 'active' and next_shift_at is not null;

-- ---------------------------------------------------------------------------
-- Link agent_runs to employees (FK after both tables exist)
-- ---------------------------------------------------------------------------

alter table agent_runs
  add column if not exists employee_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'agent_runs_employee_id_fkey'
  ) then
    alter table agent_runs
      add constraint agent_runs_employee_id_fkey
      foreign key (employee_id) references ai_employees(id) on delete set null;
  end if;
end $$;

create index if not exists agent_runs_employee_id_idx
  on agent_runs (employee_id, created_at desc)
  where employee_id is not null;

-- current_agent_run_id FK (deferred until agent_runs exists — always true here)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'ai_employees_current_agent_run_id_fkey'
  ) then
    alter table ai_employees
      add constraint ai_employees_current_agent_run_id_fkey
      foreign key (current_agent_run_id) references agent_runs(id) on delete set null;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table ai_employees enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'ai_employees'
      and policyname = 'ai_employees_owner_all'
  ) then
    create policy ai_employees_owner_all on ai_employees
      for all
      using (user_id = auth.uid())
      with check (user_id = auth.uid());
  end if;
end $$;
