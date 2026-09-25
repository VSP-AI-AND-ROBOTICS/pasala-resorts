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
-- Internal helpers, run with invoker rights. Only the security definer
-- functions below call them, so they run as those functions' owner.
-- Nobody else can execute them.

-- A guest the resort can restrict a coupon to: someone with a real
-- booking there (confirmed, in house or checked out). Holds, pending
-- payments and cancelled bookings do not count.
create function public.is_resort_guest(p_property uuid, p_user uuid)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.reservations r
     where r.property_id = p_property
       and r.customer_id = p_user
       and r.kind = 'booking'
       and r.status in ('confirmed', 'checked_in', 'checked_out'));
$$;

-- Checks what create_coupon/update_coupon were given and returns the code
-- normalised (trimmed, upper-case). Raises P0033 with one reason word.
-- p_customer is checked only when given: update_coupon passes null when
-- the coupon keeps the guest it already had.
create function public.coupon_check_input(
  p_property    uuid,
  p_code        text,
  p_kind        public.coupon_kind,
  p_value       numeric,
  p_min_amount  numeric,
  p_valid_from  date,
  p_valid_until date,
  p_usage_limit int,
  p_customer    uuid
) returns text
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_code text := upper(btrim(coalesce(p_code, '')));
begin
  if v_code !~ '^[A-Z0-9][A-Z0-9_-]{2,23}$' then
    raise exception using errcode = 'P0033', message = 'code_invalid';
  end if;
  if p_kind is null then
    raise exception using errcode = 'P0033', message = 'kind_required';
  end if;
  -- numeric(12,2) holds values below 10^10; anything larger would fail
  -- the insert with a raw overflow instead of a readable reason.
  if p_value is null or p_value <= 0 or p_value >= 10000000000
     or (p_kind = 'percent' and p_value > 100) then
    raise exception using errcode = 'P0033', message = 'value_invalid';
  end if;
  if p_min_amount is not null and (p_min_amount < 0 or p_min_amount >= 10000000000) then
    raise exception using errcode = 'P0033', message = 'min_amount_invalid';
  end if;
  if p_valid_from is not null and p_valid_until is not null
     and p_valid_until < p_valid_from then
    raise exception using errcode = 'P0033', message = 'dates_invalid';
  end if;
  if p_usage_limit is not null and p_usage_limit < 1 then
    raise exception using errcode = 'P0033', message = 'usage_limit_invalid';
  end if;
  if p_customer is not null
     and not public.is_resort_guest(p_property, p_customer) then
    raise exception using errcode = 'P0033', message = 'guest_not_eligible';
  end if;
  return v_code;
end;
$$;

revoke execute on function public.is_resort_guest(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.coupon_check_input(uuid, text, public.coupon_kind, numeric, numeric, date, date, integer, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Coupon functions. The signatures are the contract the app is built
-- against; Tasks 2 and 3 of the plan replace the stub bodies.

-- Every coupon of the resort, for the Coupons screen. Owner/admin of the
-- resort (reads are allowed while it is suspended). Dates come back as
-- calendar days in the resort's time zone. status follows the order
-- resolve_coupon checks at booking time: inactive, expired, not yet valid
-- (scheduled), used up, else active. Active coupons first, newest first.
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
#variable_conflict use_column
declare
  v_tz text;
begin
  perform public.assert_resort_role(p_property, false, 'owner', 'admin');

  select p.timezone into v_tz from public.properties p where p.id = p_property;

  return query
    select c.id,
           c.code,
           c.kind,
           c.value,
           c.min_booking_value,
           (c.valid_from at time zone v_tz)::date,
           (c.valid_to at time zone v_tz)::date,
           c.max_redemptions,
           c.redeemed_count,
           c.customer_id,
           u.email::text,
           pr.full_name,
           c.is_active,
           case
             when not c.is_active then 'inactive'
             when c.valid_to is not null and now() > c.valid_to then 'expired'
             when c.valid_from is not null and now() < c.valid_from then 'scheduled'
             when c.max_redemptions is not null
                  and c.redeemed_count >= c.max_redemptions then 'used_up'
             else 'active'
           end,
           c.created_at
      from public.coupons c
      left join auth.users u on u.id = c.customer_id
      left join public.profiles pr on pr.id = c.customer_id
     where c.property_id = p_property
     order by c.is_active desc, c.created_at desc, c.code;
end;
$$;

-- The account with this email (case-insensitive, trimmed), if it has a
-- real booking at the resort (is_resort_guest). Zero or one row. It never
-- reveals an account that has not booked at this resort.
create function public.find_resort_guest(p_property uuid, p_email text)
returns table (user_id uuid, email text, full_name text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  perform public.assert_resort_role(p_property, false, 'owner', 'admin');

  return query
    select u.id, u.email::text, pr.full_name
      from auth.users u
      left join public.profiles pr on pr.id = u.id
     where lower(u.email) = lower(btrim(p_email))
       and public.is_resort_guest(p_property, u.id);
end;
$$;

-- A new coupon at p_property. Owner/admin there, and the resort must be
-- active (P0022 when suspended). Valid from/until are whole days in the
-- resort's time zone: 00:00 on the first day to the last microsecond of
-- the last.
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
declare
  v_code text;
  v_tz   text;
  v_row  public.coupons;
begin
  perform public.assert_resort_role(p_property, true, 'owner', 'admin');

  v_code := public.coupon_check_input(p_property, p_code, p_kind, p_value,
              p_min_amount, p_valid_from, p_valid_until, p_usage_limit, p_customer);

  select p.timezone into v_tz from public.properties p where p.id = p_property;

  begin
    insert into public.coupons
      (property_id, code, kind, value, min_booking_value, valid_from, valid_to,
       max_redemptions, customer_id)
    values
      (p_property, v_code, p_kind, p_value, p_min_amount,
       p_valid_from::timestamp at time zone v_tz,
       (p_valid_until + 1)::timestamp at time zone v_tz - interval '1 microsecond',
       p_usage_limit, p_customer)
    returning * into v_row;
  exception when unique_violation then
    raise exception using errcode = 'P0033', message = 'code_taken';
  end;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'coupon', v_row.id, 'create', null, to_jsonb(v_row), p_property);

  return v_row.id;
end;
$$;

-- Replaces every field of one coupon (a null clears that optional field).
-- The resort comes from the coupon row. The usage-limit floor sits in the
-- UPDATE's WHERE: create_hold increments redeemed_count under the same
-- row lock, so a booking cannot slip between the check and the write.
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
declare
  v_old  public.coupons;
  v_new  public.coupons;
  v_code text;
  v_tz   text;
begin
  select * into v_old from public.coupons where id = p_coupon;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;
  perform public.assert_resort_role(v_old.property_id, true, 'owner', 'admin');

  -- A guest the coupon already has is not checked again: their booking
  -- may have been cancelled since, and that must not block other edits.
  v_code := public.coupon_check_input(v_old.property_id, p_code, p_kind, p_value,
              p_min_amount, p_valid_from, p_valid_until, p_usage_limit,
              case when p_customer is distinct from v_old.customer_id
                   then p_customer end);

  select p.timezone into v_tz from public.properties p where p.id = v_old.property_id;

  begin
    update public.coupons
       set code              = v_code,
           kind              = p_kind,
           value             = p_value,
           min_booking_value = p_min_amount,
           valid_from        = p_valid_from::timestamp at time zone v_tz,
           valid_to          = (p_valid_until + 1)::timestamp at time zone v_tz
                                 - interval '1 microsecond',
           max_redemptions   = p_usage_limit,
           customer_id       = p_customer
     where id = p_coupon
       and (p_usage_limit is null or redeemed_count <= p_usage_limit)
    returning * into v_new;
  exception when unique_violation then
    raise exception using errcode = 'P0033', message = 'code_taken';
  end;

  if v_new.id is null then
    raise exception using errcode = 'P0033', message = 'usage_limit_below_used';
  end if;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'coupon', p_coupon, 'update', to_jsonb(v_old), to_jsonb(v_new),
          v_old.property_id);
end;
$$;

-- Deactivates or reactivates one coupon. There is no delete: removing a
-- coupon would cascade to coupon_redemptions and erase history.
create function public.set_coupon_active(p_coupon uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old public.coupons;
  v_new public.coupons;
begin
  select * into v_old from public.coupons where id = p_coupon;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;
  perform public.assert_resort_role(v_old.property_id, true, 'owner', 'admin');

  if p_active is null then
    raise exception 'active must be true or false' using errcode = 'P0005';
  end if;

  update public.coupons set is_active = p_active
   where id = p_coupon
  returning * into v_new;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'coupon', p_coupon,
          case when p_active then 'activate' else 'deactivate' end,
          to_jsonb(v_old), to_jsonb(v_new), v_old.property_id);
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
