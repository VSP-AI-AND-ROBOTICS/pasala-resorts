-- 0063_fifteen_day_trial.sql
-- Updates the default trial period for new resorts and listings across the
-- three tiers (Starter, Pro, Enterprise) to a 15-day free trial.

-- 1. Listing application creates a 15-day free trial on the chosen tier.
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
  v_uid     uuid := auth.uid();
  v_name    text := coalesce(trim(p_name), '');
  v_city    text := coalesce(trim(p_city), '');
  v_addr    text := coalesce(trim(p_address), '');
  v_phone   text := coalesce(trim(p_contact_phone), '');
  v_desc    text := coalesce(trim(p_description), '');
  v_id      uuid;
  v_sub     public.resort_subscriptions;
  v_attempt int := 0;
  v_constr  text;
begin
  if v_uid is null then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;
  if public.is_platform_admin() then
    raise exception 'Platform admins cannot list a resort.' using errcode = 'P0008';
  end if;

  if length(v_name) not between 2 and 120 then
    raise exception 'Enter a resort name between 2 and 120 characters.' using errcode = 'P0005';
  end if;
  if length(v_city) not between 2 and 80 then
    raise exception 'Enter a city between 2 and 80 characters.' using errcode = 'P0005';
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

  perform pg_advisory_xact_lock(hashtext('listing:' || v_uid::text));
  if exists (select 1 from public.listing_applications
              where applicant_id = v_uid and decision is null) then
    raise exception 'You already have a resort waiting for review.' using errcode = 'P0040';
  end if;

  loop
    begin
      insert into public.properties (name, slug, status, city, address, contact_phone, description)
      values (v_name, public.resort_slug_for(v_name), 'pending', v_city, v_addr, v_phone, v_desc)
      returning id into v_id;
      exit;
    exception when unique_violation then
      get stacked diagnostics v_constr = constraint_name;
      v_attempt := v_attempt + 1;
      if v_constr is distinct from 'properties_slug_key' or v_attempt >= 5 then
        raise;
      end if;
    end;
  end loop;

  insert into public.resort_members (property_id, user_id, role)
  values (v_id, v_uid, 'owner');

  -- 15-day free trial on the chosen tier (Starter, Pro, Enterprise)
  insert into public.resort_subscriptions (property_id, tier, status, trial_ends_on)
  values (v_id, p_tier, 'trial', (now() at time zone 'Asia/Kolkata')::date + 15)
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

revoke execute on function public.apply_for_listing(text, text, text, text, text, public.subscription_tier) from public, anon;
grant execute on function public.apply_for_listing(text, text, text, text, text, public.subscription_tier) to authenticated;

-- 2. Listing approval restarts a 15-day trial from approval date.
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

  -- Review time does not eat the trial: 15-day trial restarts from today
  select * into v_old from public.resort_subscriptions
   where property_id = p_property
   for update;
  if v_old.status = 'trial' then
    update public.resort_subscriptions
       set trial_ends_on = (now() at time zone 'Asia/Kolkata')::date + 15,
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

revoke execute on function public.approve_listing(uuid) from public, anon;
grant execute on function public.approve_listing(uuid) to authenticated;

-- 3. create_resort: drop and recreate to update default p_trial_days to 15.
drop function if exists public.create_resort(text, text, public.subscription_tier, int);

create function public.create_resort(
  p_name        text,
  p_owner_email text,
  p_tier        public.subscription_tier default 'starter',
  p_trial_days  int default 15
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_owner uuid;
  v_base  text;
  v_slug  text;
  v_n     int := 1;
  v_id    uuid;
  v_sub   public.resort_subscriptions;
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if coalesce(trim(p_name), '') = '' then
    raise exception 'name is required' using errcode = 'P0005';
  end if;

  if p_tier is null then
    raise exception 'Choose a plan.' using errcode = 'P0005';
  end if;

  if p_trial_days is null or p_trial_days < 0 or p_trial_days > 365 then
    raise exception 'A trial is 0 to 365 days.' using errcode = 'P0005';
  end if;

  select id into v_owner from auth.users
   where lower(email) = lower(trim(p_owner_email));
  if v_owner is null then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;

  v_base := trim(both '-' from regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '-', 'g'));
  if v_base = '' then
    v_base := 'resort';
  end if;
  v_slug := v_base;
  while exists (select 1 from public.properties where slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;

  insert into public.properties (name, slug)
  values (trim(p_name), v_slug)
  returning id into v_id;

  insert into public.resort_members (property_id, user_id, role)
  values (v_id, v_owner, 'owner');

  insert into public.resort_subscriptions (property_id, tier, status, trial_ends_on)
  values (v_id,
          p_tier,
          (case when p_trial_days > 0 then 'trial' else 'active' end)::public.subscription_status,
          case when p_trial_days > 0
               then (now() at time zone 'Asia/Kolkata')::date + p_trial_days end)
  returning * into v_sub;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'subscription', v_id, 'subscription:create',
          null, to_jsonb(v_sub), v_id);

  return v_id;
end;
$$;

revoke execute on function public.create_resort(text, text, public.subscription_tier, int) from public, anon;
grant execute on function public.create_resort(text, text, public.subscription_tier, int) to authenticated;

-- 4. Allow modern image formats (avif, heic, heif, gif) in storage buckets.
update storage.buckets
   set allowed_mime_types = array['image/png', 'image/jpeg', 'image/webp', 'image/avif', 'image/gif', 'image/heic', 'image/heif']
 where id in ('property-photos', 'maintenance-photos');

