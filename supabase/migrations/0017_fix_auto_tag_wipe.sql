-- Hotfix: smart-tag enrichment was deleting legacy/manual tags.
--
-- Root cause: apply_auto_note_tags deleted ALL note_tags with locked=false.
-- Migration 0014 added locked boolean NOT NULL DEFAULT false without backfilling
-- existing manual/hashtag rows to locked=true, so the first auto-apply wiped them.
--
-- Also: hashtag sync used set_locked_note_tags (full replace), which removes any
-- tag not in the hashtag list. Hashtags should merge, not replace.

-- 1) Lock existing non-auto tags so future auto-apply cannot remove them.
update note_tags
set locked = true
where locked = false
  and origin in ('manual', 'hashtag');

-- Treat remaining non-auto unlocked rows as locked user tags.
update note_tags
set locked = true,
    origin = 'manual'
where locked = false
  and coalesce(origin, 'manual') <> 'auto';

-- 2) Only replace previous *auto* unlocked tags; never touch locked/manual/hashtag.
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
  preserved_tags text[];
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
    into preserved_tags
  from note_tags
  where note_id = p_note_id
    and user_id = p_user_id
    and (locked = true or coalesce(origin, 'manual') <> 'auto');

  delete from note_tags
  where note_id = p_note_id
    and user_id = p_user_id
    and locked = false
    and coalesce(origin, 'manual') = 'auto';

  foreach t in array cleaned loop
    if t = any(preserved_tags) then
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

-- 3) Hashtag merge: add/lock hashtags without removing other tags.
create or replace function apply_hashtag_note_tags(
  p_user_id uuid,
  p_note_id uuid,
  p_tags text[]
)
returns text[]
language plpgsql
as $$
declare
  t text;
  cleaned text[] := '{}';
  seen text[] := '{}';
  final_tags text[];
begin
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

  foreach t in array cleaned loop
    insert into tags (user_id, name, count, updated_at, normalized_name)
    values (p_user_id, t, 0, now(), t)
    on conflict (user_id, name) do update
      set updated_at = now(),
          normalized_name = coalesce(tags.normalized_name, excluded.normalized_name);

    insert into note_tags (user_id, note_id, tag, origin, locked)
    values (p_user_id, p_note_id, t, 'hashtag', true)
    on conflict (note_id, tag) do update
      set origin = case
            when note_tags.origin = 'manual' then 'manual'
            else 'hashtag'
          end,
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

-- 4) Explicit manual set still fully replaces the tag set (including clear-to-empty).
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

  delete from note_tags
  where note_id = p_note_id
    and user_id = p_user_id
    and (
      locked = false
      or coalesce(origin, 'manual') = 'auto'
      or cardinality(cleaned) = 0
      or not (tag = any(cleaned))
    );

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
