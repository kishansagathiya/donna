-- ChatGPT export import: durable status rows for ZIP upload + async processing.

create table if not exists chatgpt_imports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'awaiting_upload'
    check (status in (
      'awaiting_upload', 'queued', 'running', 'completed', 'failed'
    )),
  storage_path text,
  bytes bigint,
  conversations_total int not null default 0,
  conversations_processed int not null default 0,
  memories_imported int not null default 0,
  cursor_index int not null default 0,
  error text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists chatgpt_imports_user_created_idx
  on chatgpt_imports (user_id, created_at desc);

create index if not exists chatgpt_imports_user_status_idx
  on chatgpt_imports (user_id, status);

alter table chatgpt_imports enable row level security;

-- Service role (Donna server) bypasses RLS; no end-user policies needed.
