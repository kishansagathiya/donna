-- Mini apps: user-authored prompt recipes with optional schedules and sharing.
-- Access path today is donna-server-go with the service role (same as notes/conversations).
-- See docs/improvement-plans/03-user-launched-mini-apps.md.

-- ---------------------------------------------------------------------------
-- Definitions (author-owned recipes)
-- ---------------------------------------------------------------------------

create table if not exists mini_apps (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null,
  name text not null,
  description text not null default '',
  prompt text not null,
  capabilities jsonb not null default '{"web_search": false, "use_memory": true}'::jsonb,
  visibility text not null default 'private'
    check (visibility in ('private', 'unlisted', 'public')),
  slug text,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint mini_apps_name_nonempty check (length(trim(name)) > 0),
  constraint mini_apps_prompt_nonempty check (length(trim(prompt)) > 0),
  constraint mini_apps_slug_format check (
    slug is null or slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
  )
);

-- Slug must be unique when present (share URLs).
create unique index if not exists mini_apps_slug_uidx
  on mini_apps (slug)
  where slug is not null;

create index if not exists mini_apps_owner_updated_idx
  on mini_apps (owner_user_id, archived_at, updated_at desc);

create index if not exists mini_apps_gallery_idx
  on mini_apps (updated_at desc)
  where visibility = 'public' and archived_at is null;

-- ---------------------------------------------------------------------------
-- Installs (per-user instance + schedule)
-- Authors get an install row too; schedule lives here so shared apps aren't
-- locked to one timezone.
-- ---------------------------------------------------------------------------

create table if not exists mini_app_installs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  mini_app_id uuid not null references mini_apps (id) on delete cascade,
  enabled boolean not null default true,
  -- v1 schedule: none | daily wall-clock in the install timezone.
  schedule_kind text not null default 'none'
    check (schedule_kind in ('none', 'daily')),
  schedule_time time,
  -- Bitmask: Mon=1, Tue=2, Wed=4, Thu=8, Fri=16, Sat=32, Sun=64.
  -- NULL or 127 = every day when schedule_kind = 'daily'.
  schedule_days int
    check (schedule_days is null or (schedule_days >= 1 and schedule_days <= 127)),
  timezone text not null default 'UTC',
  next_run_at timestamptz,
  last_run_at timestamptz,
  notify_on_complete boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, mini_app_id),
  constraint mini_app_installs_daily_requires_time check (
    schedule_kind = 'none'
    or (schedule_time is not null and length(trim(timezone)) > 0)
  )
);

create index if not exists mini_app_installs_user_idx
  on mini_app_installs (user_id, updated_at desc);

create index if not exists mini_app_installs_due_idx
  on mini_app_installs (next_run_at)
  where enabled = true
    and schedule_kind <> 'none'
    and next_run_at is not null;

create index if not exists mini_app_installs_app_idx
  on mini_app_installs (mini_app_id);

-- ---------------------------------------------------------------------------
-- Runs (execution history)
-- ---------------------------------------------------------------------------

create table if not exists mini_app_runs (
  id uuid primary key default gen_random_uuid(),
  install_id uuid not null references mini_app_installs (id) on delete cascade,
  mini_app_id uuid not null references mini_apps (id) on delete cascade,
  user_id uuid not null,
  trigger text not null check (trigger in ('manual', 'schedule')),
  status text not null default 'pending'
    check (status in ('pending', 'running', 'succeeded', 'failed')),
  prompt_resolved text not null default '',
  output_text text not null default '',
  error text,
  conversation_id uuid references conversations (id) on delete set null,
  timings jsonb,
  started_at timestamptz not null default now(),
  finished_at timestamptz
);

create index if not exists mini_app_runs_install_started_idx
  on mini_app_runs (install_id, started_at desc);

create index if not exists mini_app_runs_user_started_idx
  on mini_app_runs (user_id, started_at desc);

create index if not exists mini_app_runs_status_started_idx
  on mini_app_runs (status, started_at)
  where status in ('pending', 'running');

-- ---------------------------------------------------------------------------
-- Claim due installs for the scheduler (service-role / server tick).
-- SKIP LOCKED so a future multi-replica tick won't double-run.
-- ---------------------------------------------------------------------------

create or replace function claim_due_mini_app_installs(
  p_limit int default 10
)
returns setof mini_app_installs
language plpgsql
as $$
begin
  return query
  with due as (
    select i.id
    from mini_app_installs i
    where i.enabled = true
      and i.schedule_kind <> 'none'
      and i.next_run_at is not null
      and i.next_run_at <= now()
    order by i.next_run_at asc
    limit greatest(coalesce(p_limit, 10), 1)
    for update skip locked
  )
  update mini_app_installs i
  set updated_at = now()
  from due
  where i.id = due.id
  returning i.*;
end;
$$;
