-- Donna notes table (run after knowledge_base.sql in Supabase Dashboard → SQL Editor)

create table if not exists notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  source_id uuid references kb_sources (id) on delete set null,
  source_type text not null check (source_type in ('voice_turn', 'document', 'manual')),
  note_date timestamptz not null default now(),
  title text not null default '',
  content text not null,
  preview text not null default '',
  is_important boolean not null default false,
  is_urgent boolean not null default false,
  user_last_modified timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Dictation audio (notes-mode voice turns). Populated only when the user
  -- dictated this note out loud; null for typed/manual and compiler-derived
  -- notes. Audio lives in the `note-audio` storage bucket.
  audio_path text,
  audio_mime text not null default 'audio/wav'
);

create index if not exists notes_user_id_note_date_idx on notes (user_id, note_date desc);
create index if not exists notes_user_id_flags_idx on notes (user_id, is_urgent, is_important);

create unique index if not exists notes_source_id_unique
  on notes (source_id) where source_id is not null;

alter table notes add column if not exists search_vector tsvector
  generated always as (
    to_tsvector('english', coalesce(title, '') || ' ' || coalesce(content, '') || ' ' || coalesce(preview, ''))
  ) stored;

create index if not exists notes_search_idx on notes using gin (search_vector);
