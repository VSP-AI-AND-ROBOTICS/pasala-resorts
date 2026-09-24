-- ResortHub tenancy, part 4: retire the global business roles.
-- See docs/superpowers/specs/2026-09-24-resorthub-tenancy-design.md.
--
-- Resort roles now live only in resort_members (0043 copied every staff
-- role there), and every policy and function checks them through
-- has_resort_role / assert_resort_role (0044, 0045). What is left of the
-- old global roles goes here: the user_role column and enum, and the
-- helpers that read it. profiles.platform_role takes over the name
-- profiles.role.

-- Drops the column's default and profiles_update_self, the only objects
-- that depend on it (recreated below). No other profiles policy reads
-- the role.
alter table public.profiles drop column role cascade;
alter table public.profiles rename column platform_role to role;

drop function if exists public.assert_staff();
drop function if exists public.is_super_admin();
drop function if exists public.is_admin();
drop function if exists public.is_staff_or_above();
drop function if exists public.current_role();
drop type public.user_role;

-- A SQL function body is stored as text, so the rename does not reach
-- it: recreate it against the renamed column.
create or replace function public.is_platform_admin()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select role = 'platform_admin' from public.profiles where id = auth.uid()),
    false);
$$;

-- Self-update may not change the role. The stored role is read through
-- the security definer is_platform_admin(): a policy on profiles that
-- selects from profiles itself fails with "infinite recursion detected
-- in policy for relation profiles". platform_role has two values, so
-- matching is_platform_admin() pins the role to what is stored.
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid()
              and (role = 'platform_admin') = public.is_platform_admin());

-- New sign-ups are customers. The column default says so too; spelled
-- out so the trigger does not depend on it.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, full_name, phone, role)
  values (new.id,
          new.raw_user_meta_data ->> 'full_name',
          new.raw_user_meta_data ->> 'phone',
          'customer');
  return new;
end;
$$;

-- Unchanged from 0045 except the comment, which named the dropped
-- global role-setting function.
create or replace function public.set_member_role(
  p_property uuid,
  p_user     uuid,
  p_role     public.resort_role
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old          public.resort_members;
  v_new          public.resort_members;
  v_owner_count  int;
begin
  perform public.assert_resort_role(p_property, true, 'owner');

  if p_role is null then
    raise exception 'role is required' using errcode = 'P0005';
  end if;

  -- The last-owner guard: without it, the only owner demoting themself
  -- leaves a resort nobody can manage.
  --
  -- A single `for update` on just this row only locks the row being
  -- changed -- it does not conflict with a concurrent transaction demoting
  -- a DIFFERENT owner, so a plain `select count(*)` afterwards can read a
  -- count that predates either commit. Two owners each demoting the other
  -- "simultaneously" would both see count = 2, both pass, and both commit,
  -- leaving zero -- exactly the lockout this guard exists to prevent (the
  -- race ecd7182 closed for the old global last super admin). The check
  -- and the read it depends on must happen under a lock a competing
  -- transaction is actually forced to wait on.
  --
  -- Fixed by locking every owner row of this resort -- not just this one --
  -- in a fixed order (`order by user_id`) before counting. That order is
  -- also why this must be the FIRST lock this transaction takes on any
  -- owner row: if p_user's own row were locked first, two transactions
  -- demoting two different owners would each already hold their own
  -- target's lock before reaching this statement, and each would then
  -- block waiting for the other's -- a deadlock, not a clean queue.
  --
  -- Unlike the old global role setter, this takes the owner locks on every
  -- call, not only when an unlocked peek says the target is an owner: a
  -- peek can be stale (the target promoted to owner just after it), which
  -- would skip the guard. A resort has a handful of owners, so the extra
  -- locking is negligible.
  perform 1 from public.resort_members
   where property_id = p_property and role = 'owner'
   order by user_id
   for update;

  select * into v_old from public.resort_members
   where property_id = p_property and user_id = p_user
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;

  -- Setting a role to its current value is a no-op that succeeds, not an
  -- error -- the caller (e.g. a screen re-submitting an unchanged
  -- dropdown) should never have to special-case "same value" itself.
  if v_old.role = p_role then
    return;
  end if;

  if v_old.role = 'owner' then
    select count(*) into v_owner_count
      from public.resort_members
     where property_id = p_property and role = 'owner';
    if v_owner_count <= 1 then
      raise exception using errcode = 'P0023', message = 'last_owner';
    end if;
  end if;

  update public.resort_members set role = p_role
   where property_id = p_property and user_id = p_user
   returning * into v_new;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'resort_member', p_user,
          'role:' || v_old.role::text || '->' || p_role::text,
          to_jsonb(v_old), to_jsonb(v_new), p_property);
end;
$$;
