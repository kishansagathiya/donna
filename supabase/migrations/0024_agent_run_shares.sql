-- Public agent-run share links (prompt + output only).
-- Access is via opaque token through the Go API (service role). RLS blocks
-- direct PostgREST access from anon/authenticated clients.

create table if not exists agent_run_shares (
  id uuid primary key default gen_random_uuid(),
  agent_run_id uuid not null references agent_runs (id) on delete cascade,
  user_id uuid not null,
  token text not null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  expires_at timestamptz,
  constraint agent_run_shares_token_nonempty
    check (char_length(trim(token)) >= 16)
);

create unique index if not exists agent_run_shares_token_uidx
  on agent_run_shares (token);

-- At most one active (non-revoked) share per agent run.
create unique index if not exists agent_run_shares_active_run_uidx
  on agent_run_shares (agent_run_id)
  where revoked_at is null;

create index if not exists agent_run_shares_user_id_idx
  on agent_run_shares (user_id, created_at desc);

create index if not exists agent_run_shares_agent_run_id_idx
  on agent_run_shares (agent_run_id);

alter table agent_run_shares enable row level security;
