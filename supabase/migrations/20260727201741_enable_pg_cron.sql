-- Enable pg_cron for scheduled jobs (booking expiry sweeps, etc.).
-- pg_cron ships preloaded in the Supabase local Postgres image's
-- shared_preload_libraries, so it only needs to be created as an extension.
--
-- Note: the task brief called for `[experimental] enable_pg_cron = true` in
-- supabase/config.toml, but Supabase CLI 2.110.0 rejects that key
-- ("'experimental' has invalid keys: enable_pg_cron"), which breaks
-- `supabase db reset` entirely. This migration achieves the same functional
-- outcome (pg_cron enabled) without an invalid config key.
create extension if not exists pg_cron with schema extensions;
