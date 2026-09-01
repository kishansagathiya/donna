-- Desktop local agent runtime: devices, workspaces, and local run routing.
-- Additive. Existing cloud runs keep execution_target='cloud'.

-- ---------------------------------------------------------------------------
-- Per-user dogfood flag (null = inherit server default, currently off)
-- ---------------------------------------------------------------------------

alter table user_preferences
  add column if not exists flag_local_agents_v1 boolean;

-- ---------------------------------------------------------------------------
-- desktop_devices
-- ---------------------------------------------------------------------------

create table if not exists desktop_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  public_device_id text not null,
  name text not null default 'Mac',
  platform text not null default 'macos'
    check (platform in ('macos')),
  architecture text not null default 'arm64',
  app_version text not null default '',
  capabilities jsonb not null default '{}'::jsonb,
  last_seen_at timestamptz,
  is_default boolean not null default false,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, public_device_id)
);

create index if not exists desktop_devices_user_id_idx
  on desktop_devices (user_id, is_default desc, last_seen_at desc)
  where revoked_at is null;

-- ---------------------------------------------------------------------------
-- desktop_workspaces (opaque id + display name only; paths stay on the Mac)
-- ---------------------------------------------------------------------------

create table if not exists desktop_workspaces (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null references desktop_devices(id) on delete cascade,
  name text not null,
  capabilities jsonb not null default '{}'::jsonb,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists desktop_workspaces_user_device_idx
  on desktop_workspaces (user_id, device_id);

-- ---------------------------------------------------------------------------
-- agent_runs local routing
-- ---------------------------------------------------------------------------

alter table agent_runs
  add column if not exists execution_target text not null default 'cloud';

alter table agent_runs
  drop constraint if exists agent_runs_execution_target_check;

alter table agent_runs
  add constraint agent_runs_execution_target_check
  check (execution_target in ('local', 'cloud'));

alter table agent_runs
  add column if not exists assigned_device_id uuid references desktop_devices(id) on delete set null;

alter table agent_runs
  add column if not exists workspace_id uuid references desktop_workspaces(id) on delete set null;

alter table agent_runs
  add column if not exists waiting_reason text;

alter table agent_runs
  drop constraint if exists agent_runs_waiting_reason_check;

alter table agent_runs
  add constraint agent_runs_waiting_reason_check
  check (
    waiting_reason is null or waiting_reason in (
      'device_offline',
      'device_busy',
      'workspace_unavailable',
      'desktop_required'
    )
  );

create index if not exists agent_runs_local_queue_idx
  on agent_runs (assigned_device_id, status, created_at)
  where execution_target = 'local' and status in ('queued', 'running');

create index if not exists agent_runs_execution_target_idx
  on agent_runs (execution_target, status)
  where status in ('queued', 'running');

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table desktop_devices enable row level security;
alter table desktop_workspaces enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'desktop_devices' and policyname = 'desktop_devices_owner_all'
  ) then
    create policy desktop_devices_owner_all on desktop_devices
      for all
      using (user_id = auth.uid())
      with check (user_id = auth.uid());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'desktop_workspaces' and policyname = 'desktop_workspaces_owner_all'
  ) then
    create policy desktop_workspaces_owner_all on desktop_workspaces
      for all
      using (user_id = auth.uid())
      with check (user_id = auth.uid());
  end if;
end $$;
