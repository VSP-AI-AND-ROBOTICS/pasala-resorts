-- Final-review minors (items 4-7):
--   4. search_resorts also matches properties.city (added in 0059), as
--      P11 spec decision 10 planned once such a column existed.
--   5. resolve_coupon and create_hold match the code as upper(btrim(..)):
--      0051 stores codes upper-cased, and installed app builds may still
--      send lower case.
--   6. apply_for_listing retries on a slug unique violation, so two
--      same-name applications at once both succeed instead of the loser
--      getting a raw 23505.
--   7. payment_webhook_events keeps only the ids and fields needed for
--      idempotency and audit (no email, phone, VPA, card or notes); the
--      rows already stored are scrubbed, and a daily pg_cron job prunes
--      processed rows older than 90 days.

-- ---------------------------------------------------------------------
-- 4. search_resorts: from 0060, with `city` added to the word match.
create or replace function public.search_resorts(
  p_query     text default null,
  p_lat       double precision default null,
  p_lng       double precision default null,
  p_sort      text default 'recommended',
  p_amenities text[] default null
) returns table (
  id             uuid,
  name           text,
  slug           text,
  description    text,
  address        text,
  images         text[],
  amenities      text[],
  check_in_time  time,
  check_out_time time,
  is_active      boolean,
  lat            double precision,
  lng            double precision,
  distance_km    numeric,
  min_price      numeric,
  avg_rating     numeric,
  review_count   int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_sort     text := coalesce(nullif(btrim(p_sort), ''), 'recommended');
  v_patterns text[];
  v_wanted   text[];
begin
  if v_sort not in ('recommended', 'distance', 'price', 'rating')
     or (p_lat is null) <> (p_lng is null)
     or p_lat not between -90 and 90
     or p_lng not between -180 and 180
     or length(p_query) > 100 then
    raise exception using errcode = 'P0041', message = 'invalid_search';
  end if;

  -- One ILIKE pattern per word. The guest's own \, % and _ are escaped so
  -- they match literally.
  select coalesce(array_agg('%' || replace(replace(replace(w, '\', '\\'),
                                                   '%', '\%'),
                                           '_', '\_') || '%'),
                  '{}')
    into v_patterns
    from regexp_split_to_table(btrim(coalesce(p_query, '')), '\s+') as w
   where w <> '';

  -- The amenities the guest asked for, lower-cased, with blanks dropped.
  select coalesce(array_agg(distinct lower(btrim(a))), '{}')
    into v_wanted
    from unnest(coalesce(p_amenities, '{}'::text[])) as a
   where btrim(a) <> '';

  return query
  with matched as (
    select p.*
      from public.properties p
     where p.status = 'active'
       and p.is_active
       -- every word appears in some field
       and not exists (
             select 1 from unnest(v_patterns) as pat
              where not (p.name ilike pat
                         or coalesce(p.city, '') ilike pat
                         or coalesce(p.address, '') ilike pat
                         or coalesce(p.description, '') ilike pat
                         or array_to_string(p.amenities, ' ') ilike pat))
       -- every requested amenity is present
       and not exists (
             select 1 from unnest(v_wanted) as want
              where not exists (select 1 from unnest(p.amenities) as have
                                 where lower(btrim(have)) = want))
  ),
  prices as (
    -- Lowest nightly price: nightly rules (no slot type) of active units
    -- that take nightly bookings, not yet expired in the resort's own
    -- timezone.
    select u.property_id, min(r.price) as min_price
      from matched m
      join public.units u on u.property_id = m.id
      join public.rate_rules r on r.unit_id = u.id
     where u.is_active
       and u.booking_mode in ('nightly', 'both')
       and r.slot_type_id is null
       and (r.valid_to is null
            or r.valid_to >= (now() at time zone m.timezone)::date)
     group by u.property_id
  ),
  ratings as (
    select rv.property_id,
           count(*)::int                    as review_count,
           sum(rv.overall_rating)::numeric  as rating_sum
      from matched m
      join public.reviews rv on rv.property_id = m.id
     group by rv.property_id
  ),
  cards as (
    select m.id, m.name, m.slug, m.description, m.address, m.images,
           m.amenities, m.check_in_time, m.check_out_time, m.is_active,
           m.lat, m.lng,
           -- Haversine, R = 6371 km, rounded to 0.1 km.
           case when p_lat is not null and m.lat is not null then
             round((2 * 6371 * asin(least(1.0::double precision, sqrt(
                 power(sin(radians(m.lat - p_lat) / 2), 2)
                 + cos(radians(p_lat)) * cos(radians(m.lat))
                   * power(sin(radians(m.lng - p_lng) / 2), 2)))))::numeric, 1)
           end                                        as distance_km,
           pr.min_price::numeric                      as min_price,
           round(rt.rating_sum / rt.review_count, 1)  as avg_rating,
           coalesce(rt.review_count, 0)               as review_count,
           -- Recommended: the average shrunk toward 4 by three phantom
           -- reviews, so one 5-star review does not outrank many 4.5s.
           (coalesce(rt.rating_sum, 0) + 12)
             / (coalesce(rt.review_count, 0) + 3)     as score,
           cardinality(m.images) > 0                  as has_photo
      from matched m
      left join prices  pr on pr.property_id = m.id
      left join ratings rt on rt.property_id = m.id
  )
  select c.id, c.name, c.slug, c.description, c.address, c.images,
         c.amenities, c.check_in_time, c.check_out_time, c.is_active,
         c.lat, c.lng, c.distance_km, c.min_price, c.avg_rating,
         c.review_count
    from cards c
   order by
     case when v_sort = 'distance' and p_lat is not null
          then c.distance_km end asc nulls last,
     case when v_sort = 'price'  then c.min_price  end asc nulls last,
     case when v_sort = 'rating' then c.avg_rating end desc nulls last,
     case when v_sort = 'rating' then c.review_count end desc,
     -- Recommended, and distance requested without a position.
     case when v_sort = 'recommended' or (v_sort = 'distance' and p_lat is null)
          then c.score end desc,
     case when v_sort = 'recommended' or (v_sort = 'distance' and p_lat is null)
          then c.has_photo end desc,
     c.name, c.id;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. resolve_coupon: from 0045, matching upper(btrim(p_code)).
create or replace function public.resolve_coupon(
  p_property_id uuid,
  p_code        text,
  p_uid         uuid,
  p_amount      numeric
) returns public.coupons
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_coupon public.coupons;
begin
  select * into v_coupon
  from public.coupons c
  -- 0051 stores codes upper-cased and trimmed; normalise what was sent
  -- the same way, so an older app build's lower-case code still matches.
  where c.code = upper(btrim(p_code))
    and c.property_id = p_property_id
    and c.is_active
    -- A coupon restricted to another customer must look exactly like it
    -- doesn't exist -- P0010, not a different code.
    and (c.customer_id is null or c.customer_id = p_uid);

  if not found then
    raise exception 'coupon not found or inactive' using errcode = 'P0010';
  end if;

  if (v_coupon.valid_from is not null and now() < v_coupon.valid_from)
     or (v_coupon.valid_to is not null and now() > v_coupon.valid_to) then
    raise exception 'coupon % has expired', p_code using errcode = 'P0011';
  end if;

  if v_coupon.max_redemptions is not null
     and v_coupon.redeemed_count >= v_coupon.max_redemptions then
    raise exception 'coupon % has reached its usage limit', p_code
      using errcode = 'P0012';
  end if;

  if v_coupon.min_booking_value is not null
     and p_amount < v_coupon.min_booking_value then
    raise exception
      'this booking is below the minimum of % for coupon %',
      v_coupon.min_booking_value, p_code
      using errcode = 'P0013';
  end if;

  return v_coupon;
end;
$$;

-- Internal helper for get_quote/create_hold only (see 0012, 0045).
revoke execute on function public.resolve_coupon(uuid, text, uuid, numeric)
  from public;
revoke execute on function public.resolve_coupon(uuid, text, uuid, numeric)
  from anon, authenticated;

-- create_hold: from 0045, with the redemption's update matching the same
-- normalised code as resolve_coupon (otherwise a lower-case code would
-- quote fine and then fail here with P0012).
create or replace function public.create_hold(
  p_unit_id        uuid,
  p_from           date,
  p_to             date,
  p_guests         int,
  p_slot_type_id   uuid default null,
  p_expected_total numeric default null,
  p_coupon_code    text default null,
  p_occasion       text default null
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid       uuid := auth.uid();
  v_mode      public.booking_mode;
  v_property  uuid;
  v_period    tstzrange;
  v_quote     jsonb;
  v_row       public.reservations;
  v_coupon_id uuid;
  v_discount  numeric(12,2);
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  -- If the unit doesn't exist `v_mode`/`v_property` stay NULL, so neither
  -- check below fires and `build_period`'s own "unit not found" raise does.
  select booking_mode, property_id into v_mode, v_property
  from public.units where id = p_unit_id;

  if v_property is not null and not exists (
    select 1 from public.properties where id = v_property and status = 'active'
  ) then
    raise exception using errcode = 'P0022', message = 'resort_suspended';
  end if;

  -- I3: `booking_mode` enforced in SQL, not just in the client (see 0007).
  if v_mode = 'nightly' and p_slot_type_id is not null then
    raise exception 'this unit does not support slot bookings'
      using errcode = 'P0003';
  end if;
  if v_mode = 'slot' and p_slot_type_id is null then
    raise exception 'this unit requires a slot type' using errcode = 'P0003';
  end if;

  v_period := public.build_period(p_unit_id, p_from, p_to, p_slot_type_id);
  v_quote  := public.get_quote(p_unit_id, v_period, p_guests, p_slot_type_id,
                                p_coupon_code);

  -- The client displayed a total; refuse to hold at a price it never saw.
  if p_expected_total is not null
     and (v_quote ->> 'total')::numeric <> p_expected_total then
    raise exception 'price changed to %', (v_quote ->> 'total')
      using errcode = 'P0007';
  end if;

  insert into public.reservations
    (unit_id, slot_type_id, period, kind, status, customer_id, guests,
     quote, hold_expires_at, created_by, occasion)
  values
    (p_unit_id, p_slot_type_id, v_period, 'booking', 'hold', v_uid, p_guests,
     v_quote, now() + interval '15 minutes', v_uid, p_occasion)
  returning * into v_row;

  if p_coupon_code is not null then
    -- Race-safe redemption: the max_redemptions check and the increment
    -- are the SAME statement, serialized by the coupon row's lock (see
    -- 0012 for the full reasoning).
    update public.coupons
       set redeemed_count = redeemed_count + 1
     where code = upper(btrim(p_coupon_code))
       and property_id = v_property
       and is_active
       and (max_redemptions is null or redeemed_count < max_redemptions)
    returning id into v_coupon_id;

    if v_coupon_id is null then
      raise exception 'coupon % has reached its usage limit', p_coupon_code
        using errcode = 'P0012';
    end if;

    v_discount := coalesce(((v_quote -> 'coupon') ->> 'discount')::numeric, 0);

    insert into public.coupon_redemptions
      (coupon_id, reservation_id, customer_id, amount)
    values (v_coupon_id, v_row.id, v_uid, v_discount);
  end if;

  return v_row;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. apply_for_listing: from 0059. resort_slug_for checks and the insert
-- claims without a lock, so a same-name application committing in between
-- makes the insert fail on properties_slug_key. Retry the insert (a fresh
-- statement, so resort_slug_for sees the committed row) a few times;
-- any other unique violation is re-raised.
create or replace function public.apply_for_listing(
  p_name          text,
  p_city          text,
  p_address       text,
  p_contact_phone text,
  p_description   text,
  p_tier          public.subscription_tier default 'starter'
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid     uuid := auth.uid();
  v_name    text := btrim(coalesce(p_name, ''));
  v_city    text := btrim(coalesce(p_city, ''));
  v_addr    text := btrim(coalesce(p_address, ''));
  v_phone   text := regexp_replace(btrim(coalesce(p_contact_phone, '')), '[ -]', '', 'g');
  v_desc    text := btrim(coalesce(p_description, ''));
  v_id      uuid;
  v_sub     public.resort_subscriptions;
  v_attempt int := 0;
  v_constr  text;
begin
  if v_uid is null or public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if length(v_name) not between 2 and 80 then
    raise exception 'Enter the resort name (2 to 80 characters).' using errcode = 'P0005';
  end if;
  if length(v_city) not between 2 and 60 then
    raise exception 'Enter the city (2 to 60 characters).' using errcode = 'P0005';
  end if;
  if length(v_addr) not between 5 and 300 then
    raise exception 'Enter the full address (5 to 300 characters).' using errcode = 'P0005';
  end if;
  if v_phone !~ '^\+?[0-9]{10,13}$' then
    raise exception 'Enter a contact phone number, e.g. +91 98765 43210.' using errcode = 'P0005';
  end if;
  if length(v_desc) not between 20 and 500 then
    raise exception 'Describe the resort in 20 to 500 characters.' using errcode = 'P0005';
  end if;
  if p_tier is null then
    raise exception 'Choose a plan.' using errcode = 'P0005';
  end if;

  -- Serialise this user's applications, so two taps at once give P0040
  -- here rather than a unique violation from the partial index.
  perform pg_advisory_xact_lock(hashtext('listing:' || v_uid::text));
  if exists (select 1 from public.listing_applications
              where applicant_id = v_uid and decision is null) then
    raise exception 'You already have a resort waiting for review.' using errcode = 'P0040';
  end if;

  loop
    begin
      insert into public.properties (name, slug, status, city, address, contact_phone, description)
      values (v_name, public.resort_slug_for(v_name), 'pending', v_city, v_addr, v_phone, v_desc)
      returning id into v_id;
      exit;
    exception when unique_violation then
      get stacked diagnostics v_constr = constraint_name;
      v_attempt := v_attempt + 1;
      if v_constr is distinct from 'properties_slug_key' or v_attempt >= 5 then
        raise;
      end if;
    end;
  end loop;

  insert into public.resort_members (property_id, user_id, role)
  values (v_id, v_uid, 'owner');

  insert into public.resort_subscriptions (property_id, tier, status, trial_ends_on)
  values (v_id, p_tier, 'trial', (now() at time zone 'Asia/Kolkata')::date + 30)
  returning * into v_sub;

  insert into public.listing_applications (property_id, applicant_id, tier)
  values (v_id, v_uid, p_tier);

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values
    (v_uid, 'listing', v_id, 'listing:apply', null,
     jsonb_build_object('name', v_name, 'city', v_city, 'tier', p_tier), v_id),
    (v_uid, 'subscription', v_id, 'subscription:create', null, to_jsonb(v_sub), v_id);

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. The webhook ledger.
--
-- payment_webhook_redact: the subset of a Razorpay event worth keeping --
-- the event's own identity, and for each payment / refund / order entity
-- its ids, amounts, status and error codes. Everything else (email,
-- contact, VPA, card, bank, wallet, notes, acquirer data, description)
-- is dropped. A plain function; payment_webhook_begin applies it.
create function public.payment_webhook_redact(p_payload jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  v_out    jsonb;
  v_inner  jsonb := '{}'::jsonb;
  v_kind   text;
  v_keys   text[];
  v_entity jsonb;
begin
  if jsonb_typeof(p_payload) is distinct from 'object' then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) into v_out
    from jsonb_each(p_payload)
   where key in ('entity', 'account_id', 'event', 'contains', 'created_at');

  foreach v_kind in array array['payment', 'refund', 'order'] loop
    v_entity := p_payload #> array['payload', v_kind, 'entity'];
    continue when jsonb_typeof(v_entity) is distinct from 'object';

    v_keys := case v_kind
      when 'payment' then array['id', 'entity', 'order_id', 'invoice_id',
                                'amount', 'currency', 'status', 'method',
                                'captured', 'amount_refunded', 'refund_status',
                                'error_code', 'error_reason', 'error_source',
                                'error_step', 'error_description', 'created_at']
      when 'refund'  then array['id', 'entity', 'payment_id', 'amount',
                                'currency', 'status', 'receipt',
                                'speed_processed', 'created_at']
      else                array['id', 'entity', 'amount', 'amount_paid',
                                'amount_due', 'currency', 'receipt', 'status',
                                'attempts', 'created_at']
    end;

    select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) into v_entity
      from jsonb_each(v_entity)
     where key = any(v_keys);

    v_inner := v_inner || jsonb_build_object(v_kind, jsonb_build_object('entity', v_entity));
  end loop;

  if v_inner <> '{}'::jsonb then
    v_out := v_out || jsonb_build_object('payload', v_inner);
  end if;
  return v_out;
end;
$$;
revoke execute on function public.payment_webhook_redact(jsonb) from public, anon, authenticated;

-- payment_webhook_begin: from 0055, storing the redacted payload.
create or replace function public.payment_webhook_begin(
  p_event_id text,
  p_event    text,
  p_payload  jsonb
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_processed timestamptz;
begin
  if p_event_id is null or btrim(p_event_id) = '' then
    raise exception 'a webhook event id is required' using errcode = 'P0009';
  end if;

  insert into public.payment_webhook_events (event_id, event, payload)
  values (btrim(p_event_id), coalesce(p_event, 'unknown'),
          public.payment_webhook_redact(p_payload))
  on conflict (event_id) do nothing;

  select processed_at into v_processed
    from public.payment_webhook_events
   where event_id = btrim(p_event_id);

  -- Unfinished (a crash mid-way) is processed again; settling is idempotent.
  return v_processed is null;
end;
$$;
revoke execute on function public.payment_webhook_begin(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.payment_webhook_begin(text, text, jsonb) to service_role;

-- Scrub what is already stored.
update public.payment_webhook_events
   set payload = public.payment_webhook_redact(payload)
 where payload is distinct from public.payment_webhook_redact(payload);

-- payment_webhook_prune: deletes processed events received more than 90
-- days ago. Razorpay retries an event for about 24 hours, so an event
-- that old will not be seen again and its row is no longer needed for
-- idempotency. Unfinished rows are kept. Returns the number deleted.
create function public.payment_webhook_prune()
returns int
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_n int;
begin
  delete from public.payment_webhook_events
   where processed_at is not null
     and received_at < now() - interval '90 days';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke execute on function public.payment_webhook_prune() from public, anon, authenticated, service_role;

-- Daily at 03:17 UTC.
select cron.schedule(
  'payment-webhook-prune', '17 3 * * *',
  $$select public.payment_webhook_prune()$$);
