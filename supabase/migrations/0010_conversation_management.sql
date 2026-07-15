-- Conversation management: archive, pin, title provenance, tags, and search.
-- Soft-archive via archived_at (NULL = active). Hard-delete remains available via API.
-- title_source: auto (truncated) | llm (generated) | user (manual rename — never overwritten).

alter table conversations
  add column if not exists archived_at timestamptz,
  add column if not exists pinned_at timestamptz,
  add column if not exists title_source text not null default 'auto';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'conversations_title_source_check'
  ) then
    alter table conversations
      add constraint conversations_title_source_check
      check (title_source in ('auto', 'llm', 'user'));
  end if;
end $$;

create index if not exists conversations_user_active_updated_idx
  on conversations (user_id, archived_at, created_at desc);

create index if not exists conversations_user_pinned_idx
  on conversations (user_id, pinned_at desc nulls last)
  where pinned_at is not null;

-- Per-conversation tags (separate from note_tags; simple membership, no shared counts).
create table if not exists conversation_tags (
  user_id uuid not null,
  conversation_id uuid not null references conversations (id) on delete cascade,
  tag text not null,
  created_at timestamptz not null default now(),
  primary key (conversation_id, tag)
);

create index if not exists conversation_tags_user_tag_idx
  on conversation_tags (user_id, tag);

create index if not exists conversation_tags_conversation_id_idx
  on conversation_tags (conversation_id);

-- ---------------------------------------------------------------------------
-- set_conversation_tags(userId, conversationId, text[]): replace tag set.
-- ---------------------------------------------------------------------------
create or replace function set_conversation_tags(
  p_user_id uuid,
  p_conversation_id uuid,
  p_tags text[]
) returns table (tag text)
language plpgsql as $$
declare
  desired text[];
begin
  if not exists (
    select 1 from conversations
    where id = p_conversation_id and user_id = p_user_id
  ) then
    raise exception 'conversation not found';
  end if;

  select array_agg(distinct lower(trim(x))) into desired
  from unnest(coalesce(p_tags, array[]::text[])) as x
  where trim(x) <> '';

  delete from conversation_tags
  where conversation_id = p_conversation_id and user_id = p_user_id;

  if desired is not null then
    insert into conversation_tags (user_id, conversation_id, tag)
      select p_user_id, p_conversation_id, unnest(desired)
      on conflict (conversation_id, tag) do nothing;
  end if;

  return query
    select t.tag
    from unnest(coalesce(desired, array[]::text[])) as t(tag)
    order by t.tag;
end;
$$;

-- ---------------------------------------------------------------------------
-- search_conversations: keyword match on title + turn transcripts.
-- Returns conversation ids ordered by recency of last activity (created_at of
-- latest matching turn, else conversation created_at), pinned first.
-- ---------------------------------------------------------------------------
create or replace function search_conversations(
  p_user_id uuid,
  p_query text,
  p_limit int default 50,
  p_include_archived boolean default false
) returns table (conversation_id uuid)
language sql stable as $$
  with q as (
    select trim(p_query) as needle
  ),
  matched as (
    select distinct c.id as conversation_id,
      c.pinned_at,
      coalesce(
        (select max(t.created_at) from conversation_turns t where t.conversation_id = c.id),
        c.created_at
      ) as activity_at
    from conversations c
    cross join q
    where c.user_id = p_user_id
      and q.needle <> ''
      and (p_include_archived or c.archived_at is null)
      and (
        c.title ilike '%' || q.needle || '%'
        or exists (
          select 1 from conversation_turns t
          where t.conversation_id = c.id
            and (
              t.user_transcript ilike '%' || q.needle || '%'
              or t.assistant_transcript ilike '%' || q.needle || '%'
            )
        )
      )
  )
  select m.conversation_id
  from matched m
  order by
    (m.pinned_at is not null) desc,
    m.pinned_at desc nulls last,
    m.activity_at desc
  limit greatest(coalesce(p_limit, 50), 1);
$$;
