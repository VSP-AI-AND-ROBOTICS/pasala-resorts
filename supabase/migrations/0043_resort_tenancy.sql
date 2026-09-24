-- ResortHub tenancy foundation, part 1: resorts, memberships, helpers.
-- See docs/superpowers/specs/2026-09-24-resorthub-tenancy-design.md.

create type public.resort_role as enum ('owner','admin','staff','accountant');
create type public.platform_role as enum ('customer','platform_admin');

alter table public.properties
  add column status text not null default 'active'
    check (status in ('active','suspended','archived'));

-- Folded into profiles.role by 0046; separate until then so the old
-- user_role-based helpers keep working while 0044/0045 are applied.
alter table public.profiles
  add column platform_role public.platform_role not null default 'customer';

create table public.resort_members (
  property_id uuid not null references public.properties(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  role        public.resort_role not null,
  created_at  timestamptz not null default now(),
  primary key (property_id, user_id)
);
create index resort_members_user_idx on public.resort_members (user_id);
alter table public.resort_members enable row level security;

create function public.is_platform_admin()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select platform_role = 'platform_admin' from public.profiles
      where id = auth.uid()),
    false);
$$;

create function public.resort_role(p_property uuid)
returns public.resort_role
language sql stable security definer
set search_path = public, pg_temp
as $$
  select role from public.resort_members
   where property_id = p_property and user_id = auth.uid();
$$;

create function public.has_resort_role(
  p_property uuid,
  p_write    boolean,
  variadic p_roles public.resort_role[]
) returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select m.role = any (p_roles)
       and (p.status = 'active' or (p.status = 'suspended' and not p_write))
      from public.resort_members m
      join public.properties p on p.id = m.property_id
     where m.property_id = p_property and m.user_id = auth.uid()
  ), false);
$$;

-- For functions: raises instead of returning false, so callers get a
-- specific error code.
create function public.assert_resort_role(
  p_property uuid,
  p_write    boolean,
  variadic p_roles public.resort_role[]
) returns void
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_role   public.resort_role;
  v_status text;
begin
  select m.role, p.status into v_role, v_status
    from public.resort_members m
    join public.properties p on p.id = m.property_id
   where m.property_id = p_property and m.user_id = auth.uid();
  if v_role is null or not (v_role = any (p_roles)) then
    raise exception using errcode = 'P0020', message = 'not_a_member';
  end if;
  if p_write and v_status <> 'active' then
    raise exception using errcode = 'P0022', message = 'resort_suspended';
  end if;
  if not p_write and v_status = 'archived' then
    raise exception using errcode = 'P0020', message = 'not_a_member';
  end if;
end;
$$;

grant execute on function public.is_platform_admin() to authenticated;
grant execute on function public.resort_role(uuid) to authenticated;
grant execute on function public.has_resort_role(uuid, boolean, public.resort_role[]) to authenticated, anon;
grant execute on function public.assert_resort_role(uuid, boolean, public.resort_role[]) to authenticated;

-- Members read their own resort's roster; owners manage it through the
-- functions in 0045 (no direct write policy).
create policy resort_members_read on public.resort_members
  for select to authenticated
  using (user_id = auth.uid()
         or public.has_resort_role(property_id, false, 'owner','admin'));

-- ---------------------------------------------------------------------
-- property_id on every resort-owned table.

create function public.fill_property_id()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_parent_table text := tg_argv[0];
  v_parent_col   text := tg_argv[1];
  v_parent_id    uuid;
  v_property     uuid;
begin
  execute format('select ($1).%I', v_parent_col) into v_parent_id using new;
  if v_parent_id is null then
    return new;
  end if;
  execute format('select property_id from public.%I where id = $1', v_parent_table)
    into v_property using v_parent_id;
  if tg_op = 'INSERT' and new.property_id is null then
    new.property_id := v_property;
  elsif new.property_id is distinct from v_property then
    raise exception using errcode = 'P0021', message = 'resort_mismatch';
  end if;
  return new;
end;
$$;

do $$
declare
  r record;
begin
  for r in select * from (values
    ('reservations','unit_id','units'),
    ('rate_rules','unit_id','units'),
    ('ical_feeds','unit_id','units'),
    ('ical_export_tokens','unit_id','units'),
    ('payments','reservation_id','reservations'),
    ('food_orders','reservation_id','reservations'),
    ('activity_bookings','reservation_id','reservations'),
    ('coupon_redemptions','reservation_id','reservations'),
    ('reviews','reservation_id','reservations'),
    ('service_requests','reservation_id','reservations'),
    ('maintenance_issues','reservation_id','reservations'),
    ('unit_calendar_events','reservation_id','reservations'),
    ('food_items','category_id','food_categories'),
    ('food_order_items','order_id','food_orders')
  ) as t(child, col, parent)
  loop
    execute format('alter table public.%I add column property_id uuid references public.properties(id)', r.child);
    -- Backfilling with a plain UPDATE would otherwise fire every
    -- user trigger on the table for each existing row: write-guard
    -- triggers reject the update outright (no auth.uid() in a
    -- migration), and side-effecting triggers on reservations
    -- (audit log, outbox enqueue, calendar sync) would re-fire for
    -- history that already happened. Disable user triggers for the
    -- duration of the backfill only; the new fill_property_id
    -- trigger below is created after they're re-enabled.
    execute format('alter table public.%I disable trigger user', r.child);
    execute format(
      'update public.%I c set property_id = p.property_id from public.%I p where p.id = c.%I',
      r.child, r.parent, r.col);
    execute format('alter table public.%I enable trigger user', r.child);
    execute format('create index %I on public.%I (property_id)', r.child || '_property_idx', r.child);
    execute format(
      'create trigger %I before insert or update on public.%I
         for each row execute function public.fill_property_id(%L, %L)',
      r.child || '_fill_property', r.child, r.parent, r.col);
  end loop;
end;
$$;

-- Tables with no path to a resort: everything that exists today belongs
-- to the single existing property.
do $$
declare
  v_pasala uuid;
  t text;
begin
  select id into v_pasala from public.properties order by created_at, id limit 1;
  foreach t in array array['coupons','outbox','outbox_templates','staff_shifts',
                           'leave_requests','attendance_records','tasks','audit_log']
  loop
    execute format('alter table public.%I add column property_id uuid references public.properties(id)', t);
    if v_pasala is not null and t not in ('outbox_templates') then
      -- Same reasoning as above: skip write-guard triggers (e.g.
      -- staff_shifts' admin-only check) for this system backfill.
      execute format('alter table public.%I disable trigger user', t);
      execute format('update public.%I set property_id = $1', t) using v_pasala;
      execute format('alter table public.%I enable trigger user', t);
    end if;
    execute format('create index %I on public.%I (property_id)', t || '_property_idx', t);
  end loop;
end;
$$;

-- outbox_templates rows stay platform defaults (property_id null);
-- audit_log keeps null for platform-level events. Six other "no link
-- today" tables (coupons, outbox, staff_shifts, leave_requests,
-- attendance_records, tasks) are backfilled above but stay nullable
-- for now: a later task sets them NOT NULL once the triggers and
-- tests that supply property_id on those tables land. Everything
-- derivable from a resort-scoped parent is required from here on.
do $$
declare
  t text;
begin
  foreach t in array array[
    'reservations','rate_rules','ical_feeds','ical_export_tokens','payments',
    'food_orders','activity_bookings','coupon_redemptions','reviews',
    'service_requests','maintenance_issues','unit_calendar_events','food_items',
    'food_order_items']
  loop
    execute format('alter table public.%I alter column property_id set not null', t);
  end loop;
end;
$$;

-- Existing global staff roles become memberships at the first property.
insert into public.resort_members (property_id, user_id, role)
select (select id from public.properties order by created_at, id limit 1),
       p.id,
       case p.role when 'super_admin' then 'owner'::public.resort_role
                   else p.role::text::public.resort_role end
  from public.profiles p
 where p.role <> 'customer'
   and exists (select 1 from public.properties);
