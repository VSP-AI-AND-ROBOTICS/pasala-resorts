-- Activity booking during a stay. `activities` is an admin-managed catalog
-- (name, per-person price, per-slot capacity). `activity_bookings` snapshots
-- the price at booking time -- same "server prices, client never does"
-- principle as 0032's food ordering -- and enforces slot capacity by
-- summing existing bookings for that activity/date/time, the same
-- overlap-prevention spirit as the reservation exclusion constraint but
-- expressed as an aggregate check inside the RPC since a slot is a plain
-- (date, time) pair, not a period.
create table public.activities (
  id                 uuid primary key default gen_random_uuid(),
  property_id        uuid not null references public.properties(id) on delete cascade,
  name               text not null,
  description        text,
  price_per_person   numeric(10,2) not null check (price_per_person >= 0),
  capacity_per_slot  int not null check (capacity_per_slot > 0),
  is_available       boolean not null default true,
  created_at         timestamptz not null default now()
);

grant select on public.activities to authenticated;
grant insert, update, delete on public.activities to authenticated;

alter table public.activities enable row level security;

create policy activities_read on public.activities
  for select to authenticated using (true);
create policy activities_admin_write on public.activities
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create type public.activity_booking_status as enum ('booked', 'cancelled');

create table public.activity_bookings (
  id             uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.reservations(id) on delete cascade,
  activity_id    uuid not null references public.activities(id),
  booking_date   date not null,
  start_time     time not null,
  people         int not null check (people > 0),
  amount         numeric(12,2) not null check (amount >= 0),
  status         public.activity_booking_status not null default 'booked',
  created_at     timestamptz not null default now()
);

create index activity_bookings_reservation_idx on public.activity_bookings(reservation_id);
create index activity_bookings_slot_idx
  on public.activity_bookings(activity_id, booking_date, start_time)
  where status = 'booked';

-- No INSERT grant -- `book_activity` (security definer) is the only writer.
-- UPDATE is limited to cancelling: `activity_bookings_owner_cancel` lets the
-- owning customer flip `booked -> cancelled` and nothing else (the `check`
-- re-tests ownership, and cancelling is idempotent-safe since the RPC below
-- never has to touch this path -- a customer just updates the row directly,
-- there's no server-priced work left to do once the amount is already set).
grant select, update on public.activity_bookings to authenticated;

alter table public.activity_bookings enable row level security;

create policy activity_bookings_read on public.activity_bookings
  for select to authenticated
  using (
    public.is_staff_or_above()
    or exists (
      select 1 from public.reservations r
      where r.id = reservation_id and r.customer_id = auth.uid()
    )
  );

create policy activity_bookings_owner_cancel on public.activity_bookings
  for update to authenticated
  using (
    exists (
      select 1 from public.reservations r
      where r.id = reservation_id and r.customer_id = auth.uid()
    )
  )
  with check (
    status = 'cancelled'
    and exists (
      select 1 from public.reservations r
      where r.id = reservation_id and r.customer_id = auth.uid()
    )
  );

-- Gated on `confirmed`/`checked_in`, same as `place_food_order`. Capacity is
-- enforced by summing `people` across existing `booked` rows for the same
-- activity/date/time and rejecting if the new booking would exceed
-- `capacity_per_slot` -- a plain read-then-check under the row lock taken
-- by this function's own insert is sufficient here (unlike stay-date
-- overlap, a lost race just double-books a handful of activity seats, not
-- the same physical unit for the same night, and activity capacity is
-- advisory in a way a farmhouse's own private booking never is).
create function public.book_activity(
  p_reservation_id uuid,
  p_activity_id    uuid,
  p_booking_date   date,
  p_start_time     time,
  p_people         int
) returns public.activity_bookings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid      uuid := auth.uid();
  v_res      public.reservations;
  v_activity public.activities;
  v_booked   int;
  v_booking  public.activity_bookings;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_res from public.reservations where id = p_reservation_id;
  if not found or v_res.customer_id is distinct from v_uid then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if v_res.status not in ('confirmed', 'checked_in') then
    raise exception 'this stay is not open for activity booking' using errcode = 'P0009';
  end if;

  if p_people <= 0 then
    raise exception 'people must be positive' using errcode = 'P0003';
  end if;

  -- Locks the activity row itself, not the (aggregate) booking count --
  -- `for update` cannot target an aggregate directly. This serializes every
  -- concurrent booking attempt on the same activity behind one lock, which
  -- is coarser than locking just this slot, but activity capacity is
  -- advisory (see this function's own header comment) so contention across
  -- unrelated slots on a popular activity is an acceptable tradeoff for a
  -- correct, simple capacity check.
  select * into v_activity from public.activities
  where id = p_activity_id and is_available
  for update;
  if not found then
    raise exception 'activity is not available' using errcode = 'P0002';
  end if;

  select coalesce(sum(people), 0) into v_booked
  from public.activity_bookings
  where activity_id = p_activity_id
    and booking_date = p_booking_date
    and start_time = p_start_time
    and status = 'booked';

  if v_booked + p_people > v_activity.capacity_per_slot then
    raise exception 'this slot is full' using errcode = 'P0010';
  end if;

  insert into public.activity_bookings
    (reservation_id, activity_id, booking_date, start_time, people, amount)
  values
    (p_reservation_id, p_activity_id, p_booking_date, p_start_time, p_people,
     v_activity.price_per_person * p_people)
  returning * into v_booking;

  return v_booking;
end;
$$;

grant execute on function public.book_activity(uuid, uuid, date, time, int) to authenticated;
revoke execute on function public.book_activity(uuid, uuid, date, time, int) from public;
revoke execute on function public.book_activity(uuid, uuid, date, time, int) from anon;

-- No demo catalog is seeded here: migrations run before seed.sql during
-- `supabase db reset`, and the one demo property doesn't exist yet at this
-- point -- see seed.sql for the starter activity list.
