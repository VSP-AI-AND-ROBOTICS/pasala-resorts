-- Logical replication emits only the primary key for a DELETE unless the
-- table carries a full replica identity. Supabase realtime needs the old row
-- to route the change to subscribers filtering on unit_id, so a cancellation
-- would otherwise never reach an open calendar.
alter table public.unit_calendar_events replica identity full;
