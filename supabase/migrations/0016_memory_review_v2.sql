-- Memory review inbox: outdated status, UI kinds, citation feedback actions.
-- Additive / idempotent where possible.

-- ---------------------------------------------------------------------------
-- kb_facts.review_status: add outdated
-- ---------------------------------------------------------------------------

alter table kb_facts drop constraint if exists kb_facts_review_status_check;
alter table kb_facts
  add constraint kb_facts_review_status_check
  check (review_status in (
    'active', 'pending_review', 'rejected', 'superseded', 'outdated'
  ));

-- ---------------------------------------------------------------------------
-- kb_facts.memory_kind: add routine, constraint, instruction
-- ---------------------------------------------------------------------------

alter table kb_facts drop constraint if exists kb_facts_memory_kind_check;
alter table kb_facts
  add constraint kb_facts_memory_kind_check
  check (memory_kind is null or memory_kind in (
    'identity', 'preference', 'relationship', 'goal', 'project',
    'habit', 'routine', 'location', 'event', 'fact', 'other',
    'constraint', 'instruction'
  ));

-- ---------------------------------------------------------------------------
-- memory_feedback.action: citation + review feedback
-- ---------------------------------------------------------------------------

alter table memory_feedback drop constraint if exists memory_feedback_action_check;
alter table memory_feedback
  add constraint memory_feedback_action_check
  check (action in (
    'confirm', 'reject', 'edit', 'merge', 'tag_correction',
    'not_relevant', 'outdated', 'accept', 'resolve'
  ));

-- Helpful indexes for review inbox filters
create index if not exists kb_facts_user_review_status_idx
  on kb_facts (user_id, review_status, created_at desc);

create index if not exists kb_facts_user_sensitivity_idx
  on kb_facts (user_id, sensitivity)
  where sensitivity in ('sensitive', 'restricted');

create index if not exists kb_memory_evidence_source_idx
  on kb_memory_evidence (user_id, source_kind, source_id);
