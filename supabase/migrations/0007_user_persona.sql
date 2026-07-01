-- Configurable AI persona: per-user persona selection + optional custom prompt.
-- Idempotent (uses IF NOT EXISTS). Builds on user_preferences from 0002.

-- persona: built-in persona id (default 'companion').
-- persona_custom: free-text users may supply when persona = 'custom'.
alter table user_preferences add column if not exists persona text not null default 'companion';
alter table user_preferences add column if not exists persona_custom text not null default '';