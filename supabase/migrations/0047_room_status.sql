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

-- A room belongs only on a housekeeping task. Not the spec's strict
-- `(kind = 'housekeeping') = (unit_id is not null)`: with
-- `on delete set null` above, that would refuse every delete of a unit
-- with housekeeping history. dispatch_housekeeping always sets unit_id.
alter table public.tasks
  add constraint tasks_unit_only_for_housekeeping
    check (unit_id is null or kind = 'housekeeping');

-- One open housekeeping task per unit. dispatch_housekeeping checks first
-- and raises P0031; this index settles two dispatches that race past that
-- check.
create unique index tasks_one_open_housekeeping_per_unit
  on public.tasks (unit_id)
  where kind = 'housekeeping' and status <> 'done';

-- The unit's resort must be the task's resort (P0021), as for every other
-- unit-linked table (0043). A general task (no unit) passes straight
-- through.
create trigger tasks_fill_property
  before insert or update on public.tasks
  for each row execute function public.fill_property_id('units', 'unit_id');

-- tasks_enforce_write, copied from 0045 with three changes:
--  * started_at is set the first time a task moves to in_progress;
--  * the assignee's status-only path also may not change kind, unit_id,
--    started_at or completed_at;
--  * on a housekeeping task, an owner/admin/staff member of its resort
--    may change the status only. RLS (tasks_update) still admits only
--    admins and the assignee to a direct update, so this "room writer"
--    path is reachable only through set_room_status.
create or replace function public.tasks_enforce_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin boolean := public.has_resort_role(old.property_id, true, 'owner','admin');
  v_room_writer boolean := old.kind = 'housekeeping'
    and public.has_resort_role(old.property_id, true, 'owner','admin','staff');
begin
  if TG_OP = 'DELETE' then
    if not v_admin then
      raise sqlstate '42501' using
        message = 'permission denied for table tasks',
        hint = 'only an administrator can delete a task';
    end if;
    return old;
  end if;

  if v_admin and public.has_resort_role(new.property_id, true, 'owner','admin') then
    new.updated_at := clock_timestamp();
    if new.status = 'in_progress' and old.started_at is null then
      new.started_at := clock_timestamp();
    end if;
    if new.status = 'done' and old.completed_at is null then
      new.completed_at := clock_timestamp();
    end if;
    return new;
  end if;

  if new.assignee_id <> old.assignee_id then
    raise sqlstate '42501' using
      message = 'permission denied for table tasks',
      hint = 'only an administrator can reassign a task';
  end if;

  if new.id is distinct from old.id
      or new.title is distinct from old.title
      or new.description is distinct from old.description
      or new.created_by is distinct from old.created_by
      or new.created_at is distinct from old.created_at
      or new.property_id is distinct from old.property_id
      or new.kind is distinct from old.kind
      or new.unit_id is distinct from old.unit_id
      or new.started_at is distinct from old.started_at
      or new.completed_at is distinct from old.completed_at then
    raise sqlstate '42501' using
      message = 'permission denied for table tasks',
      hint = 'only an administrator can edit a task''s details';
  end if;

  if old.assignee_id <> auth.uid() and not v_room_writer then
    raise sqlstate '42501' using
      message = 'permission denied for table tasks',
      hint = 'you can only update the status of your own tasks';
  end if;

  new.updated_at := clock_timestamp();
  if new.status = 'in_progress' and old.started_at is null then
    new.started_at := clock_timestamp();
  end if;
  if new.status = 'done' and old.completed_at is null then
    new.completed_at := clock_timestamp();
  end if;
  return new;
end;
$$;

-- A finished housekeeping task makes a dirty room ready. An out-of-order
-- room stays in Maintenance: only a person clears that.
create function public.tasks_housekeeping_done()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.unit_room_status
     set state = 'ready', reason = null, updated_by = auth.uid(), updated_at = now()
   where unit_id = new.unit_id
     and state = 'dirty';
  return null;
end;
$$;

create trigger tasks_housekeeping_done
  after update of status on public.tasks
  for each row
  when (new.kind = 'housekeeping' and new.unit_id is not null
        and new.status = 'done' and old.status is distinct from 'done')
  execute function public.tasks_housekeeping_done();

-- ---------------------------------------------------------------------
-- Room functions. The signatures are the contract the app is built
-- against; Tasks 2 and 3 of the plan replace the stub bodies.

-- One row per active unit of the resort, for the room grid. Staff+ of the
-- resort (reads are allowed while it is suspended). effective_status:
-- occupied (a checked-in reservation) > maintenance (out_of_order) >
-- cleaning (dirty) > available. The stored state comes back too, so an
-- occupied room can still carry a needs-cleaning or out-of-order badge.
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
#variable_conflict use_column
declare
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_sla   int;
begin
  perform public.assert_resort_role(p_property, false, 'owner','admin','staff','accountant');

  select p.housekeeping_sla_minutes into v_sla
    from public.properties p where p.id = p_property;

  return query
    select u.id,
           u.name,
           u.booking_mode,
           case
             when occ.id is not null then 'occupied'
             when s.state = 'out_of_order' then 'maintenance'
             when s.state = 'dirty' then 'cleaning'
             else 'available'
           end,
           coalesce(s.state, 'ready'::public.room_state),
           s.reason,
           occ.id,
           nullif(split_part(btrim(g.full_name), ' ', 1), ''),
           exists (select 1 from public.reservations a
                    where a.unit_id = u.id
                      and a.kind <> 'block'
                      and a.status = 'confirmed'
                      and (lower(a.period) at time zone 'Asia/Kolkata')::date = v_today),
           hk.id,
           hp.full_name,
           hk.status,
           hk.created_at,
           coalesce(hk.created_at < now() - make_interval(mins => v_sla), false)
      from public.units u
      left join public.unit_room_status s on s.unit_id = u.id
      left join lateral (
        select r.id, r.customer_id
          from public.reservations r
         where r.unit_id = u.id and r.status = 'checked_in'
         order by r.checked_in_at desc nulls last
         limit 1
      ) occ on true
      left join public.profiles g on g.id = occ.customer_id
      left join lateral (
        select t.id, t.assignee_id, t.status, t.created_at
          from public.tasks t
         where t.unit_id = u.id and t.kind = 'housekeeping' and t.status <> 'done'
         order by t.created_at desc
         limit 1
      ) hk on true
      left join public.profiles hp on hp.id = hk.assignee_id
     where u.property_id = p_property and u.is_active
     order by u.name, u.id;
end;
$$;

-- Owner/admin/staff of the unit's resort set its housekeeping state.
-- Maintenance needs a reason (P0030). Available also closes the unit's
-- open housekeeping task -- the room is clean, so the job is done.
create function public.set_room_status(
  p_unit   uuid,
  p_state  public.room_state,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_property uuid;
  v_reason   text := nullif(btrim(p_reason), '');
begin
  select u.property_id into v_property from public.units u where u.id = p_unit;
  if not found then
    raise exception 'unit not found' using errcode = 'P0002';
  end if;

  perform public.assert_resort_role(v_property, true, 'owner','admin','staff');

  if p_state is null then
    raise exception 'state is required' using errcode = 'P0005';
  end if;
  if p_state = 'out_of_order' and v_reason is null then
    raise exception using errcode = 'P0030', message = 'reason_required';
  end if;

  insert into public.unit_room_status as s
    (unit_id, property_id, state, reason, updated_by, updated_at)
  values (p_unit, v_property, p_state,
          case when p_state = 'out_of_order' then v_reason end,
          auth.uid(), now())
  on conflict (unit_id) do update
    set state      = excluded.state,
        reason     = excluded.reason,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;

  if p_state = 'ready' then
    update public.tasks
       set status = 'done'
     where unit_id = p_unit and kind = 'housekeeping' and status <> 'done';
  end if;
end;
$$;

-- Owner/admin/staff of the unit's resort send one `staff` member of that
-- same resort (else P0020) to clean the unit. Refused with P0031 while an
-- open housekeeping task exists. Marks the room dirty unless it is out of
-- order -- sending housekeeping never clears Maintenance. Returns the new
-- task's id.
create function public.dispatch_housekeeping(
  p_unit     uuid,
  p_assignee uuid,
  p_note     text default null
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unit public.units;
  v_task uuid;
begin
  select * into v_unit from public.units where id = p_unit;
  if not found then
    raise exception 'unit not found' using errcode = 'P0002';
  end if;

  perform public.assert_resort_role(v_unit.property_id, true, 'owner','admin','staff');

  if not exists (select 1 from public.resort_members m
                  where m.property_id = v_unit.property_id
                    and m.user_id = p_assignee
                    and m.role = 'staff') then
    raise exception using errcode = 'P0020', message = 'not_a_member';
  end if;

  if exists (select 1 from public.tasks t
              where t.unit_id = p_unit and t.kind = 'housekeeping' and t.status <> 'done') then
    raise exception using errcode = 'P0031', message = 'already_dispatched';
  end if;

  begin
    insert into public.tasks
      (property_id, assignee_id, title, description, kind, unit_id, created_by)
    values
      (v_unit.property_id, p_assignee, 'Clean ' || v_unit.name,
       coalesce(btrim(p_note), ''), 'housekeeping', p_unit, auth.uid())
    returning id into v_task;
  exception when unique_violation then
    -- Lost a race with another dispatch (tasks_one_open_housekeeping_per_unit).
    raise exception using errcode = 'P0031', message = 'already_dispatched';
  end;

  insert into public.unit_room_status as s
    (unit_id, property_id, state, reason, updated_by, updated_at)
  values (p_unit, v_unit.property_id, 'dirty', null, auth.uid(), now())
  on conflict (unit_id) do update
    set state      = 'dirty',
        reason     = null,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at
    where s.state <> 'out_of_order';

  return v_task;
end;
$$;

-- The resort's `staff` members, for the Send housekeeping picker. Needed
-- because staff cannot read the roster (resort_members_read is owner/admin
-- or self); returns only the id and name.
create function public.list_dispatchable_staff(p_property uuid)
returns table (user_id uuid, full_name text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  perform public.assert_resort_role(p_property, false, 'owner','admin','staff');

  return query
    select m.user_id, p.full_name
      from public.resort_members m
      join public.profiles p on p.id = m.user_id
     where m.property_id = p_property and m.role = 'staff'
     order by p.full_name nulls last, m.user_id;
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

-- ---------------------------------------------------------------------
-- checkout_booking, copied from 0045 with one step added: after checkout
-- the unit needs cleaning, unless it is out of order (checkout never
-- clears Maintenance). The idempotent early return for an
-- already-checked-out booking does not touch the room again.
create or replace function public.checkout_booking(
  p_reservation_id uuid,
  p_payment_ref    text,
  p_amount         numeric
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid     uuid := auth.uid();
  v_row     public.reservations;
  v_charges jsonb;
  v_balance numeric(12,2);
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_row.customer_id is distinct from v_uid then
    perform public.assert_resort_role(v_row.property_id, true, 'owner','admin','staff','accountant');
  end if;

  if v_row.status = 'checked_out' then
    return v_row;   -- idempotent: a retried checkout must not double-charge
  end if;

  if v_row.status <> 'checked_in' then
    raise exception 'reservation is %', v_row.status using errcode = 'P0009';
  end if;

  v_charges := public.current_charges(p_reservation_id);
  v_balance := (v_charges ->> 'balance')::numeric;

  if v_balance > 0 and (p_amount is null or p_amount is distinct from v_balance) then
    raise exception 'payment amount % does not match balance due %',
      p_amount, v_balance
      using errcode = 'P0009';
  end if;

  if v_balance > 0 then
    insert into public.payments
      (reservation_id, amount, kind, status, gateway, gateway_ref)
    values (p_reservation_id, v_balance, 'balance', 'succeeded', 'mock', p_payment_ref);
  end if;

  update public.reservations
     set status = 'checked_out', checked_out_at = clock_timestamp()
   where id = p_reservation_id
  returning * into v_row;

  -- 0047: the room needs cleaning now.
  insert into public.unit_room_status as s
    (unit_id, property_id, state, reason, updated_by, updated_at)
  values (v_row.unit_id, v_row.property_id, 'dirty', null, v_uid, now())
  on conflict (unit_id) do update
    set state      = 'dirty',
        reason     = null,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at
    where s.state <> 'out_of_order';

  return v_row;
end;
$$;
