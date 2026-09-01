-- Owner-editable business settings that previously had no schema at all:
-- tax rate, GST number, per-stay night limits, and which payment methods /
-- gateway name are shown to a customer. See
-- docs/superpowers/specs/2026-08-31-owner-super-admin-flow-design.md.
--
-- Every new column is either zero/empty-defaulted (`tax_pct`,
-- `payment_display_methods`) or nullable with no restriction implied by
-- NULL (`gstin`, `min_nights`, `max_nights`, `gateway_display_name`) --
-- exactly the same safe-default precedent `0014_advance_policy.sql` set for
-- `advance_pct`. An existing property that never visits the new Settings
-- screens keeps today's pricing and booking behaviour byte-for-byte.
alter table public.properties
  add column tax_pct numeric(5,2) not null default 0
    check (tax_pct >= 0 and tax_pct <= 100),
  add column gstin text,
  add column min_nights int check (min_nights is null or min_nights > 0),
  add column max_nights int check (max_nights is null or max_nights > 0),
  add column payment_display_methods text[] not null default '{}',
  add column gateway_display_name text,
  add constraint properties_night_range check (
    min_nights is null or max_nights is null or max_nights >= min_nights
  );

-- Tax is added on top of the coupon-discounted subtotal, as its own
-- additive line -- never folded into `subtotal`/`cleaning_fee`, so an
-- existing client that only ever read `total` keeps working, and one that
-- wants to show a tax line now has `tax_pct`/`tax_amount` to show. Night
-- limits apply only to nightly bookings (a slot booking has no "nights" to
-- count) and are skipped whenever a property has not set them, so a
-- property with `min_nights`/`max_nights` both NULL is validated exactly
-- as before this migration.
create or replace function public.get_quote(
  p_unit_id      uuid,
  p_period       tstzrange,
  p_guests       int,
  p_slot_type_id uuid default null,
  p_coupon_code  text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_unit        public.units;
  v_tz          text;
  v_tax_pct     numeric(5,2);
  v_min_nights  int;
  v_max_nights  int;
  v_rule        public.rate_rules;
  v_date        date;
  v_end_date    date;
  v_nights      int;
  v_lines       jsonb := '[]'::jsonb;
  v_subtotal    numeric(12,2) := 0;
  v_cleaning    numeric(12,2) := 0;
  v_extra       int;
  v_extra_amt   numeric(12,2);
  v_coupon      public.coupons;
  v_discount    numeric(12,2) := 0;
  v_taxable     numeric(12,2);
  v_tax_amount  numeric(12,2);
begin
  select * into v_unit from public.units where id = p_unit_id and is_active;
  if not found then
    raise exception 'unit not found or inactive' using errcode = 'P0002';
  end if;

  select p.timezone, p.tax_pct, p.min_nights, p.max_nights
  into v_tz, v_tax_pct, v_min_nights, v_max_nights
  from public.properties p where p.id = v_unit.property_id;

  if p_guests is null or p_guests < 1 or p_guests > v_unit.capacity_max then
    raise exception 'guest count out of range (max %)', v_unit.capacity_max
      using errcode = 'P0003';
  end if;

  v_extra := greatest(p_guests - v_unit.capacity_base, 0);

  -- One line per calendar night (nightly) or per slot day (slot bookings).
  v_date     := (lower(p_period) at time zone v_tz)::date;
  v_end_date := (upper(p_period) at time zone v_tz)::date;
  v_nights   := v_end_date - v_date;
  if p_slot_type_id is not null then
    v_end_date := v_date + 1;   -- a slot occupies exactly one dated line
  end if;

  if p_slot_type_id is null and v_nights > 0 then
    if v_min_nights is not null and v_nights < v_min_nights then
      raise exception 'this unit requires a minimum stay of % nights', v_min_nights
        using errcode = 'P0015';
    end if;
    if v_max_nights is not null and v_nights > v_max_nights then
      raise exception 'this unit allows a maximum stay of % nights', v_max_nights
        using errcode = 'P0015';
    end if;
  end if;

  while v_date < v_end_date loop
    v_rule := public.resolve_rate_rule(p_unit_id, v_date, p_slot_type_id);
    if v_rule.id is null then
      raise exception 'no rate rule for unit % on %', p_unit_id, v_date
        using errcode = 'P0004';
    end if;

    v_extra_amt := v_extra * v_rule.extra_guest_price;
    v_subtotal  := v_subtotal + v_rule.price + v_extra_amt;
    v_cleaning  := greatest(v_cleaning, v_rule.cleaning_fee);

    v_lines := v_lines || jsonb_build_object(
      'date',               to_char(v_date, 'YYYY-MM-DD'),
      'label',              coalesce(v_rule.label, initcap(v_rule.kind::text) || ' rate'),
      'amount',             v_rule.price,
      'rate_rule_id',       v_rule.id,
      'extra_guests',       v_extra,
      'extra_guest_amount', v_extra_amt
    );

    v_date := v_date + 1;
  end loop;

  if jsonb_array_length(v_lines) = 0 then
    raise exception 'period covers no nights' using errcode = 'P0005';
  end if;

  if p_coupon_code is not null then
    v_coupon := public.resolve_coupon(p_coupon_code, auth.uid(),
                                       v_subtotal + v_cleaning);
    v_discount := case v_coupon.kind
      when 'percent' then round((v_subtotal + v_cleaning) * v_coupon.value / 100, 2)
      when 'fixed'   then round(v_coupon.value, 2)
    end;
    -- Never let a coupon drive the total below zero, regardless of how
    -- `value` is configured.
    v_discount := least(v_discount, v_subtotal + v_cleaning);
  end if;

  v_taxable    := v_subtotal + v_cleaning - v_discount;
  v_tax_amount := round(v_taxable * coalesce(v_tax_pct, 0) / 100, 2);

  return jsonb_build_object(
    'unit_id',      p_unit_id,
    'currency',     'INR',
    'guests',       p_guests,
    'lines',        v_lines,
    'subtotal',     v_subtotal,
    'cleaning_fee', v_cleaning,
    'coupon',       case when v_coupon.id is not null
                      then jsonb_build_object(
                        'code',     v_coupon.code,
                        'kind',     v_coupon.kind,
                        'value',    v_coupon.value,
                        'discount', v_discount)
                      else null end,
    'tax_pct',      coalesce(v_tax_pct, 0),
    'tax_amount',   v_tax_amount,
    'total',        v_taxable + v_tax_amount
  );
end;
$$;

-- `properties_write` (0003_properties_units.sql) already covers every
-- column on this table, including the six added here -- no new RLS policy
-- needed for the columns themselves. Read access is likewise already
-- covered by `properties_read`.
