-- Note image attachments: photos saved with a note (compose or detail),
-- stored in the private `note-attachments` bucket. Clients never see
-- storage_path; the server signs short-lived download URLs on read.

alter table notes
  add column if not exists attachments jsonb not null default '[]'::jsonb;

comment on column notes.attachments is
  'JSON array of {id, kind, filename, mime?, storage_path?} for images on this note.';

create index if not exists notes_has_image_idx
  on notes (user_id)
  where jsonb_typeof(attachments) = 'array' and jsonb_array_length(attachments) > 0;

-- Storage bucket: create "note-attachments" in Dashboard → Storage
-- (private bucket; server signs short-lived download URLs on read).
-- Also added to supabase/setup_storage.sh.
