-- Coupon management (P1): owners and admins create, edit, deactivate and
-- list their resort's coupons. See
-- docs/superpowers/specs/2026-09-25-p1-coupon-management-design.md.
--
-- Redemption is unchanged: resolve_coupon, get_quote and create_hold
-- (latest in 0045) still match a code exactly. So codes are stored
-- upper-case and trimmed from now on, and the guest's coupon field sends
-- them that way.
--
-- Error code: P0033 coupon_invalid. The message is one reason word:
-- code_invalid, code_taken, kind_required, value_invalid,
-- min_amount_invalid, dates_invalid, usage_limit_invalid,
-- usage_limit_below_used, guest_not_eligible. Also raised: P0002 (unknown
-- coupon), P0005 (missing active flag), P0020 not_a_member, P0022
-- resort_suspended.

-- ---------------------------------------------------------------------
-- Codes are upper-case and trimmed. Existing codes are normalised first.
-- A code whose normalised form would collide with another code at the
-- same resort keeps its spelling, and the check then stays NOT VALID (it
-- still applies to every new or changed row).
update public.coupons c
   set code = upper(btrim(c.code))
 where c.code <> upper(btrim(c.code))
   and not exists (select 1 from public.coupons d
                    where d.property_id = c.property_id
                      and d.id <> c.id
                      and upper(btrim(d.code)) = upper(btrim(c.code)));

alter table public.coupons
  add constraint coupons_code_upper check (code = upper(btrim(code))) not valid;

do $$
begin
  if not exists (select 1 from public.coupons where code <> upper(btrim(code))) then
    alter table public.coupons validate constraint coupons_code_upper;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Coupon functions. The signatures are the contract the app is built
-- against; Tasks 2 and 3 of the plan replace the stub bodies.

-- Every coupon of the resort, for the Coupons screen. Owner/admin of the
-- resort (reads are allowed while it is suspended).
create function public.list_coupons(p_property uuid)
returns table (
  id                uuid,
  code              text,
  kind              public.coupon_kind,
  value             numeric,
  min_booking_value numeric,
  valid_from        date,
  valid_until       date,
  max_redemptions   int,
  redeemed_count    int,
  customer_id       uuid,
  customer_email    text,
  customer_name     text,
  is_active         boolean,
  status            text,
  created_at        timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'list_coupons is not implemented yet' using errcode = '0A000';
end;
$$;

-- The guest with this email, if they have booked at the resort.
create function public.find_resort_guest(p_property uuid, p_email text)
returns table (user_id uuid, email text, full_name text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'find_resort_guest is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.create_coupon(
  p_property    uuid,
  p_code        text,
  p_kind        public.coupon_kind,
  p_value       numeric,
  p_min_amount  numeric default null,
  p_valid_from  date default null,
  p_valid_until date default null,
  p_usage_limit int default null,
  p_customer    uuid default null
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'create_coupon is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.update_coupon(
  p_coupon      uuid,
  p_code        text,
  p_kind        public.coupon_kind,
  p_value       numeric,
  p_min_amount  numeric default null,
  p_valid_from  date default null,
  p_valid_until date default null,
  p_usage_limit int default null,
  p_customer    uuid default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'update_coupon is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.set_coupon_active(p_coupon uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'set_coupon_active is not implemented yet' using errcode = '0A000';
end;
$$;

revoke execute on function public.list_coupons(uuid) from public, anon;
revoke execute on function public.find_resort_guest(uuid, text) from public, anon;
revoke execute on function public.create_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid) from public, anon;
revoke execute on function public.update_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid) from public, anon;
revoke execute on function public.set_coupon_active(uuid, boolean) from public, anon;
grant execute on function public.list_coupons(uuid) to authenticated;
grant execute on function public.find_resort_guest(uuid, text) to authenticated;
grant execute on function public.create_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid) to authenticated;
grant execute on function public.update_coupon(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid) to authenticated;
grant execute on function public.set_coupon_active(uuid, boolean) to authenticated;
