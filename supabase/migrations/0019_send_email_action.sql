-- Seed send_email system action (Gmail send via Google integration).
-- Requires a connected Google integration with gmail.send scope at confirm time.

insert into actions (slug, name, description, runner, risk, input_schema, config, owner_type)
select v.slug, v.name, v.description, v.runner, v.risk, v.input_schema, v.config, 'system'
from (
  values
    (
      'send_email',
      'Send email',
      'Send an email via the user''s Gmail account after confirmation.',
      'builtin',
      'irreversible',
      '{"type":"object","properties":{"to":{"type":"string"},"recipient":{"type":"string"},"subject":{"type":"string"},"body":{"type":"string"},"cc":{"type":"string"}},"required":["body"]}'::jsonb,
      '{"builtin":"send_email","provider":"google"}'::jsonb
    )
) as v(slug, name, description, runner, risk, input_schema, config)
where not exists (
  select 1 from actions a
  where a.owner_type = 'system' and a.slug = v.slug
);
