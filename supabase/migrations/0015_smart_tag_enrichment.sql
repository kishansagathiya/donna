-- Notes V2 smart-tag enrichment helpers (#160)
-- Additive: preserves locked manual/hashtag tags; supports taxonomy ops.

-- Ensure normalized_name is populated for existing tags.
update tags
set normalized_name = lower(trim(name))
where normalized_name is null or btrim(normalized_name) = '';

create index if not exists tags_user_normalized_name_idx
  on tags (user_id, normalized_name);

-- Apply auto tags without removing locked rows. Replaces unlocked auto tags only.
create or replace function apply_auto_note_tags(
  p_user_id uuid,
  p_note_id uuid,
  p_auto_tags text[]
)
returns text[]
language plpgsql
as $$
declare
  t text;
  cleaned text[] := '{}';
  seen text[] := '{}';
  locked_tags text[];
  final_tags text[];
begin
  if p_auto_tags is null then
    p_auto_tags := '{}';
  end if;

  foreach t in array p_auto_tags loop
    t := lower(trim(t));
    if t = '' or t = any(seen) then
      continue;
    end if;
    seen := array_append(seen, t);
    cleaned := array_append(cleaned, t);
  end loop;

  select coalesce(array_agg(tag order by tag), '{}')
    into locked_tags
  from note_tags
  where note_id = p_note_id
    and user_id = p_user_id
    and locked = true;

  -- Drop previous unlocked (auto) tags for this note.
  delete from note_tags
  where note_id = p_note_id
    and user_id = p_user_id
    and locked = false;

  foreach t in array cleaned loop
    if t = any(locked_tags) then
      continue;
    end if;

    insert into tags (user_id, name, count, updated_at, normalized_name)
    values (p_user_id, t, 0, now(), t)
    on conflict (user_id, name) do update
      set updated_at = now(),
          normalized_name = coalesce(tags.normalized_name, excluded.normalized_name);

    insert into note_tags (user_id, note_id, tag, origin, locked)
    values (p_user_id, p_note_id, t, 'auto', false)
    on conflict (note_id, tag) do update
      set origin = case when note_tags.locked then note_tags.origin else 'auto' end,
          locked = note_tags.locked;
  end loop;

  perform recompute_tag_counts(p_user_id);

  select coalesce(array_agg(tag order by tag), '{}')
    into final_tags
  from note_tags
  where note_id = p_note_id
    and user_id = p_user_id;

  return final_tags;
end;
$$;

-- Replace tags while marking them locked (manual / hashtag).
create or replace function set_locked_note_tags(
  p_user_id uuid,
  p_note_id uuid,
  p_tags text[],
  p_origin text default 'manual'
)
returns text[]
language plpgsql
as $$
declare
  t text;
  cleaned text[] := '{}';
  seen text[] := '{}';
  final_tags text[];
  origin text := coalesce(nullif(trim(p_origin), ''), 'manual');
begin
  if origin not in ('manual', 'hashtag') then
    origin := 'manual';
  end if;

  if p_tags is null then
    p_tags := '{}';
  end if;

  foreach t in array p_tags loop
    t := lower(trim(t));
    if t = '' or t = any(seen) then
      continue;
    end if;
    seen := array_append(seen, t);
    cleaned := array_append(cleaned, t);
  end loop;

  -- Remove unlocked tags; keep locked tags that remain in cleaned.
  delete from note_tags
  where note_id = p_note_id
    and user_id = p_user_id
    and (locked = false or not (tag = any(cleaned)));

  foreach t in array cleaned loop
    insert into tags (user_id, name, count, updated_at, normalized_name)
    values (p_user_id, t, 0, now(), t)
    on conflict (user_id, name) do update
      set updated_at = now(),
          normalized_name = coalesce(tags.normalized_name, excluded.normalized_name);

    insert into note_tags (user_id, note_id, tag, origin, locked)
    values (p_user_id, p_note_id, t, origin, true)
    on conflict (note_id, tag) do update
      set origin = excluded.origin,
          locked = true;
  end loop;

  perform recompute_tag_counts(p_user_id);

  select coalesce(array_agg(tag order by tag), '{}')
    into final_tags
  from note_tags
  where note_id = p_note_id
    and user_id = p_user_id;

  return final_tags;
end;
$$;

-- Pin / unpin a canonical tag.
create or replace function pin_tag(
  p_user_id uuid,
  p_tag text,
  p_pinned boolean
)
returns void
language plpgsql
as $$
begin
  update tags
  set pinned = coalesce(p_pinned, false),
      updated_at = now()
  where user_id = p_user_id
    and name = lower(trim(p_tag));
end;
$$;

-- Alias source tag onto canonical tag.
create or replace function alias_tag(
  p_user_id uuid,
  p_source text,
  p_canonical text
)
returns void
language plpgsql
as $$
declare
  src text := lower(trim(p_source));
  canon text := lower(trim(p_canonical));
begin
  if src = '' or canon = '' or src = canon then
    return;
  end if;

  insert into tags (user_id, name, count, updated_at, normalized_name)
  values (p_user_id, canon, 0, now(), canon)
  on conflict (user_id, name) do update
    set updated_at = now(),
        alias_of = null;

  insert into tags (user_id, name, count, updated_at, normalized_name, alias_of)
  values (p_user_id, src, 0, now(), src, canon)
  on conflict (user_id, name) do update
    set alias_of = canon,
        updated_at = now();

  -- Move note memberships from alias -> canonical.
  insert into note_tags (user_id, note_id, tag, origin, locked)
  select user_id, note_id, canon, origin, locked
  from note_tags
  where user_id = p_user_id and tag = src
  on conflict (note_id, tag) do nothing;

  delete from note_tags
  where user_id = p_user_id and tag = src;

  perform recompute_tag_counts(p_user_id);
end;
$$;

-- Rename a canonical tag (and rewrite note_tags + aliases).
create or replace function rename_tag(
  p_user_id uuid,
  p_from text,
  p_to text
)
returns void
language plpgsql
as $$
declare
  src text := lower(trim(p_from));
  dest text := lower(trim(p_to));
begin
  if src = '' or dest = '' or src = dest then
    return;
  end if;

  insert into tags (user_id, name, count, updated_at, normalized_name, pinned, alias_of)
  select p_user_id, dest, count, now(), dest, pinned, null
  from tags
  where user_id = p_user_id and name = src
  on conflict (user_id, name) do update
    set updated_at = now(),
        alias_of = null,
        pinned = greatest(tags.pinned, excluded.pinned);

  insert into note_tags (user_id, note_id, tag, origin, locked)
  select user_id, note_id, dest, origin, locked
  from note_tags
  where user_id = p_user_id and tag = src
  on conflict (note_id, tag) do nothing;

  delete from note_tags where user_id = p_user_id and tag = src;

  update tags
  set alias_of = dest,
      updated_at = now()
  where user_id = p_user_id
    and alias_of = src;

  delete from tags where user_id = p_user_id and name = src;

  perform recompute_tag_counts(p_user_id);
end;
$$;

-- Merge source into canonical (alias + membership move).
create or replace function merge_tags(
  p_user_id uuid,
  p_source text,
  p_canonical text
)
returns void
language plpgsql
as $$
begin
  perform alias_tag(p_user_id, p_source, p_canonical);
end;
$$;
