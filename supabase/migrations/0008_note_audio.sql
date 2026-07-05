-- Note audio: stores the path/mime of the dictation WAV for notes that were
-- dictated out loud via the /voice WebSocket in `notes` mode. Older notes
-- dictated before this migration have no audio_path and the clients hide the
-- play button for them. Manual/text notes and compiler-derived notes (with
-- source_type = 'voice_turn' talking to Donna) also stay text-only here —
-- their audio already lives in the conversation-audio bucket keyed by
-- conversation/turn, surfaced through a different code path.

alter table notes
  add column if not exists audio_path text;

alter table notes
  add column if not exists audio_mime text default 'audio/wav';

-- Index for "show me my voice notes" filters later, if we ever need it.
create index if not exists notes_has_audio_idx
  on notes (user_id)
  where audio_path is not null;