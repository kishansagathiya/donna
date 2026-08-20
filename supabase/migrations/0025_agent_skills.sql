-- Agent skills (Phase 2 of the cloud agent harness plan).
-- Per-user + bundled system skills, agentskills.io-compatible SKILL.md content.
-- Also adds agent_runs.selected_skills for user-picked skills at spawn.

create table if not exists agent_skills (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  description text not null default '',
  content text not null default '',
  source text not null default 'user'
    check (source in ('user', 'agent')),
  agent_run_id uuid references agent_runs(id) on delete set null,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, name)
);

create index if not exists agent_skills_user_id_idx
  on agent_skills (user_id, updated_at desc);

-- User-selected skills at spawn (names; user skills shadow bundled system skills).
alter table agent_runs
  add column if not exists selected_skills text[] not null default '{}';

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table agent_skills enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'agent_skills' and policyname = 'agent_skills_owner_all'
  ) then
    create policy agent_skills_owner_all on agent_skills
      for all
      using (user_id = auth.uid())
      with check (user_id = auth.uid());
  end if;
end $$;
