-- Chat turn attachments: keep the user-facing prompt separate from the
-- vision/text grounding used for the LLM, and store attachment metadata so
-- reloaded chats can show the original message with image previews.

alter table conversation_turns
  add column if not exists user_grounded_transcript text;

alter table conversation_turns
  add column if not exists attachments jsonb not null default '[]'::jsonb;

comment on column conversation_turns.user_transcript is
  'User-facing prompt shown in the chat UI (original text + attachment labels).';

comment on column conversation_turns.user_grounded_transcript is
  'LLM grounding text for this turn (includes extracted attachment content). Used when resuming chat history.';

comment on column conversation_turns.attachments is
  'JSON array of {kind, filename, mime?, storage_path?, url?} for this turn.';

-- Storage bucket: create "chat-attachments" in Dashboard → Storage
-- (private bucket; server signs short-lived download URLs on read).
