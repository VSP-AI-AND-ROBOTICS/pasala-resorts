-- Maintenance issue reporting. Same write-enforcement shape as
-- 0034_service_requests.sql (staff-or-above full write, assigned staff
-- status-only write, enforced by trigger since RLS's USING stays
-- permissive). New here: `priority` and an optional `photo_url` pointing
-- into the `maintenance-photos` Storage bucket (declared in
-- config.toml; this is the first Storage bucket this app has ever used).
--
-- The bucket itself is provisioned by the Storage service from
-- config.toml on `supabase start`/`db reset`, not by this migration --
-- only the policies on `storage.objects` need to be created here. A
-- customer may upload only under their own `auth.uid()` as the first path
-- segment (`{uid}/...`); staff-or-above can read anything in the bucket
-- to review a report's photo. Nobody may update or delete an uploaded
-- photo -- reports are immutable evidence, not editable, so uploading a
-- corrected photo is a new report, not a replace.
create type public.maintenance_category as enum
  ('ac', 'electrical', 'plumbing', 'water', 'furniture',
   'appliance', 'internet', 'pool_facility');

create type public.maintenance_priority as enum ('low', 'medium', 'high');

create type public.maintenance_status as enum
  ('reported', 'assigned', 'in_progress', 'fixed', 'closed');

create table public.maintenance_issues (
  id                uuid primary key default gen_random_uuid(),
  reservation_id    uuid not null references public.reservations(id) on delete cascade,
  category          public.maintenance_category not null,
  description       text not null default '',
  photo_url         text,
  priority          public.maintenance_priority not null default 'medium',
  status            public.maintenance_status not null default 'reported',
  assigned_staff_id uuid references public.profiles(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index maintenance_issues_reservation_idx on public.maintenance_issues(reservation_id);
create index maintenance_issues_assignee_idx
  on public.maintenance_issues(assigned_staff_id, status);

-- No INSERT grant -- `report_maintenance_issue` (security definer) is the
-- only writer of a new row.
grant select, update on public.maintenance_issues to authenticated;

alter table public.maintenance_issues enable row level security;

create policy maintenance_issues_read on public.maintenance_issues
  for select to authenticated
  using (
    public.is_staff_or_above()
    or exists (
      select 1 from public.reservations r
      where r.id = reservation_id and r.customer_id = auth.uid()
    )
  );

create policy maintenance_issues_update on public.maintenance_issues
  for update to authenticated using (true);

create function public.maintenance_issues_enforce_write()
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
        and old.status = 'reported' then
      new.status := 'assigned';
    end if;
    new.updated_at := clock_timestamp();
    return new;
  end if;

  if old.assigned_staff_id is distinct from auth.uid() then
    raise sqlstate '42501' using
      message = 'permission denied for table maintenance_issues',
      hint = 'you can only update issues assigned to you';
  end if;

  if new.id is distinct from old.id
      or new.reservation_id is distinct from old.reservation_id
      or new.category is distinct from old.category
      or new.description is distinct from old.description
      or new.photo_url is distinct from old.photo_url
      or new.priority is distinct from old.priority
      or new.assigned_staff_id is distinct from old.assigned_staff_id
      or new.created_at is distinct from old.created_at then
    raise sqlstate '42501' using
      message = 'permission denied for table maintenance_issues',
      hint = 'only staff can reassign or edit an issue''s details';
  end if;

  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger maintenance_issues_enforce_write_trigger
  before update on public.maintenance_issues
  for each row execute function public.maintenance_issues_enforce_write();

create function public.report_maintenance_issue(
  p_reservation_id uuid,
  p_category       public.maintenance_category,
  p_description    text default '',
  p_photo_url      text default null,
  p_priority       public.maintenance_priority default 'medium'
) returns public.maintenance_issues
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_res   public.reservations;
  v_issue public.maintenance_issues;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_res from public.reservations where id = p_reservation_id;
  if not found or v_res.customer_id is distinct from v_uid then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if v_res.status not in ('confirmed', 'checked_in') then
    raise exception 'this stay is not open for maintenance reports' using errcode = 'P0009';
  end if;

  insert into public.maintenance_issues
    (reservation_id, category, description, photo_url, priority)
  values (p_reservation_id, p_category, p_description, p_photo_url, p_priority)
  returning * into v_issue;

  return v_issue;
end;
$$;

grant execute on function public.report_maintenance_issue(
  uuid, public.maintenance_category, text, text, public.maintenance_priority) to authenticated;
revoke execute on function public.report_maintenance_issue(
  uuid, public.maintenance_category, text, text, public.maintenance_priority) from public;
revoke execute on function public.report_maintenance_issue(
  uuid, public.maintenance_category, text, text, public.maintenance_priority) from anon;

-- Storage policies: path convention is `{auth.uid()}/{filename}`.
create policy maintenance_photos_owner_upload on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'maintenance-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy maintenance_photos_owner_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'maintenance-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy maintenance_photos_staff_read on storage.objects
  for select to authenticated
  using (bucket_id = 'maintenance-photos' and public.is_staff_or_above());
