-- Thumbs up/down feedback on assistant replies, keyed by conversation turn.
-- Cascade on conversation delete keeps account deletion simple.

create table if not exists conversation_turn_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  conversation_id uuid not null references conversations (id) on delete cascade,
  turn_index int not null,
  rating text not null check (rating in ('up', 'down')),
  comment text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (conversation_id, turn_index)
);

create index if not exists conversation_turn_feedback_user_id_idx
  on conversation_turn_feedback (user_id);
