-- Intent → Action platform (Phase 1)
-- Tables: intents, actions, action_runs
-- Notes remain user-authored only; no action creates notes.

-- ---------------------------------------------------------------------------
-- System + user action registry
-- ---------------------------------------------------------------------------

create table if not exists actions (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  name text not null,
  description text not null default '',
  runner text not null check (runner in ('builtin', 'http', 'llm_template')),
  risk text not null check (risk in ('internal', 'external', 'irreversible')),
  input_schema jsonb not null default '{}'::jsonb,
  config jsonb not null default '{}'::jsonb,
  owner_type text not null default 'system'
    check (owner_type in ('system', 'user', 'store')),
  owner_user_id uuid,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (owner_type = 'system' and owner_user_id is null)
    or (owner_type <> 'system' and owner_user_id is not null)
  )
);

create unique index if not exists actions_system_slug_unique
  on actions (slug)
  where owner_type = 'system';

create unique index if not exists actions_user_slug_unique
  on actions (owner_user_id, slug)
  where owner_type = 'user' and owner_user_id is not null;

create index if not exists actions_owner_user_id_idx
  on actions (owner_user_id)
  where owner_user_id is not null;

create index if not exists actions_enabled_idx
  on actions (enabled)
  where enabled = true;

-- ---------------------------------------------------------------------------
-- Extracted intents (from notes / conversation turns)
-- ---------------------------------------------------------------------------

create table if not exists intents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  kind text not null,
  status text not null default 'open'
    check (status in ('open', 'dismissed', 'acted', 'expired')),
  summary text not null,
  slots jsonb not null default '{}'::jsonb,
  source_type text not null
    check (source_type in ('note', 'conversation_turn')),
  source_id text,
  source_turn_index int,
  confidence double precision,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists intents_user_id_status_idx
  on intents (user_id, status, created_at desc);

create index if not exists intents_user_id_created_at_idx
  on intents (user_id, created_at desc);

create index if not exists intents_source_idx
  on intents (source_type, source_id, source_turn_index);

-- Avoid duplicate open intents for the same source + kind.
create unique index if not exists intents_open_source_kind_unique
  on intents (user_id, source_type, source_id, (coalesce(source_turn_index, -1)), kind)
  where status = 'open';

-- ---------------------------------------------------------------------------
-- Action run ledger (proposed → confirmed → executed)
-- ---------------------------------------------------------------------------

create table if not exists action_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  intent_id uuid references intents (id) on delete set null,
  action_id uuid not null references actions (id) on delete restrict,
  status text not null default 'proposed'
    check (status in (
      'proposed',
      'confirmed',
      'denied',
      'cancelled',
      'running',
      'succeeded',
      'failed'
    )),
  input jsonb not null default '{}'::jsonb,
  output jsonb,
  error text,
  confirmed_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists action_runs_user_id_status_idx
  on action_runs (user_id, status, created_at desc);

create index if not exists action_runs_intent_id_idx
  on action_runs (intent_id)
  where intent_id is not null;

create index if not exists action_runs_action_id_idx
  on action_runs (action_id);

-- One active proposal per intent (proposed/confirmed/running).
create unique index if not exists action_runs_active_intent_unique
  on action_runs (intent_id)
  where intent_id is not null
    and status in ('proposed', 'confirmed', 'running');

-- ---------------------------------------------------------------------------
-- Seed first-party builtins (no create_note)
-- ---------------------------------------------------------------------------

insert into actions (slug, name, description, runner, risk, input_schema, config, owner_type)
select v.slug, v.name, v.description, v.runner, v.risk, v.input_schema, v.config, 'system'
from (
  values
    (
      'draft_message',
      'Draft message',
      'Draft a message to someone without sending it.',
      'builtin',
      'internal',
      '{"type":"object","properties":{"recipient":{"type":"string"},"subject":{"type":"string"},"body":{"type":"string"},"channel":{"type":"string"}},"required":["body"]}'::jsonb,
      '{"builtin":"draft_message"}'::jsonb
    ),
    (
      'propose_reminder',
      'Propose reminder',
      'Propose a reminder with a time and title for the user to confirm.',
      'builtin',
      'internal',
      '{"type":"object","properties":{"title":{"type":"string"},"when":{"type":"string"},"notes":{"type":"string"}},"required":["title"]}'::jsonb,
      '{"builtin":"propose_reminder"}'::jsonb
    ),
    (
      'open_url',
      'Open URL',
      'Propose opening a URL in the browser.',
      'builtin',
      'external',
      '{"type":"object","properties":{"url":{"type":"string"},"label":{"type":"string"}},"required":["url"]}'::jsonb,
      '{"builtin":"open_url"}'::jsonb
    )
) as v(slug, name, description, runner, risk, input_schema, config)
where not exists (
  select 1 from actions a
  where a.owner_type = 'system' and a.slug = v.slug
);

-- ---------------------------------------------------------------------------
-- RLS (service role bypasses; policies protect direct client access)
-- ---------------------------------------------------------------------------

alter table actions enable row level security;
alter table intents enable row level security;
alter table action_runs enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'actions' and policyname = 'actions_select_visible'
  ) then
    create policy actions_select_visible on actions
      for select
      using (
        owner_type = 'system'
        or owner_user_id = auth.uid()
      );
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'intents' and policyname = 'intents_owner_all'
  ) then
    create policy intents_owner_all on intents
      for all
      using (user_id = auth.uid())
      with check (user_id = auth.uid());
  end if;

  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'action_runs' and policyname = 'action_runs_owner_all'
  ) then
    create policy action_runs_owner_all on action_runs
      for all
      using (user_id = auth.uid())
      with check (user_id = auth.uid());
  end if;
end $$;
