-- Leftover Phase 2: child agent_runs + seed agent_approval ledger action.
-- action_runs.agent_run_id / approval_kind already exist from 0023.

alter table agent_runs
  add column if not exists parent_run_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'agent_runs_parent_run_id_fkey'
  ) then
    alter table agent_runs
      add constraint agent_runs_parent_run_id_fkey
      foreign key (parent_run_id) references agent_runs(id) on delete set null;
  end if;
end $$;

create index if not exists agent_runs_parent_run_id_idx
  on agent_runs (parent_run_id)
  where parent_run_id is not null;

insert into actions (slug, name, description, runner, risk, input_schema, config, owner_type)
select v.slug, v.name, v.description, v.runner, v.risk, v.input_schema, v.config, 'system'
from (
  values
    (
      'agent_approval',
      'Agent approval',
      'Approve or deny an irreversible step requested by a cloud agent. Confirm resumes the agent; this action does not charge a card or send mail by itself.',
      'builtin',
      'irreversible',
      '{"type":"object","properties":{"kind":{"type":"string"},"summary":{"type":"string"},"details":{"type":"object"}},"required":["summary"]}'::jsonb,
      '{"builtin":"agent_approval"}'::jsonb
    )
) as v(slug, name, description, runner, risk, input_schema, config)
where not exists (
  select 1 from actions a
  where a.owner_type = 'system' and a.slug = v.slug
);
