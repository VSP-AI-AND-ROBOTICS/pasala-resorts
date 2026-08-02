-- Reporting is read-only and staff-gated. Every figure is computed here so
-- that no client ever performs arithmetic on money.

create function public.assert_staff()
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_staff_or_above() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;
end;
$$;

create function public.report_revenue(
  p_from        date,
  p_to          date,
  p_property_id uuid default null
) returns table (
  day         date,
  property_id uuid,
  bookings    int,
  gross       numeric,
  refunded    numeric,
  net         numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_staff();

  return query
  select
    (lower(r.period) at time zone p.timezone)::date as day,
    p.id,
    count(*)::int,
    coalesce(sum((r.quote ->> 'total')::numeric)
             filter (where r.status = 'confirmed'), 0),
    coalesce(sum((r.quote ->> 'total')::numeric)
             filter (where r.status = 'cancelled'), 0),
    coalesce(sum((r.quote ->> 'total')::numeric)
             filter (where r.status = 'confirmed'), 0)
  from public.reservations r
  join public.units u on u.id = r.unit_id
  join public.properties p on p.id = u.property_id
  where r.kind = 'booking'
    and r.quote is not null
    and (lower(r.period) at time zone p.timezone)::date between p_from and p_to
    and (p_property_id is null or p.id = p_property_id)
  group by 1, 2
  order by 1;
end;
$$;

create function public.report_occupancy(
  p_from        date,
  p_to          date,
  p_property_id uuid default null
) returns table (
  unit_id         uuid,
  unit_name       text,
  nights_available int,
  nights_booked    int,
  occupancy_pct    numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_span int := greatest((p_to - p_from), 1);
begin
  perform public.assert_staff();

  -- I1: casting `upper(period)`/`lower(period)` straight to `::date` uses
  -- the SESSION timezone (UTC here), not the property's. The app stores
  -- UTC instants and every property is Asia/Kolkata (UTC+5:30); a checkout
  -- whose IST clock time is before 05:30 lands, in UTC, on the PREVIOUS
  -- calendar date. Cast under the session timezone and a 2-night IST stay
  -- silently becomes 1 night. Converting `at time zone p.timezone` first,
  -- exactly like report_revenue does, fixes it.
  return query
  select
    u.id,
    u.name,
    v_span,
    coalesce((
      select sum(
        least((upper(r.period) at time zone p.timezone)::date, p_to)
        - greatest((lower(r.period) at time zone p.timezone)::date, p_from)
      )::int
      from public.reservations r
      where r.unit_id = u.id
        and r.kind = 'booking'
        and r.status = 'confirmed'
        and r.period && tstzrange(p_from::timestamptz, p_to::timestamptz, '[)')
    ), 0),
    round(
      coalesce((
        select sum(
          least((upper(r.period) at time zone p.timezone)::date, p_to)
          - greatest((lower(r.period) at time zone p.timezone)::date, p_from)
        )::numeric
        from public.reservations r
        where r.unit_id = u.id
          and r.kind = 'booking'
          and r.status = 'confirmed'
          and r.period && tstzrange(p_from::timestamptz, p_to::timestamptz, '[)')
      ), 0) * 100 / v_span, 1)
  from public.units u
  join public.properties p on p.id = u.property_id
  where u.is_active
    and (p_property_id is null or p.id = p_property_id)
  order by u.name;
end;
$$;

create function public.dashboard_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_month_start date := date_trunc('month', v_today)::date;
begin
  perform public.assert_staff();

  return jsonb_build_object(
    'today_revenue', coalesce((
      select sum(net) from public.report_revenue(v_today, v_today)), 0),
    'month_revenue', coalesce((
      select sum(net) from public.report_revenue(v_month_start, v_today)), 0),
    'occupancy_pct', coalesce((
      select round(avg(occupancy_pct), 1)
      from public.report_occupancy(v_month_start, v_today)), 0),
    'upcoming_arrivals', (
      select count(*)::int from public.reservations
      where kind = 'booking' and status = 'confirmed'
        and lower(period) >= now()
        and lower(period) < now() + interval '7 days'),
    'cancellations_this_month', (
      select count(*)::int from public.reservations
      where kind = 'booking' and status = 'cancelled'
        and cancelled_at >= v_month_start),
    'active_holds', (
      select count(*)::int from public.reservations
      where status = 'hold' and hold_expires_at > now())
  );
end;
$$;

grant execute on function public.report_revenue    to authenticated;
grant execute on function public.report_occupancy  to authenticated;
grant execute on function public.dashboard_summary to authenticated;
