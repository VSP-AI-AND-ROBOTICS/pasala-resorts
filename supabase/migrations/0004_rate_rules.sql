create table public.rate_rules (
  id                uuid primary key default gen_random_uuid(),
  unit_id           uuid not null references public.units(id) on delete cascade,
  kind              public.rate_kind not null,
  slot_type_id      uuid references public.slot_types(id) on delete cascade,
  label             text,
  valid_from        date,
  valid_to          date,
  weekdays          int[],
  price             numeric(12,2) not null check (price >= 0),
  extra_guest_price numeric(12,2) not null default 0 check (extra_guest_price >= 0),
  cleaning_fee      numeric(12,2) not null default 0 check (cleaning_fee >= 0),
  priority          int not null default 0,
  created_at        timestamptz not null default now(),
  constraint rate_rules_override_dates check (
    kind <> 'override' or (valid_from is not null and valid_to is not null)
  ),
  constraint rate_rules_date_order check (
    valid_from is null or valid_to is null or valid_to >= valid_from
  )
);

create index rate_rules_unit_idx on public.rate_rules(unit_id, priority desc);

grant select on public.rate_rules to anon, authenticated;
grant insert, update, delete on public.rate_rules to authenticated;

alter table public.rate_rules enable row level security;

create policy rate_rules_read on public.rate_rules
  for select to anon, authenticated using (true);

create policy rate_rules_write on public.rate_rules
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Resolve the single winning rule for one date on one unit.
-- Highest priority wins. Ties do NOT break on created_at alone: created_at
-- defaults to now(), which is frozen for the whole transaction, so any rules
-- inserted together (a seed script, an admin bulk-insert) share an identical
-- created_at and would otherwise tie arbitrarily. Instead we break ties by
-- specificity -- a rule that targets this exact slot type, then one that
-- targets specific weekdays, then one that is date-bounded, outranks a more
-- generic rule at the same priority -- before falling back to created_at and
-- finally id, so the ordering is always total and never arbitrary.
create function public.resolve_rate_rule(
  p_unit_id      uuid,
  p_date         date,
  p_slot_type_id uuid
) returns public.rate_rules
language sql
stable
set search_path = public, pg_temp
as $$
  select r.*
  from public.rate_rules r
  where r.unit_id = p_unit_id
    and (r.slot_type_id is null or r.slot_type_id = p_slot_type_id)
    and (r.valid_from is null or p_date >= r.valid_from)
    and (r.valid_to   is null or p_date <= r.valid_to)
    and (r.weekdays is null or extract(isodow from p_date)::int = any(r.weekdays))
  order by
    r.priority desc,
    (r.slot_type_id is not null) desc,
    (r.weekdays    is not null) desc,
    (r.valid_from  is not null) desc,
    r.created_at desc,
    r.id desc
  limit 1;
$$;

create function public.get_quote(
  p_unit_id      uuid,
  p_period       tstzrange,
  p_guests       int,
  p_slot_type_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_unit      public.units;
  v_tz        text;
  v_rule      public.rate_rules;
  v_date      date;
  v_end_date  date;
  v_lines     jsonb := '[]'::jsonb;
  v_subtotal  numeric(12,2) := 0;
  v_cleaning  numeric(12,2) := 0;
  v_extra     int;
  v_extra_amt numeric(12,2);
begin
  select * into v_unit from public.units where id = p_unit_id and is_active;
  if not found then
    raise exception 'unit not found or inactive' using errcode = 'P0002';
  end if;

  select p.timezone into v_tz
  from public.properties p where p.id = v_unit.property_id;

  if p_guests is null or p_guests < 1 or p_guests > v_unit.capacity_max then
    raise exception 'guest count out of range (max %)', v_unit.capacity_max
      using errcode = 'P0003';
  end if;

  v_extra := greatest(p_guests - v_unit.capacity_base, 0);

  -- One line per calendar night (nightly) or per slot day (slot bookings).
  v_date     := (lower(p_period) at time zone v_tz)::date;
  v_end_date := (upper(p_period) at time zone v_tz)::date;
  if p_slot_type_id is not null then
    v_end_date := v_date + 1;   -- a slot occupies exactly one dated line
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

  return jsonb_build_object(
    'unit_id',      p_unit_id,
    'currency',     'INR',
    'guests',       p_guests,
    'lines',        v_lines,
    'subtotal',     v_subtotal,
    'cleaning_fee', v_cleaning,
    'total',        v_subtotal + v_cleaning
  );
end;
$$;
