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

-- ---------------------------------------------------------------------
-- Private helpers. Not security definer: they run with the rights of the
-- definer functions that call them, and nobody else can reach `private`.

-- base64url without padding (RFC 4648 section 5). encode() wraps its
-- output every 76 characters, so the newlines are dropped too.
create function private.b64url_encode(p_bytes bytea)
returns text
language sql
immutable
strict
set search_path = pg_catalog, pg_temp
as $$
  select rtrim(translate(encode(p_bytes, 'base64'), E'+/\n', '-_'), '=');
$$;

create function private.b64url_decode(p_text text)
returns bytea
language sql
immutable
strict
set search_path = pg_catalog, pg_temp
as $$
  select decode(rpad(translate(p_text, '-_', '+/'),
                     ((length(p_text) + 3) / 4) * 4, '='),
                'base64');
$$;

-- The pass tag: HMAC-SHA256 under the deployment secret over the version
-- prefix and the 40-byte body, cut to 16 bytes.
create function private.stay_pass_mac(p_body bytea)
returns bytea
language sql
stable
strict
set search_path = pg_catalog, pg_temp
as $$
  select substring(extensions.hmac(convert_to('rh1.', 'UTF8') || p_body,
                                   s.secret, 'sha256')
                   from 1 for 16)
    from private.stay_pass_secret s
   where s.id;
$$;

create function private.stay_pass_token(
  p_reservation uuid,
  p_property    uuid,
  p_expires     bigint
) returns text
language sql
stable
strict
set search_path = pg_catalog, pg_temp
as $$
  with body as (
    select decode(replace(p_reservation::text, '-', ''), 'hex')
        || decode(replace(p_property::text, '-', ''), 'hex')
        || int8send(p_expires) as b
  )
  select 'rh1.' || private.b64url_encode(b || private.stay_pass_mac(b))
    from body;
$$;

revoke all on all functions in schema private from public, anon, authenticated;

-- The signed check-in pass for the caller's own booking. The same booking
-- always gets the same pass, valid until the stay ends (spec decision 9).
-- Anyone else's booking, an unknown id or a non-booking row is simply "not
-- found", so the function never reveals which ids exist.
create function public.issue_stay_pass(p_reservation uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.reservations;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
   where id = p_reservation
     and customer_id = v_uid
     and kind = 'booking';
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_row.status not in ('confirmed', 'checked_in') then
    raise exception 'reservation is %', v_row.status using errcode = 'P0009';
  end if;

  return private.stay_pass_token(
    v_row.id, v_row.property_id,
    extract(epoch from upper(v_row.period))::bigint);
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
