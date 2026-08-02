-- User-management screen support: an admin-readable roster of every
-- profile (including the email, which lives in `auth.users`, not
-- `public.profiles`), and a super-admin-only role-change entry point.
--
-- There is deliberately no "create user" function anywhere in this
-- migration. Creating an `auth.users` row requires the service-role key,
-- which must never ship inside a client app -- so the only way a new
-- staff/admin account comes to exist is the ordinary `/signup` flow
-- (`public.handle_new_user`, migration 0002) followed by a super admin
-- promoting that profile with `set_user_role` below. The Flutter screen
-- says this in as many words; see `users_screen.dart`.

-- === list_profiles: the roster, with email joined in from auth.users ======
--
-- SECURITY DEFINER is required here for the same reason it's required
-- everywhere else this schema reaches into `auth.users` (see
-- `handle_new_user`): a plain `authenticated` role has no SELECT grant on
-- `auth.users` at all, and must not gain one -- that table also carries
-- password hashes, MFA secrets and recovery tokens, none of which this
-- function (or the screen behind it) has any business exposing. Only the
-- three columns actually needed are selected out of it; nothing about the
-- shape of this function makes it possible to widen that by accident from
-- the caller's side.
create function public.list_profiles()
returns table(
  id         uuid,
  full_name  text,
  phone      text,
  role       public.user_role,
  email      text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  return query
    select p.id, p.full_name, p.phone, p.role, u.email::text, p.created_at
    from public.profiles p
    join auth.users u on u.id = p.id
    order by p.created_at asc;
end;
$$;

grant execute on function public.list_profiles() to authenticated;
-- C1-sweep convention (see 0018_ical.sql): `grant ... to authenticated`
-- never removes the default PUBLIC EXECUTE a function holds since
-- creation, so `anon` must be revoked explicitly or it reaches the body
-- (and would be rejected there by is_admin(), but only after paying the
-- cost of the join -- and this project no longer accepts "gated in the
-- body" as sufficient on its own after two real incidents of exactly that
-- gap).
revoke execute on function public.list_profiles() from public;
revoke execute on function public.list_profiles() from anon;

-- === set_user_role: the only way a profile's role ever changes outside ====
-- === of direct SQL =========================================================
--
-- `profiles_admin_update`'s WITH CHECK (migration 0002) already pins the
-- role column to a plain admin, so a bare UPDATE from a plain admin is
-- rejected by RLS regardless of this function -- but that policy has no way
-- to express "a super admin may change any role EXCEPT the one that would
-- leave zero super admins standing." That guard can only live in
-- application logic that can COUNT rows before deciding, which is exactly
-- what this function is for.
create function public.set_user_role(p_user_id uuid, p_role public.user_role)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old               public.profiles;
  v_new                public.profiles;
  v_super_admin_count  int;
begin
  if not public.is_super_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if p_role is null then
    raise exception 'role is required' using errcode = 'P0005';
  end if;

  select * into v_old from public.profiles where id = p_user_id for update;
  if not found then
    raise exception 'profile not found' using errcode = 'P0002';
  end if;

  -- Setting a role to its current value is a no-op that succeeds, not an
  -- error -- the caller (e.g. a screen re-submitting an unchanged
  -- dropdown) should never have to special-case "same value" itself.
  if v_old.role = p_role then
    return;
  end if;

  -- The guard the brief calls out by name: without it, a super admin
  -- demoting themselves (the only one left) locks every human out of
  -- administration permanently, recoverable only from psql. `for update`
  -- above plus this count, in the same transaction, close the race where
  -- two super admins each demote the other "simultaneously" -- the second
  -- caller blocks on the first row lock, then re-reads a count that
  -- already reflects the first change.
  if v_old.role = 'super_admin' and p_role is distinct from 'super_admin' then
    select count(*) into v_super_admin_count
    from public.profiles where role = 'super_admin';

    if v_super_admin_count <= 1 then
      raise exception
        'cannot change role: this is the last remaining super_admin'
        using errcode = 'P0014';
    end if;
  end if;

  update public.profiles set role = p_role
    where id = p_user_id
    returning * into v_new;

  -- Same shape as record_reservation_transition (0006_payments_audit.sql):
  -- actor from auth.uid(), full before/after row snapshots, one row per
  -- change.
  insert into public.audit_log (actor_id, entity, entity_id, action, before, after)
  values (auth.uid(), 'profile', p_user_id,
          'role:' || v_old.role::text || '->' || p_role::text,
          to_jsonb(v_old), to_jsonb(v_new));
end;
$$;

grant execute on function public.set_user_role(uuid, public.user_role)
  to authenticated;
-- Same C1-sweep convention as list_profiles above and every function in
-- 0018_ical.sql: anon must be revoked explicitly, not left to the body's
-- own is_super_admin() check.
revoke execute on function public.set_user_role(uuid, public.user_role)
  from public;
revoke execute on function public.set_user_role(uuid, public.user_role)
  from anon;
