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

-- Checks a scanned or typed pass at the front desk. The order is
-- deliberate (spec decision 11): format and signature, then the caller's
-- Staff+ role at the resort the pass names (so another resort's staff
-- learn nothing more), then expiry, then that the booking still exists at
-- that resort. The booking is returned in any status; check_in_booking
-- stays the only thing that changes it.
create function public.verify_stay_pass(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_raw     bytea;
  v_body    bytea;
  v_res_id  uuid;
  v_prop    uuid;
  v_expires bigint;
  v_row     public.reservations;
begin
  -- 'rh1.' and exactly 75 base64url characters (56 bytes). Anything else
  -- -- an old bare-UUID QR, a Wi-Fi code -- is not a pass, and decode()
  -- never sees it.
  if p_token is null or p_token !~ '^rh1\.[A-Za-z0-9_-]{75}$' then
    raise exception using errcode = 'P0034', message = 'pass_invalid';
  end if;

  v_raw  := private.b64url_decode(substr(p_token, 5));
  v_body := substring(v_raw from 1 for 40);
  if length(v_raw) <> 56
     or substring(v_raw from 41 for 16) <> private.stay_pass_mac(v_body) then
    raise exception using errcode = 'P0034', message = 'pass_invalid';
  end if;

  v_res_id  := encode(substring(v_body from 1 for 16), 'hex')::uuid;
  v_prop    := encode(substring(v_body from 17 for 16), 'hex')::uuid;
  v_expires := ('x' || encode(substring(v_body from 33 for 8), 'hex'))::bit(64)::bigint;

  if not public.has_resort_role(v_prop, false, 'owner','admin','staff','accountant') then
    raise exception using errcode = 'P0034', message = 'pass_other_resort';
  end if;

  if v_expires < extract(epoch from now()) then
    raise exception using errcode = 'P0034', message = 'pass_expired';
  end if;

  select * into v_row from public.reservations
   where id = v_res_id
     and property_id = v_prop
     and kind = 'booking';
  if not found then
    raise exception using errcode = 'P0034', message = 'pass_invalid';
  end if;

  return to_jsonb(v_row) || jsonb_build_object(
    'profiles', (select jsonb_build_object('full_name', p.full_name, 'phone', p.phone)
                   from public.profiles p
                  where p.id = v_row.customer_id),
    'unit_name', (select u.name from public.units u where u.id = v_row.unit_id));
end;
$$;

revoke execute on function public.issue_stay_pass(uuid) from public, anon;
revoke execute on function public.verify_stay_pass(text) from public, anon;
grant execute on function public.issue_stay_pass(uuid) to authenticated;
grant execute on function public.verify_stay_pass(text) to authenticated;
