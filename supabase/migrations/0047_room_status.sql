-- Room status grid (REQ-06): the housekeeping state of each unit,
-- housekeeping tasks linked to a unit, and a per-resort cleaning SLA.
-- See docs/superpowers/specs/2026-09-25-room-status-grid-design.md.
--
-- Error codes: P0030 reason_required (Maintenance needs a reason), P0031
-- already_dispatched (the unit already has an open housekeeping task).
-- Also raised: P0002 (unknown unit), P0005 (missing state), P0020
-- not_a_member, P0021 resort_mismatch, P0022 resort_suspended.

create type public.room_state as enum ('ready', 'dirty', 'out_of_order');
create type public.task_kind as enum ('general', 'housekeeping');

-- ---------------------------------------------------------------------
-- The cleaning SLA: an open housekeeping task older than this many
-- minutes shows Overdue on the board.
alter table public.properties
  add column housekeeping_sla_minutes int not null default 60
    constraint properties_housekeeping_sla_positive
      check (housekeeping_sla_minutes > 0);

-- ---------------------------------------------------------------------
-- unit_room_status: the state a person set. A unit without a row is
-- `ready`. Occupied is never stored -- room_status_board derives it from
-- a checked-in reservation. Readable by the resort's Staff+; written only
-- by the security definer functions below (no write grant or policy).
create table public.unit_room_status (
  unit_id     uuid primary key references public.units(id) on delete cascade,
  property_id uuid not null references public.properties(id),
  state       public.room_state not null default 'ready',
  reason      text,
  updated_by  uuid default auth.uid(),
  updated_at  timestamptz not null default now(),
  -- coalesce: `length(trim(null)) > 0` is null, which a CHECK accepts,
  -- so without it a null reason would slip through.
  constraint unit_room_status_reason_required
    check (state <> 'out_of_order' or coalesce(length(btrim(reason)), 0) > 0)
);
create index unit_room_status_property_idx on public.unit_room_status (property_id);

create trigger unit_room_status_fill_property
  before insert or update on public.unit_room_status
  for each row execute function public.fill_property_id('units', 'unit_id');

alter table public.unit_room_status enable row level security;
revoke all on public.unit_room_status from anon, authenticated;
grant select on public.unit_room_status to authenticated;

create policy unit_room_status_read on public.unit_room_status
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));

-- ---------------------------------------------------------------------
-- tasks: a housekeeping task points at a unit. completed_at already
-- exists (0029); started_at joins it.
alter table public.tasks
  add column kind       public.task_kind not null default 'general',
  add column unit_id    uuid references public.units(id) on delete set null,
  add column started_at timestamptz;
create index tasks_unit_idx on public.tasks (unit_id) where unit_id is not null;

-- ---------------------------------------------------------------------
-- Room functions. The signatures are the contract the app is built
-- against; Tasks 2 and 3 of the plan replace the stub bodies.

create function public.room_status_board(p_property uuid)
returns table (
  unit_id                    uuid,
  name                       text,
  booking_mode               public.booking_mode,
  effective_status           text,
  state                      public.room_state,
  reason                     text,
  occupied_reservation_id    uuid,
  guest_first_name           text,
  arriving_today             boolean,
  housekeeping_task_id       uuid,
  housekeeper_name           text,
  housekeeping_status        public.task_status,
  housekeeping_dispatched_at timestamptz,
  overdue                    boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'room_status_board is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.set_room_status(
  p_unit   uuid,
  p_state  public.room_state,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'set_room_status is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.dispatch_housekeeping(
  p_unit     uuid,
  p_assignee uuid,
  p_note     text default null
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'dispatch_housekeeping is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.list_dispatchable_staff(p_property uuid)
returns table (user_id uuid, full_name text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'list_dispatchable_staff is not implemented yet' using errcode = '0A000';
end;
$$;

revoke execute on function public.room_status_board(uuid) from public, anon;
revoke execute on function public.set_room_status(uuid, public.room_state, text) from public, anon;
revoke execute on function public.dispatch_housekeeping(uuid, uuid, text) from public, anon;
revoke execute on function public.list_dispatchable_staff(uuid) from public, anon;
grant execute on function public.room_status_board(uuid) to authenticated;
grant execute on function public.set_room_status(uuid, public.room_state, text) to authenticated;
grant execute on function public.dispatch_housekeeping(uuid, uuid, text) to authenticated;
grant execute on function public.list_dispatchable_staff(uuid) to authenticated;
