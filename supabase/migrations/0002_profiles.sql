create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  phone      text,
  role       public.user_role not null default 'customer',
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

grant select, insert, update, delete on public.profiles to authenticated;

-- Role lookups run inside policies, so they must bypass RLS themselves.
create function public.current_role()
returns public.user_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select role from public.profiles where id = auth.uid();
$$;

create function public.is_staff_or_above()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    public.current_role() in ('staff','admin','accountant','super_admin'),
    false);
$$;

create function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.current_role() in ('admin','super_admin'), false);
$$;

create function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.current_role() = 'super_admin', false);
$$;

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (new.id,
          new.raw_user_meta_data ->> 'full_name',
          new.raw_user_meta_data ->> 'phone');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create policy profiles_select_self on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_staff_or_above());

-- Role is deliberately excluded: the WITH CHECK clause pins it to the
-- stored value, so self-service escalation is rejected with 42501.
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and role = (select p.role from public.profiles p where p.id = auth.uid())
  );

create policy profiles_admin_select on public.profiles
  for select to authenticated
  using (public.is_admin());

create policy profiles_admin_insert on public.profiles
  for insert to authenticated
  with check (public.is_admin() and (role = 'customer' or public.is_super_admin()));

-- Role changes are super-admin only. For every other admin, the new row's
-- role must equal the role already stored for that row.
create policy profiles_admin_update on public.profiles
  for update to authenticated
  using (public.is_admin())
  with check (
    public.is_super_admin()
    or role = (select p.role from public.profiles p where p.id = profiles.id)
  );

create policy profiles_admin_delete on public.profiles
  for delete to authenticated
  using (public.is_admin() and (role = 'customer' or public.is_super_admin()));
