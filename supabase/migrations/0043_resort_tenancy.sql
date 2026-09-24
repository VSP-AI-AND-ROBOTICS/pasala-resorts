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
