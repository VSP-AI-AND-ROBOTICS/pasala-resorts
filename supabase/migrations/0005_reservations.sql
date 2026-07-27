create table public.reservations (
  id              uuid primary key default gen_random_uuid(),
  unit_id         uuid not null references public.units(id) on delete cascade,
  slot_type_id    uuid references public.slot_types(id),
  period          tstzrange not null,
  kind            public.reservation_kind not null default 'booking',
  status          public.reservation_status not null default 'hold',
  customer_id     uuid references public.profiles(id),
  guests          int,
  quote           jsonb,
  hold_expires_at timestamptz,
  block_reason    text,
  cancel_reason   text,
  cancelled_at    timestamptz,
  source          text not null default 'app',
  created_by      uuid references public.profiles(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint reservations_period_nonempty check (not isempty(period)),
  constraint reservations_booking_has_customer check (
    kind <> 'booking' or customer_id is not null),
  constraint reservations_block_has_reason check (
    kind <> 'block' or block_reason is not null),
  constraint reservations_no_overlap
    exclude using gist (unit_id with =, period with &&)
    where (status <> 'cancelled')
);

create index reservations_unit_period_idx
  on public.reservations using gist (unit_id, period);
create index reservations_customer_idx on public.reservations(customer_id);
create index reservations_hold_idx
  on public.reservations(hold_expires_at) where status = 'hold';

-- Customers never write here directly — every write goes through the
-- SECURITY DEFINER RPC in Task 8, which runs as the function owner. The
-- insert/update/delete grants exist for the admin policy below.
grant select on public.reservations to authenticated;
grant insert, update, delete on public.reservations to authenticated;

alter table public.reservations enable row level security;

create function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger reservations_touch
  before update on public.reservations
  for each row execute function public.touch_updated_at();

-- Reads. All writes go through the RPC functions in Task 7, so no
-- INSERT/UPDATE policy is granted to customers at all.
create policy reservations_select_own on public.reservations
  for select to authenticated
  using (customer_id = auth.uid() or public.is_staff_or_above());

create policy reservations_admin_write on public.reservations
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Public availability: busy ranges without customer identity.
create view public.availability
with (security_invoker = off) as
  select r.unit_id, r.period, r.kind
  from public.reservations r
  where r.status <> 'cancelled';

grant select on public.availability to anon, authenticated;

-- Turn dates into a concrete period using property or slot times.
create function public.build_period(
  p_unit_id      uuid,
  p_from         date,
  p_to           date,
  p_slot_type_id uuid default null
) returns tstzrange
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_tz    text;
  v_in    time;
  v_out   time;
  v_start timestamptz;
  v_end   timestamptz;
begin
  select p.timezone, p.check_in_time, p.check_out_time
    into v_tz, v_in, v_out
  from public.units u
  join public.properties p on p.id = u.property_id
  where u.id = p_unit_id;

  if v_tz is null then
    raise exception 'unit not found' using errcode = 'P0002';
  end if;

  if p_slot_type_id is not null then
    select s.start_time, s.end_time into v_in, v_out
    from public.slot_types s where s.id = p_slot_type_id;

    if v_in is null then
      raise exception 'slot type not found' using errcode = 'P0002';
    end if;

    v_start := ((p_from + v_in) at time zone v_tz);
    -- A night slot wraps past midnight; add a day when it does.
    v_end := ((p_from + v_out
               + case when v_out <= v_in then interval '1 day'
                      else interval '0' end) at time zone v_tz);
  else
    if p_to <= p_from then
      raise exception 'check-out must be after check-in'
        using errcode = 'P0005';
    end if;
    v_start := ((p_from + v_in) at time zone v_tz);
    v_end   := ((p_to   + v_out) at time zone v_tz);
  end if;

  return tstzrange(v_start, v_end, '[)');
end;
$$;

create function public.search_availability(
  p_property_id  uuid,
  p_from         date,
  p_to           date,
  p_guests       int default 1,
  p_slot_type_id uuid default null
) returns table (
  unit_id      uuid,
  property_id  uuid,
  unit_name    text,
  booking_mode public.booking_mode,
  is_available boolean,
  busy_periods tstzrange[]
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    u.id,
    u.property_id,
    u.name,
    u.booking_mode,
    not exists (
      select 1 from public.reservations r
      where r.unit_id = u.id
        and r.status <> 'cancelled'
        and r.period && public.build_period(u.id, p_from, p_to, p_slot_type_id)
    ),
    coalesce((
      select array_agg(r.period order by lower(r.period))
      from public.reservations r
      where r.unit_id = u.id
        and r.status <> 'cancelled'
        and r.period && tstzrange(
              (p_from - 1)::timestamptz, (p_to + 1)::timestamptz, '[)')
    ), '{}')
  from public.units u
  join public.properties p on p.id = u.property_id
  where u.is_active
    and p.is_active
    and (p_property_id is null or u.property_id = p_property_id)
    and u.capacity_max >= p_guests
  order by u.name;
$$;

grant execute on function public.search_availability to anon, authenticated;
grant execute on function public.build_period      to anon, authenticated;
grant execute on function public.get_quote         to anon, authenticated;
