-- Text chat persistence: reuse conversations + conversation_turns with a channel discriminator.

alter table conversations
  add column if not exists channel text not null default 'voice'
    check (channel in ('voice', 'text')),
  add column if not exists client_session_id text;

alter table conversations
  alter column voice_session_id drop not null;

create unique index if not exists conversations_user_text_session_idx
  on conversations (user_id, client_session_id)
  where channel = 'text' and client_session_id is not null;
