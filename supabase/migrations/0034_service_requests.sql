-- In-stay service requests (cleaning, water, extra bed, ...). Mirrors
-- 0024_tasks.sql's write-enforcement shape: RLS's USING clause stays
-- permissive enough to admit both staff-or-above (full write) and the
-- assigned staff member (status-only write) on a row they can see;
-- tasks_enforce_write's trigger is what actually restricts what each side
-- may change. The one addition over tasks: setting assigned_staff_id from
-- null bumps status to 'assigned' automatically, since a request always
-- starts unassigned and 'requested' the moment `create_service_request`
-- inserts it -- there is no separate "assign" RPC, staff just do a plain
-- UPDATE, so the trigger keeps status and assignment in sync for them.
create type public.service_request_category as enum
  ('cleaning', 'water', 'extra_bed', 'food_assistance', 'general_assistance');

create type public.service_request_status as enum
  ('requested', 'assigned', 'in_progress', 'completed');

create table public.service_requests (
  id                uuid primary key default gen_random_uuid(),
  reservation_id    uuid not null references public.reservations(id) on delete cascade,
  category          public.service_request_category not null,
  description        text not null default '',
  status            public.service_request_status not null default 'requested',
  assigned_staff_id uuid references public.profiles(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index service_requests_reservation_idx on public.service_requests(reservation_id);
create index service_requests_assignee_idx on public.service_requests(assigned_staff_id, status);

-- No INSERT grant -- `create_service_request` (security definer) is the
-- only writer of a new row.
grant select, update on public.service_requests to authenticated;

alter table public.service_requests enable row level security;

create policy service_requests_read on public.service_requests
  for select to authenticated
  using (
    public.is_staff_or_above()
    or exists (
      select 1 from public.reservations r
      where r.id = reservation_id and r.customer_id = auth.uid()
    )
  );

-- `using (true)`, same reasoning as tasks_update: an assigned staff member
-- can see their own row via staff_or_above, so USING stays permissive and
-- the trigger below raises an explicit error rather than silently
-- affecting zero rows.
create policy service_requests_update on public.service_requests
  for update to authenticated using (true);

create function public.service_requests_enforce_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if public.is_staff_or_above() then
    if new.assigned_staff_id is distinct from old.assigned_staff_id
        and old.assigned_staff_id is null
        and new.assigned_staff_id is not null
        and old.status = 'requested' then
      new.status := 'assigned';
    end if;
    new.updated_at := clock_timestamp();
    return new;
  end if;

  if old.assigned_staff_id is distinct from auth.uid() then
    raise sqlstate '42501' using
      message = 'permission denied for table service_requests',
      hint = 'you can only update requests assigned to you';
  end if;

  if new.id is distinct from old.id
      or new.reservation_id is distinct from old.reservation_id
      or new.category is distinct from old.category
      or new.description is distinct from old.description
      or new.assigned_staff_id is distinct from old.assigned_staff_id
      or new.created_at is distinct from old.created_at then
    raise sqlstate '42501' using
      message = 'permission denied for table service_requests',
      hint = 'only staff can reassign or edit a request''s details';
  end if;

  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger service_requests_enforce_write_trigger
  before update on public.service_requests
  for each row execute function public.service_requests_enforce_write();

create function public.create_service_request(
  p_reservation_id uuid,
  p_category       public.service_request_category,
  p_description    text default ''
) returns public.service_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_res public.reservations;
  v_req public.service_requests;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_res from public.reservations where id = p_reservation_id;
  if not found or v_res.customer_id is distinct from v_uid then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if v_res.status not in ('confirmed', 'checked_in') then
    raise exception 'this stay is not open for service requests' using errcode = 'P0009';
  end if;

  insert into public.service_requests (reservation_id, category, description)
  values (p_reservation_id, p_category, p_description)
  returning * into v_req;

  return v_req;
end;
$$;

grant execute on function public.create_service_request(
  uuid, public.service_request_category, text) to authenticated;
revoke execute on function public.create_service_request(
  uuid, public.service_request_category, text) from public;
revoke execute on function public.create_service_request(
  uuid, public.service_request_category, text) from anon;
