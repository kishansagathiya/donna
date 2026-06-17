-- One-time backfill: create notes from existing kb_sources that don't have a note yet.
-- Run in Supabase SQL Editor after notes.sql migration.

insert into notes (
  user_id,
  source_id,
  source_type,
  note_date,
  title,
  content,
  preview,
  created_at,
  updated_at
)
select
  s.user_id,
  s.id,
  case
    when s.source_type = 'voice_turn' then 'voice_turn'
    else 'document'
  end,
  s.created_at,
  case
    when trim(split_part(s.content, E'\n', 1)) = '' then 'Untitled Note'
    when length(trim(split_part(s.content, E'\n', 1))) > 50
      then left(trim(split_part(s.content, E'\n', 1)), 50) || '...'
    else trim(split_part(s.content, E'\n', 1))
  end,
  case
    when s.source_type = 'voice_turn' and s.content like 'User: %' then
      trim(split_part(replace(s.content, E'\nAssistant: ', E'\n'), E'\n', 1))
    else s.content
  end,
  left(
    case
      when s.source_type = 'voice_turn' and s.content like 'User: %' then
        trim(split_part(replace(s.content, E'\nAssistant: ', E'\n'), E'\n', 2))
      else nullif(trim(regexp_replace(s.content, E'^[^\\n]+\\n?', '')), '')
    end,
    80
  ),
  s.created_at,
  s.created_at
from kb_sources s
where not exists (
  select 1 from notes n where n.source_id = s.id
);
