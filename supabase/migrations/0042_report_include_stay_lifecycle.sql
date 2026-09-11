-- I6: `report_revenue` and `report_occupancy` (0015_reports.sql) only ever
-- counted reservations with `status = 'confirmed'`. That was correct the
-- day it was written -- 'confirmed' was the only non-terminal, paid state a
-- real booking could be in. 0031_stay_lifecycle.sql later added
-- 'checked_in' and 'checked_out' as the stay progresses, but never updated
-- these two report functions to match: the instant a guest is checked in,
-- their booking silently disappears from the owner's revenue and occupancy
-- figures for the rest of its life, even though it is exactly as real and
-- exactly as paid as it was one second earlier as 'confirmed'.
--
-- Reproduced live: a guest who paid the full quoted total, checked in, and
-- checked out today reports `today_revenue = 0` and contributes nothing to
-- `occupancy_pct` -- the dashboard looks emptier the more successfully the
-- business actually runs.
--
-- Fix: both functions now treat 'confirmed', 'checked_in' and
-- 'checked_out' as the same "this booking happened" state for reporting
-- purposes. 'hold' (unpaid, may expire) and 'cancelled' (already handled
-- separately via `refund_amount`) are deliberately excluded, unchanged.
create or replace function public.report_revenue(p_from date, p_to date, p_property_id uuid default null::uuid)
 returns table(day date, property_id uuid, bookings integer, gross numeric, refunded numeric, net numeric)
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  perform public.assert_staff();

  return query
  select
    (lower(r.period) at time zone p.timezone)::date as day,
    p.id,
    count(*)::int,
    coalesce(sum((r.quote ->> 'total')::numeric)
             filter (where r.status in ('confirmed','checked_in','checked_out')), 0),
    coalesce(sum(r.refund_amount)
             filter (where r.status = 'cancelled'), 0),
    coalesce(sum((r.quote ->> 'total')::numeric)
             filter (where r.status in ('confirmed','checked_in','checked_out')), 0)
    - coalesce(sum(r.refund_amount)
               filter (where r.status = 'cancelled'), 0)
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
$function$;

create or replace function public.report_occupancy(p_from date, p_to date, p_property_id uuid default null::uuid)
 returns table(unit_id uuid, unit_name text, nights_available integer, nights_booked integer, occupancy_pct numeric)
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_span int := greatest((p_to - p_from), 1);
begin
  perform public.assert_staff();

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
        and r.status in ('confirmed','checked_in','checked_out')
        and r.period && tstzrange(p_from::timestamp at time zone p.timezone,
                                   p_to::timestamp at time zone p.timezone, '[)')
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
          and r.status in ('confirmed','checked_in','checked_out')
          and r.period && tstzrange(p_from::timestamp at time zone p.timezone,
                                     p_to::timestamp at time zone p.timezone, '[)')
      ), 0) * 100 / v_span, 1)
  from public.units u
  join public.properties p on p.id = u.property_id
  where u.is_active
    and (p_property_id is null or p.id = p_property_id)
  order by u.name;
end;
$function$;
