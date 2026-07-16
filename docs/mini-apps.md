# Mini apps

User-authored prompt recipes that Donna can run on demand or on a schedule.
Private by default; optionally shareable.

See the full design in [improvement-plans/03-user-launched-mini-apps.md](./improvement-plans/03-user-launched-mini-apps.md).

## Status

**Phase 0 (schema + plan):** landed in this repo.

- Migration: `supabase/migrations/0011_mini_apps.sql`
- Tables: `mini_apps`, `mini_app_installs`, `mini_app_runs`
- Scheduler helper: `claim_due_mini_app_installs(limit)`

**Phase 1 (personal create / run / schedule):** not started — needs Go API + web UI.

## Example

“Every day at 8:00, run my news prompt with web search” → one `mini_apps` row + an owner `mini_app_installs` row with `schedule_kind = 'daily'`.
