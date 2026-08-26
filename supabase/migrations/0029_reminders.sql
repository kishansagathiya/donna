-- User reminders: timed alerts Donna can create from chat, Actions, or the Reminders UI.

create table if not exists reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  notes text not null default '',
  due_at timestamptz not null,
  timezone text not null default '',
  status text not null default 'scheduled'
    check (status in ('scheduled', 'fired', 'dismissed', 'cancelled')),
  action_run_id uuid references action_runs (id) on delete set null,
  fired_at timestamptz,
  dismissed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists reminders_user_status_due_idx
  on reminders (user_id, status, due_at);

create index if not exists reminders_due_scheduled_idx
  on reminders (due_at)
  where status = 'scheduled';

create index if not exists reminders_action_run_id_idx
  on reminders (action_run_id)
  where action_run_id is not null;

alter table reminders enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'reminders'
      and policyname = 'reminders_owner_all'
  ) then
    create policy reminders_owner_all on reminders
      for all
      using (user_id = auth.uid())
      with check (user_id = auth.uid());
  end if;
end $$;
