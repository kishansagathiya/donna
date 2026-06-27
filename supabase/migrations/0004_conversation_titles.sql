-- Conversation titles for chat history browsing.

alter table conversations
  add column if not exists title text not null default '';

-- Backfill from the first turn transcript (user message, then assistant).
update conversations c
set title = sub.title
from (
  select distinct on (conversation_id)
    conversation_id,
    left(
      regexp_replace(
        trim(
          case
            when nullif(trim(user_transcript), '') is not null then user_transcript
            else assistant_transcript
          end
        ),
        E'[\\n\\r]+',
        ' ',
        'g'
      ),
      80
    ) as title
  from conversation_turns
  order by conversation_id, turn_index asc
) sub
where c.id = sub.conversation_id
  and c.title = ''
  and sub.title is not null
  and sub.title <> '';
