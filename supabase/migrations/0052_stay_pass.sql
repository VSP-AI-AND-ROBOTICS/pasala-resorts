-- QR scanning at the front desk (P3): signed check-in passes.
-- See docs/superpowers/specs/2026-09-25-p3-qr-scanning-at-the-front-desk-design.md.
--
-- A pass is 'rh1.' || base64url(reservation id (16 bytes) || property id
-- (16) || expiry, epoch seconds (8, big-endian) || the first 16 bytes of
-- HMAC-SHA256(secret, 'rh1.' || those 40 bytes)): 79 characters. The key is
-- one random secret per database, in a schema the API does not expose;
-- only the security definer functions below read it.

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

create table private.stay_pass_secret (
  id         boolean primary key default true check (id),
  secret     bytea not null check (length(secret) >= 32),
  created_at timestamptz not null default now()
);
revoke all on private.stay_pass_secret from public, anon, authenticated;

-- One random secret per database; keeps whatever is already there.
-- Rotate with: update private.stay_pass_secret
--                 set secret = extensions.gen_random_bytes(32);
-- (every pass issued before then reads as pass_invalid).
insert into private.stay_pass_secret (secret)
values (extensions.gen_random_bytes(32))
on conflict (id) do nothing;

-- Stub: Task 2 replaces the body.
create function public.issue_stay_pass(p_reservation uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'issue_stay_pass not implemented';
end;
$$;

-- Stub: Task 3 replaces the body.
create function public.verify_stay_pass(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception using errcode = '0A000', message = 'verify_stay_pass not implemented';
end;
$$;

revoke execute on function public.issue_stay_pass(uuid) from public, anon;
revoke execute on function public.verify_stay_pass(text) from public, anon;
grant execute on function public.issue_stay_pass(uuid) to authenticated;
grant execute on function public.verify_stay_pass(text) to authenticated;
