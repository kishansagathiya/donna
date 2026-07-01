-- Notes Tags System: per-user tag cloud + per-note tags with maintained counts.
-- Idempotent (uses IF NOT EXISTS). Mirrors Steve's notes tag model but user-scoped.

-- Tag registry: one row per (user_id, name) with a denormalized usage count.
create table if not exists tags (
  user_id uuid not null,
  name text not null,
  count int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, name)
);

create index if not exists tags_user_count_idx on tags (user_id, count desc);

-- Per-note tag membership. (user_id denormalized for easy filtering.)
create table if not exists note_tags (
  user_id uuid not null,
  note_id uuid not null references notes (id) on delete cascade,
  tag text not null,
  created_at timestamptz not null default now(),
  primary key (note_id, tag)
);

create index if not exists note_tags_user_tag_idx on note_tags (user_id, tag);
create index if not exists note_tags_note_id_idx on note_tags (note_id);

-- ---------------------------------------------------------------------------
-- set_note_tags(userId, noteId, text[]): transactional replace.
-- Dropping removed memberships decrements tag.count; new ones create/upsert
-- the tag row and increment it. Keeps tags.count consistent with note_tags.
-- Returns the final tag set for the note.
-- ---------------------------------------------------------------------------
create or replace function set_note_tags(
  p_user_id uuid,
  p_note_id uuid,
  p_tags text[]
) returns table (tag text)
language plpgsql as $$
declare
  desired text[];
  current_tags text[];
  to_remove text[];
  to_add text[];
  t text;
begin
  -- Verify the note belongs to the caller.
  if not exists (select 1 from notes where id = p_note_id and user_id = p_user_id) then
    raise exception 'note not found';
  end if;

  -- Normalize desired: lowercase, trimmed, dedup, no empties.
  select array_agg(distinct lower(trim(x))) into desired
  from unnest(p_tags) as x
  where trim(x) <> '';

  current_tags := array(
    select tag from note_tags where note_id = p_note_id and user_id = p_user_id order by tag
  );

  to_remove := array(
    select tag from unnest(current_tags) as c
    where c.tag <> all(coalesce(desired, array[]::text[]))
  );
  to_add := array(
    select tag from unnest(coalesce(desired, array[]::text[])) as d
    where d.tag <> all(coalesce(current_tags, array[]::text[]))
  );

  -- Remove dropped memberships + decrement counts.
  if array_length(to_remove, 1) is not null then
    delete from note_tags
      where note_id = p_note_id and user_id = p_user_id and tag = any(to_remove);

    foreach t in array to_remove loop
      update tags
        set count = greatest(count - 1, 0),
            updated_at = now()
        where user_id = p_user_id and name = t;
    end loop;

    -- Prune tags that have no remaining usage (best-effort).
    delete from tags where user_id = p_user_id and name = any(to_remove) and count <= 0;
  end if;

  -- Add new memberships + upsert/increment tag counts.
  if array_length(to_add, 1) is not null then
    insert into note_tags (user_id, note_id, tag)
      select p_user_id, p_note_id, unnest(to_add)
      on conflict (note_id, tag) do nothing;

    insert into tags (user_id, name, count)
      select p_user_id, unnest(to_add), 1
      on conflict (user_id, name)
      do update set count = tags.count + 1, updated_at = now();
  end if;

  return query
    select tag from unnest(coalesce(desired, array[]::text[])) as tag order by tag;
end;
$$;

-- ---------------------------------------------------------------------------
-- recompute_tag_counts(userId): maintenance command. Recomputes tags.count
-- from note_tags to repair drift (Steve's /fixcounts equivalent).
-- ---------------------------------------------------------------------------
create or replace function recompute_tag_counts(p_user_id uuid)
returns void
language plpgsql as $$
begin
  -- Delete all tags for this user
  delete from tags where user_id = p_user_id;
  
  -- Re-insert based on current note_tags
  insert into tags (user_id, name, count)
    select p_user_id, tag, count(*)::int
    from note_tags
    where user_id = p_user_id
    group by tag
    on conflict (user_id, name) do update set count = excluded.count, updated_at = now();
end;
$$;