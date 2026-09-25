-- Resort self-listing (P10): a signed-in user applies to list a resort,
-- which starts `pending` -- hidden from guests and unbookable, but set up
-- by its new owner like an active resort -- until the platform admin
-- approves it (-> active) or rejects it with a reason (-> archived). See
-- docs/superpowers/specs/2026-09-25-p10-resort-self-listing-design.md.
--
-- Errors: P0040 listing_blocked (a listing-state refusal; the message is
-- written for the reader and shown verbatim), P0005 bad input, P0008 not
-- permitted, P0002 unknown application, P0020 not an owner/admin of the
-- resort (assert_resort_role).

-- ---------------------------------------------------------------------
-- properties: the new status, and the two fields an application adds.
-- `add column if not exists`: P11 (guest search) also wants `city`.
alter table public.properties drop constraint properties_status_check;
alter table public.properties add constraint properties_status_check
  check (status in ('pending','active','suspended','archived'));

alter table public.properties
  add column if not exists city text,
  add column if not exists contact_phone text;

-- ---------------------------------------------------------------------
-- listing_applications: one row per applied resort. Platform-owned: the
-- owner reads it but cannot write it (properties_update would let them
-- forge a submission or a decision if these were properties columns).
-- Written only by the security definer functions below.
create table public.listing_applications (
  property_id      uuid primary key references public.properties(id) on delete cascade,
  applicant_id     uuid not null references public.profiles(id) on delete cascade,
  tier             public.subscription_tier not null references public.subscription_plans(tier),
  submitted_at     timestamptz,
  decision         text
    constraint listing_applications_decision_check check (decision in ('approved','rejected')),
  decided_at       timestamptz,
  decided_by       uuid references public.profiles(id) on delete set null,
  rejection_reason text,
  created_at       timestamptz not null default now(),
  constraint listing_applications_decided_together
    check ((decision is null) = (decided_at is null)),
  constraint listing_applications_rejection_has_reason
    check (decision is distinct from 'rejected'
           or length(btrim(coalesce(rejection_reason, ''))) > 0)
);

-- "One pending application per user" (spec decision 8): at most one
-- application without a decision.
create unique index listing_applications_one_open_per_user
  on public.listing_applications (applicant_id) where decision is null;

alter table public.listing_applications enable row level security;
revoke all on public.listing_applications from anon, authenticated;
grant select on public.listing_applications to authenticated;
create policy listing_applications_read on public.listing_applications
  for select to authenticated
  using (applicant_id = auth.uid()
         or public.has_resort_role(property_id, false, 'owner','admin'));

-- ---------------------------------------------------------------------
-- outbox: a listing message belongs to a resort but to no reservation.
-- outbox_fill_property (0044) already leaves a row with no reservation
-- alone, and outbox.property_id stays not null (0045).
alter table public.outbox alter column reservation_id drop not null;

-- ---------------------------------------------------------------------
-- Functions. The signatures are the contract the app is built against;
-- Tasks 2-4 of the plan replace the bodies.

create function public.apply_for_listing(
  p_name          text,
  p_city          text,
  p_address       text,
  p_contact_phone text,
  p_description   text,
  p_tier          public.subscription_tier default 'starter'
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'apply_for_listing is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.my_listing_applications()
returns table(
  property_id      uuid,
  name             text,
  city             text,
  tier             public.subscription_tier,
  property_status  text,
  created_at       timestamptz,
  submitted_at     timestamptz,
  decision         text,
  decided_at       timestamptz,
  rejection_reason text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'my_listing_applications is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.listing_setup_status(p_property uuid)
returns table(
  property_status         text,
  submitted_at            timestamptz,
  has_photos              boolean,
  has_unit                boolean,
  has_rates               boolean,
  has_payment_settings    boolean,
  has_cancellation_policy boolean,
  has_tax_details         boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'listing_setup_status is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.submit_listing_for_review(p_property uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'submit_listing_for_review is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.platform_listing_applications()
returns table(
  property_id             uuid,
  name                    text,
  city                    text,
  address                 text,
  contact_phone           text,
  description             text,
  applicant_email         text,
  applicant_name          text,
  tier                    public.subscription_tier,
  created_at              timestamptz,
  submitted_at            timestamptz,
  has_photos              boolean,
  has_unit                boolean,
  has_rates               boolean,
  has_payment_settings    boolean,
  has_cancellation_policy boolean,
  has_tax_details         boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'platform_listing_applications is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.approve_listing(p_property uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'approve_listing is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.reject_listing(p_property uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'reject_listing is not implemented yet' using errcode = '0A000';
end;
$$;

-- ---------------------------------------------------------------------
-- A pending resort is set up by its members exactly like an active one.
-- Guests still see and book only `active` resorts: every guest policy
-- (0044) and booking function (0045) checks `status = 'active'` itself,
-- and none of them is touched here. Copied from 0043 with only the status
-- tests changed.
create or replace function public.has_resort_role(
  p_property uuid,
  p_write    boolean,
  variadic p_roles public.resort_role[]
) returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select m.role = any (p_roles)
       and (p.status in ('active','pending') or (p.status = 'suspended' and not p_write))
      from public.resort_members m
      join public.properties p on p.id = m.property_id
     where m.property_id = p_property and m.user_id = auth.uid()
  ), false);
$$;

create or replace function public.assert_resort_role(
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
  if p_write and v_status not in ('active','pending') then
    raise exception using errcode = 'P0022', message = 'resort_suspended';
  end if;
  if not p_write and v_status = 'archived' then
    raise exception using errcode = 'P0020', message = 'not_a_member';
  end if;
end;
$$;

-- 0045's set_resort_status, refusing a pending resort: Suspend or
-- Reactivate must not bypass the review (spec decision 13). Setting a
-- resort TO pending was already refused by the status list below.
create or replace function public.set_resort_status(p_property uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old text;
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if p_status is null or p_status not in ('active','suspended','archived') then
    raise exception 'status must be active, suspended or archived' using errcode = 'P0005';
  end if;

  select status into v_old from public.properties where id = p_property for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;

  if v_old = 'pending' then
    raise exception 'Approve or reject this resort instead.' using errcode = 'P0040';
  end if;

  if v_old = p_status then
    return;
  end if;

  update public.properties set status = p_status where id = p_property;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'property', p_property, 'status:' || v_old || '->' || p_status,
          jsonb_build_object('status', v_old), jsonb_build_object('status', p_status),
          p_property);
end;
$$;

-- 0049's platform_summary, leaving pending resorts out like archived ones
-- (spec decision 14). Only the final `where` changed.
create or replace function public.platform_summary()
returns table(
  subscribed_count int,
  active_count     int,
  trial_count      int,
  mrr_inr          numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  return query
    select
      (count(*) filter (where s.status <> 'cancelled'))::int,
      (count(*) filter (where s.status <> 'cancelled' and not x.lapsed))::int,
      (count(*) filter (where s.status = 'trial' and not x.lapsed))::int,
      coalesce(sum(pl.monthly_price_inr)
                 filter (where s.status = 'active' and not x.lapsed), 0)
    from public.resort_subscriptions s
    join public.properties p on p.id = s.property_id
    join public.subscription_plans pl on pl.tier = s.tier
    cross join lateral (
      select public.subscription_lapsed(s.status, s.trial_ends_on, s.paid_through) as lapsed
    ) x
    where p.status not in ('archived', 'pending');
end;
$$;

-- Internal: create_resort's slug rule (0049) -- the name lower-cased with
-- non-alphanumerics collapsed to '-', plus '-2', '-3', ... when taken. A
-- plain function, called only from apply_for_listing.
create function public.resort_slug_for(p_name text)
returns text
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_base text;
  v_slug text;
  v_n    int := 1;
begin
  v_base := trim(both '-' from regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '-', 'g'));
  if v_base = '' then
    v_base := 'resort';
  end if;
  v_slug := v_base;
  while exists (select 1 from public.properties where slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;
  return v_slug;
end;
$$;

revoke execute on function public.resort_slug_for(text) from public, anon, authenticated;

-- A signed-in user applies (spec decisions 2, 8, 9, 18, 19, 21): a pending
-- resort with the caller as owner, a 30-day trial of the chosen tier, and
-- the application. The platform admin uses create_resort instead.
create or replace function public.apply_for_listing(
  p_name          text,
  p_city          text,
  p_address       text,
  p_contact_phone text,
  p_description   text,
  p_tier          public.subscription_tier default 'starter'
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_name  text := btrim(coalesce(p_name, ''));
  v_city  text := btrim(coalesce(p_city, ''));
  v_addr  text := btrim(coalesce(p_address, ''));
  v_phone text := regexp_replace(btrim(coalesce(p_contact_phone, '')), '[ -]', '', 'g');
  v_desc  text := btrim(coalesce(p_description, ''));
  v_id    uuid;
  v_sub   public.resort_subscriptions;
begin
  if v_uid is null or public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if length(v_name) not between 2 and 80 then
    raise exception 'Enter the resort name (2 to 80 characters).' using errcode = 'P0005';
  end if;
  if length(v_city) not between 2 and 60 then
    raise exception 'Enter the city (2 to 60 characters).' using errcode = 'P0005';
  end if;
  if length(v_addr) not between 5 and 300 then
    raise exception 'Enter the full address (5 to 300 characters).' using errcode = 'P0005';
  end if;
  if v_phone !~ '^\+?[0-9]{10,13}$' then
    raise exception 'Enter a contact phone number, e.g. +91 98765 43210.' using errcode = 'P0005';
  end if;
  if length(v_desc) not between 20 and 500 then
    raise exception 'Describe the resort in 20 to 500 characters.' using errcode = 'P0005';
  end if;
  if p_tier is null then
    raise exception 'Choose a plan.' using errcode = 'P0005';
  end if;

  -- Serialise this user's applications, so two taps at once give P0040
  -- here rather than a unique violation from the partial index.
  perform pg_advisory_xact_lock(hashtext('listing:' || v_uid::text));
  if exists (select 1 from public.listing_applications
              where applicant_id = v_uid and decision is null) then
    raise exception 'You already have a resort waiting for review.' using errcode = 'P0040';
  end if;

  insert into public.properties (name, slug, status, city, address, contact_phone, description)
  values (v_name, public.resort_slug_for(v_name), 'pending', v_city, v_addr, v_phone, v_desc)
  returning id into v_id;

  insert into public.resort_members (property_id, user_id, role)
  values (v_id, v_uid, 'owner');

  insert into public.resort_subscriptions (property_id, tier, status, trial_ends_on)
  values (v_id, p_tier, 'trial', (now() at time zone 'Asia/Kolkata')::date + 30)
  returning * into v_sub;

  insert into public.listing_applications (property_id, applicant_id, tier)
  values (v_id, v_uid, p_tier);

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values
    (v_uid, 'listing', v_id, 'listing:apply', null,
     jsonb_build_object('name', v_name, 'city', v_city, 'tier', p_tier), v_id),
    (v_uid, 'subscription', v_id, 'subscription:create', null, to_jsonb(v_sub), v_id);

  return v_id;
end;
$$;

-- The caller's own applications, decided ones too, newest first. Reads by
-- applicant, not by membership: a rejected resort is archived and no
-- longer opens through the membership, but its reason must still show
-- (spec decision 15).
create or replace function public.my_listing_applications()
returns table(
  property_id      uuid,
  name             text,
  city             text,
  tier             public.subscription_tier,
  property_status  text,
  created_at       timestamptz,
  submitted_at     timestamptz,
  decision         text,
  decided_at       timestamptz,
  rejection_reason text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  return query
    select a.property_id, p.name, p.city, a.tier, p.status, a.created_at,
           a.submitted_at, a.decision, a.decided_at, a.rejection_reason
      from public.listing_applications a
      join public.properties p on p.id = a.property_id
     where a.applicant_id = auth.uid()
     order by a.created_at desc, a.property_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Listing photos (spec decision 17): a public bucket, objects at
-- `{property_id}/{file}`. The resort's owners and admins write (at an
-- active or pending resort) and read; anyone may fetch a public URL.
-- supabase/config.toml declares the bucket for local stacks too.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('property-photos', 'property-photos', true, 10485760,
        array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do nothing;

create policy property_photos_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'property-photos'
              and exists (select 1 from public.properties p
                           where p.id::text = (storage.foldername(objects.name))[1]
                             and public.has_resort_role(p.id, true, 'owner','admin')));

create policy property_photos_read on storage.objects
  for select to authenticated
  using (bucket_id = 'property-photos'
         and exists (select 1 from public.properties p
                      where p.id::text = (storage.foldername(objects.name))[1]
                        and public.has_resort_role(p.id, false, 'owner','admin')));

create policy property_photos_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'property-photos'
         and exists (select 1 from public.properties p
                      where p.id::text = (storage.foldername(objects.name))[1]
                        and public.has_resort_role(p.id, true, 'owner','admin')));

revoke execute on function public.apply_for_listing(text, text, text, text, text, public.subscription_tier) from public, anon;
revoke execute on function public.my_listing_applications() from public, anon;
revoke execute on function public.listing_setup_status(uuid) from public, anon;
revoke execute on function public.submit_listing_for_review(uuid) from public, anon;
revoke execute on function public.platform_listing_applications() from public, anon;
revoke execute on function public.approve_listing(uuid) from public, anon;
revoke execute on function public.reject_listing(uuid, text) from public, anon;
grant execute on function public.apply_for_listing(text, text, text, text, text, public.subscription_tier) to authenticated;
grant execute on function public.my_listing_applications() to authenticated;
grant execute on function public.listing_setup_status(uuid) to authenticated;
grant execute on function public.submit_listing_for_review(uuid) to authenticated;
grant execute on function public.platform_listing_applications() to authenticated;
grant execute on function public.approve_listing(uuid) to authenticated;
grant execute on function public.reject_listing(uuid, text) to authenticated;
