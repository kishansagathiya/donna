create table if not exists user_preferences (
  user_id uuid primary key,
  llm_model text not null,
  updated_at timestamptz not null default now()
);
