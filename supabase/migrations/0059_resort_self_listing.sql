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

-- ---------------------------------------------------------------------
-- Internal: the six checklist items (spec decision 10), computed on every
-- read and never stored. A plain function, called only from the definers
-- in this file.
create function public.listing_setup_flags(p_property uuid)
returns table(
  has_photos              boolean,
  has_unit                boolean,
  has_rates               boolean,
  has_payment_settings    boolean,
  has_cancellation_policy boolean,
  has_tax_details         boolean
)
language sql
stable
set search_path = public, pg_temp
as $$
  select
    cardinality(p.images) > 0,
    exists (select 1 from public.units u where u.property_id = p.id and u.is_active),
    exists (select 1 from public.units u where u.property_id = p.id and u.is_active)
      and not exists (
        select 1 from public.units u
         where u.property_id = p.id and u.is_active
           and not exists (select 1 from public.rate_rules r
                            where r.unit_id = u.id and r.kind in ('base','weekend'))),
    cardinality(p.payment_display_methods) > 0,
    exists (select 1 from public.refund_rules rr where rr.property_id = p.id),
    coalesce(upper(btrim(p.gstin)) ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$', false)
  from public.properties p
  where p.id = p_property;
$$;

revoke execute on function public.listing_setup_flags(uuid) from public, anon, authenticated;

-- Internal: queues one platform-to-owner listing message (spec decision
-- 16). The recipient is the applicant's sign-in email (or phone for a
-- non-email template); the resort's guest-notification toggles do not
-- apply. Silently does nothing without a platform template of that name.
create function public.enqueue_listing_message(p_property uuid, p_template text)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_tpl       public.outbox_templates;
  v_app       public.listing_applications;
  v_property  public.properties;
  v_profile   public.profiles;
  v_email     text;
  v_trial     date;
  v_recipient text;
  v_ctx       jsonb;
  v_subject   text;
  v_body      text;
  v_key       text;
begin
  select * into v_tpl from public.outbox_templates
   where name = p_template and property_id is null;
  if not found then
    return;
  end if;

  select * into v_app from public.listing_applications where property_id = p_property;
  if not found then
    return;
  end if;

  select * into v_property from public.properties where id = p_property;
  select * into v_profile from public.profiles where id = v_app.applicant_id;
  select email into v_email from auth.users where id = v_app.applicant_id;
  select trial_ends_on into v_trial from public.resort_subscriptions where property_id = p_property;

  v_recipient := case v_tpl.channel
    when 'email' then nullif(btrim(coalesce(v_email, '')), '')
    else nullif(btrim(coalesce(v_profile.phone, '')), '')
  end;

  if v_recipient is null then
    insert into public.outbox (property_id, channel, recipient, template, status, last_error)
    values (p_property, v_tpl.channel,
            case v_tpl.channel when 'email' then 'no email on file' else 'no phone on file' end,
            p_template, 'skipped',
            format('cannot deliver via %s: applicant %s has no %s on file',
                   v_tpl.channel, v_app.applicant_id,
                   case v_tpl.channel when 'email' then 'email address' else 'phone number' end));
    return;
  end if;

  -- Every value is coalesced: replace() returns NULL if any argument is
  -- NULL, which would blank the whole message (see 0017).
  v_ctx := jsonb_build_object(
    'owner_name',    coalesce(nullif(btrim(v_profile.full_name), ''), 'there'),
    'property_name', coalesce(v_property.name, 'your resort'),
    'trial_ends_on', coalesce(to_char(v_trial, 'DD Mon YYYY'), ''),
    'reason',        coalesce(v_app.rejection_reason, ''));

  v_subject := v_tpl.subject_template;
  v_body    := v_tpl.body_template;
  for v_key in select jsonb_object_keys(v_ctx) loop
    if v_subject is not null then
      v_subject := replace(v_subject, '{{' || v_key || '}}', v_ctx ->> v_key);
    end if;
    v_body := replace(v_body, '{{' || v_key || '}}', v_ctx ->> v_key);
  end loop;

  insert into public.outbox (property_id, channel, recipient, template, subject, body, status)
  values (p_property, v_tpl.channel, v_recipient, p_template, v_subject, v_body, 'pending');
end;
$$;

revoke execute on function public.enqueue_listing_message(uuid, text) from public, anon, authenticated;

-- Platform default templates (property_id null) for the three listing
-- events. Email only; P7's dispatcher delivers them.
insert into public.outbox_templates (name, event, channel, subject_template, body_template, property_id)
values
  ('listing_submitted', 'listing_submitted', 'email',
   'We are reviewing {{property_name}}',
   'Hi {{owner_name}}, thank you for listing {{property_name}} on ResortHub. '
   'Our team is reviewing it and will email you when it is decided. You can '
   'keep editing your setup in the meantime.',
   null),
  ('listing_approved', 'listing_approved', 'email',
   '{{property_name}} is live on ResortHub',
   'Hi {{owner_name}}, {{property_name}} has been approved. Guests can now '
   'find and book it. Your free trial runs until {{trial_ends_on}}.',
   null),
  ('listing_rejected', 'listing_rejected', 'email',
   'About your ResortHub listing for {{property_name}}',
   'Hi {{owner_name}}, we could not approve {{property_name}} for listing. '
   'Reason: {{reason}}. You can apply again from the ResortHub app.',
   null)
on conflict (name) do nothing;

-- The checklist of one resort, for its owners and admins (a read, so it
-- also answers at a suspended resort).
create or replace function public.listing_setup_status(p_property uuid)
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
  perform public.assert_resort_role(p_property, false, 'owner','admin');

  return query
    select p.status, a.submitted_at, f.has_photos, f.has_unit, f.has_rates,
           f.has_payment_settings, f.has_cancellation_policy, f.has_tax_details
      from public.properties p
      left join public.listing_applications a on a.property_id = p.id
      cross join lateral public.listing_setup_flags(p.id) f
     where p.id = p_property;
end;
$$;

-- The owner submits a complete checklist (spec decision 11). Submitting
-- again is a no-op; anything but an undecided application of a pending
-- resort is P0040.
create or replace function public.submit_listing_for_review(p_property uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_app    public.listing_applications;
  v_status text;
  v_flags  record;
begin
  perform public.assert_resort_role(p_property, true, 'owner');

  select * into v_app from public.listing_applications
   where property_id = p_property
   for update;
  select status into v_status from public.properties where id = p_property;
  if v_app.property_id is null or v_app.decision is not null or v_status <> 'pending' then
    raise exception 'This resort is not waiting for review.' using errcode = 'P0040';
  end if;

  if v_app.submitted_at is not null then
    return;
  end if;

  select * into v_flags from public.listing_setup_flags(p_property);
  if not (v_flags.has_photos and v_flags.has_unit and v_flags.has_rates
          and v_flags.has_payment_settings and v_flags.has_cancellation_policy
          and v_flags.has_tax_details) then
    raise exception 'Finish the setup checklist before submitting.' using errcode = 'P0040';
  end if;

  update public.listing_applications
     set submitted_at = now()
   where property_id = p_property;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'listing', p_property, 'listing:submit', null,
          jsonb_build_object('submitted_at', now()), p_property);

  perform public.enqueue_listing_message(p_property, 'listing_submitted');
end;
$$;

-- ---------------------------------------------------------------------
-- 0056's claim_outbox_batch, able to claim a listing message. Such a row
-- has no reservation (its subject and body are rendered when queued), so
-- it gets no reservation variables instead of raising from
-- outbox_template_context -- which would abort the whole batch and stall
-- every email. It is also exempt from the resort's guest-notification
-- toggles (spec decision 16). Only those two statements changed.
create or replace function public.claim_outbox_batch(p_limit int default 25)
returns table (id uuid, property_id uuid, reservation_id uuid,
               channel public.outbox_channel, recipient text, template text,
               subject text, body text, attempts int, vars jsonb)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_limit   int := least(greatest(coalesce(p_limit, 25), 1), 200);
  v_row     public.outbox;
  v_enabled boolean;
begin
  for v_row in
    select o.*
      from public.outbox o
     where o.status = 'pending'
       and o.channel in ('email', 'sms')
       and o.next_attempt_at <= now()
     order by o.next_attempt_at, o.created_at, o.id
     limit v_limit
     for update skip locked
  loop
    -- A listing message (no reservation) goes to the resort's owner from
    -- the platform: the resort's guest-notification toggles do not apply.
    v_enabled := v_row.reservation_id is null or coalesce(
      (select case v_row.channel
                when 'email' then ns.email_enabled
                when 'sms'   then ns.sms_enabled
              end
         from public.notification_settings ns
        where ns.property_id = v_row.property_id),
      true);

    if not v_enabled then
      update public.outbox o
         set status = 'skipped',
             last_error = format('%s notifications are disabled in this property''s settings',
                                 v_row.channel)
       where o.id = v_row.id;
      continue;
    end if;

    if v_row.attempts >= 5 then
      update public.outbox o
         set status = 'failed',
             last_error = coalesce(v_row.last_error, 'gave up after 5 attempts')
       where o.id = v_row.id;
      continue;
    end if;

    update public.outbox o
       set attempts        = o.attempts + 1,
           last_attempt_at = now(),
           next_attempt_at = now() + interval '5 minutes'
     where o.id = v_row.id;

    id             := v_row.id;
    property_id    := v_row.property_id;
    reservation_id := v_row.reservation_id;
    channel        := v_row.channel;
    recipient      := v_row.recipient;
    template       := v_row.template;
    subject        := v_row.subject;
    body           := v_row.body;
    attempts       := v_row.attempts + 1;
    vars           := case
                        when v_row.reservation_id is null then '{}'::jsonb
                        else public.outbox_template_context(v_row.reservation_id)
                               - 'customer_email' - 'customer_phone'
                      end;
    return next;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- The console's queue (spec decision 25): undecided applications, the
-- submitted ones first (oldest submission first), then the rest by when
-- they applied. Platform admin only; no guest data.
create or replace function public.platform_listing_applications()
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
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  return query
    select a.property_id, p.name, p.city, p.address, p.contact_phone, p.description,
           u.email::text, pr.full_name, a.tier, a.created_at, a.submitted_at,
           f.has_photos, f.has_unit, f.has_rates, f.has_payment_settings,
           f.has_cancellation_policy, f.has_tax_details
      from public.listing_applications a
      join public.properties p on p.id = a.property_id
      left join auth.users u on u.id = a.applicant_id
      left join public.profiles pr on pr.id = a.applicant_id
      cross join lateral public.listing_setup_flags(a.property_id) f
     where a.decision is null
     order by a.submitted_at nulls last, a.created_at, p.name, a.property_id;
end;
$$;

-- Approve (spec decisions 4, 9, 12): only a submitted application whose
-- checklist is still complete. The resort goes live, a trial restarts
-- from today, and the owner is told.
create or replace function public.approve_listing(p_property uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_app   public.listing_applications;
  v_old   public.resort_subscriptions;
  v_new   public.resort_subscriptions;
  v_flags record;
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  select * into v_app from public.listing_applications
   where property_id = p_property
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;
  perform 1 from public.properties where id = p_property for update;

  if v_app.decision is not null then
    raise exception 'This application has already been decided.' using errcode = 'P0040';
  end if;
  if v_app.submitted_at is null then
    raise exception 'This resort has not been submitted for review yet.' using errcode = 'P0040';
  end if;

  select * into v_flags from public.listing_setup_flags(p_property);
  if not (v_flags.has_photos and v_flags.has_unit and v_flags.has_rates
          and v_flags.has_payment_settings and v_flags.has_cancellation_policy
          and v_flags.has_tax_details) then
    raise exception 'The setup checklist is no longer complete.' using errcode = 'P0040';
  end if;

  update public.properties set status = 'active' where id = p_property;
  update public.listing_applications
     set decision = 'approved', decided_at = now(), decided_by = auth.uid()
   where property_id = p_property;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values
    (auth.uid(), 'property', p_property, 'status:pending->active',
     jsonb_build_object('status', 'pending'), jsonb_build_object('status', 'active'), p_property),
    (auth.uid(), 'listing', p_property, 'listing:approve', null,
     jsonb_build_object('decision', 'approved'), p_property);

  -- Review time does not eat the trial.
  select * into v_old from public.resort_subscriptions
   where property_id = p_property
   for update;
  if v_old.status = 'trial' then
    update public.resort_subscriptions
       set trial_ends_on = (now() at time zone 'Asia/Kolkata')::date + 30,
           updated_at = now(),
           updated_by = auth.uid()
     where property_id = p_property
    returning * into v_new;

    insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
    values (auth.uid(), 'subscription', p_property, 'subscription:trial-restart',
            to_jsonb(v_old), to_jsonb(v_new), p_property);
  end if;

  perform public.enqueue_listing_message(p_property, 'listing_approved');
end;
$$;

-- Reject with a reason (spec decisions 4, 12, 15): any time before a
-- decision. The resort is archived; the applicant sees the reason through
-- my_listing_applications and the email.
create or replace function public.reject_listing(p_property uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reason text := btrim(coalesce(p_reason, ''));
  v_app    public.listing_applications;
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if length(v_reason) not between 5 and 500 then
    raise exception 'Give the owner a reason (5 to 500 characters).' using errcode = 'P0005';
  end if;

  select * into v_app from public.listing_applications
   where property_id = p_property
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;
  perform 1 from public.properties where id = p_property for update;

  if v_app.decision is not null then
    raise exception 'This application has already been decided.' using errcode = 'P0040';
  end if;

  update public.properties set status = 'archived' where id = p_property;
  update public.listing_applications
     set decision = 'rejected', decided_at = now(), decided_by = auth.uid(),
         rejection_reason = v_reason
   where property_id = p_property;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values
    (auth.uid(), 'property', p_property, 'status:pending->archived',
     jsonb_build_object('status', 'pending'), jsonb_build_object('status', 'archived'), p_property),
    (auth.uid(), 'listing', p_property, 'listing:reject', null,
     jsonb_build_object('decision', 'rejected', 'reason', v_reason), p_property);

  perform public.enqueue_listing_message(p_property, 'listing_rejected');
end;
$$;

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
