-- Public conversation share links (ChatGPT/Claude-style).
-- Access is via opaque token through the Go API (service role). RLS blocks
-- direct PostgREST access from anon/authenticated clients.

create table if not exists conversation_shares (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations (id) on delete cascade,
  user_id uuid not null,
  token text not null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  expires_at timestamptz,
  constraint conversation_shares_token_nonempty
    check (char_length(trim(token)) >= 16)
);

create unique index if not exists conversation_shares_token_uidx
  on conversation_shares (token);

-- At most one active (non-revoked) share per conversation.
create unique index if not exists conversation_shares_active_conversation_uidx
  on conversation_shares (conversation_id)
  where revoked_at is null;

create index if not exists conversation_shares_user_id_idx
  on conversation_shares (user_id, created_at desc);

create index if not exists conversation_shares_conversation_id_idx
  on conversation_shares (conversation_id);

alter table conversation_shares enable row level security;
