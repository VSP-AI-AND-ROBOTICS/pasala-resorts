-- A public, identity-free mirror of reservation occupancy.
--
-- The calendar must show every busy range to every viewer, but `reservations`
-- is row-locked to its owner and staff, and Supabase realtime applies RLS to
-- its change feed -- so a customer would never learn that someone else booked
-- a date. This table carries occupancy WITHOUT identity: no customer_id, no
-- quote, no block reason. It is maintained by a trigger and never written
-- directly.
create table public.unit_calendar_events (
  reservation_id uuid primary key
                 references public.reservations(id) on delete cascade,
  unit_id        uuid not null references public.units(id) on delete cascade,
  period         tstzrange not null,
  kind           public.reservation_kind not null,
  status         public.reservation_status not null,
  updated_at     timestamptz not null default now()
);

create index unit_calendar_events_unit_idx
  on public.unit_calendar_events(unit_id);

alter table public.unit_calendar_events enable row level security;

grant select on public.unit_calendar_events to anon, authenticated;

create policy calendar_events_read on public.unit_calendar_events
  for select to anon, authenticated using (true);

-- Deliberately no insert/update/delete policy and no write grant: the
-- SECURITY DEFINER trigger below is the only writer.

create function public.sync_unit_calendar_event()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.unit_calendar_events where reservation_id = old.id;
    return old;
  end if;

  if new.status = 'cancelled' then
    delete from public.unit_calendar_events where reservation_id = new.id;
    return new;
  end if;

  insert into public.unit_calendar_events
    (reservation_id, unit_id, period, kind, status, updated_at)
  values (new.id, new.unit_id, new.period, new.kind, new.status, now())
  on conflict (reservation_id) do update
    set unit_id = excluded.unit_id,
        period  = excluded.period,
        kind    = excluded.kind,
        status  = excluded.status,
        updated_at = now();
  return new;
end;
$$;

create trigger reservations_sync_calendar
  after insert or update or delete on public.reservations
  for each row execute function public.sync_unit_calendar_event();

insert into public.unit_calendar_events
  (reservation_id, unit_id, period, kind, status)
select id, unit_id, period, kind, status
from public.reservations
where status <> 'cancelled';

alter publication supabase_realtime add table public.unit_calendar_events;
