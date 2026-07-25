-- Seed create_calendar_event system action (Google Calendar write).
-- Requires a connected Google integration at confirm/execute time.

insert into actions (slug, name, description, runner, risk, input_schema, config, owner_type)
select v.slug, v.name, v.description, v.runner, v.risk, v.input_schema, v.config, 'system'
from (
  values
    (
      'create_calendar_event',
      'Create calendar event',
      'Create an event on the user''s Google Calendar after confirmation.',
      'builtin',
      'external',
      '{"type":"object","properties":{"title":{"type":"string"},"when":{"type":"string"},"start":{"type":"string"},"end":{"type":"string"},"notes":{"type":"string"},"location":{"type":"string"},"attendees":{"type":"string"}},"required":["title"]}'::jsonb,
      '{"builtin":"create_calendar_event","provider":"google"}'::jsonb
    )
) as v(slug, name, description, runner, risk, input_schema, config)
where not exists (
  select 1 from actions a
  where a.owner_type = 'system' and a.slug = v.slug
);
