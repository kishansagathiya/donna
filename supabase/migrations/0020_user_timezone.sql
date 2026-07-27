-- Per-user IANA timezone for calendar scheduling (e.g. Asia/Kolkata).
-- When set, Donna prefers this over Google Calendar's timezone for wall-clock times.

alter table user_preferences
  add column if not exists timezone text not null default '';
