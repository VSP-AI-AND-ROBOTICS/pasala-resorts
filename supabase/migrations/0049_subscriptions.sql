-- Subscriptions and tiers (REQ-08): one plan per resort, set by hand by
-- the platform admin, with trials, a paid-until date and monthly prices
-- for MRR. Nothing here locks a resort: properties.status stays the only
-- lock. See docs/superpowers/specs/2026-09-25-subscriptions-design.md.
--
-- Errors: P0005 bad input (messages written for the admin, shown
-- verbatim), P0002 unknown resort, P0008 not the platform admin, P0020
-- not an owner/admin of the resort. No new codes.

create type public.subscription_tier as enum ('starter', 'pro', 'enterprise');
-- "Lapsed" is never stored: subscription_lapsed() works it out on read.
create type public.subscription_status as enum ('trial', 'active', 'cancelled');

-- ---------------------------------------------------------------------
-- subscription_plans: the tiers and their monthly prices. Readable by any
-- signed-in user; changed only by set_plan_price. `id` exists for the
-- audit log, whose entity_id is a non-null uuid.
create table public.subscription_plans (
  tier              public.subscription_tier primary key,
  id                uuid not null unique default gen_random_uuid(),
  name              text not null,
  monthly_price_inr numeric(12,2) not null
    constraint subscription_plans_price_not_negative check (monthly_price_inr >= 0),
  sort_order        int not null,
  updated_at        timestamptz not null default now()
);

-- Placeholder prices (spec decision 11); the platform admin edits them on
-- the console.
insert into public.subscription_plans (tier, name, monthly_price_inr, sort_order) values
  ('starter', 'Starter', 2999, 1),
  ('pro', 'Pro', 7999, 2),
  ('enterprise', 'Enterprise', 19999, 3);

alter table public.subscription_plans enable row level security;
revoke all on public.subscription_plans from anon, authenticated;
grant select on public.subscription_plans to authenticated;
create policy subscription_plans_read on public.subscription_plans
  for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- resort_subscriptions: one row per resort. A resort with no row has "No
-- plan" and counts for nothing. Readable by the resort's owners and
-- admins; written only by the security definer functions below (no write
-- grant or policy, not even for the platform admin).
create table public.resort_subscriptions (
  property_id   uuid primary key references public.properties(id) on delete cascade,
  tier          public.subscription_tier not null references public.subscription_plans(tier),
  status        public.subscription_status not null,
  trial_ends_on date,
  -- null = no end date.
  paid_through  date,
  -- Visible to the resort's owners and admins: not a private field.
  notes         text,
  updated_at    timestamptz not null default now(),
  updated_by    uuid default auth.uid(),
  constraint resort_subscriptions_trial_has_end
    check (status <> 'trial' or trial_ends_on is not null)
);
create index resort_subscriptions_tier_idx on public.resort_subscriptions (tier);

alter table public.resort_subscriptions enable row level security;
revoke all on public.resort_subscriptions from anon, authenticated;
grant select on public.resort_subscriptions to authenticated;
create policy resort_subscriptions_read on public.resort_subscriptions
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin'));

-- Every resort that exists before this migration starts on Enterprise,
-- active, with no end date (spec decision 9). supabase/seed.sql does the
-- same for the seeded resort, because the seed runs after migrations.
insert into public.resort_subscriptions (property_id, tier, status)
select id, 'enterprise', 'active' from public.properties
on conflict (property_id) do nothing;

-- Whether a subscription has run out, worked out on every read and never
-- stored. A plan is good through its end date (Asia/Kolkata, the same
-- "today" as dashboard_summary) and lapses the day after; no end date
-- never lapses; cancelled -- and a missing row, which arrives as all
-- nulls -- is never lapsed. Not a definer: it reads no table.
create function public.subscription_lapsed(
  p_status        public.subscription_status,
  p_trial_ends_on date,
  p_paid_through  date
) returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select case p_status
    when 'trial'
      then coalesce(p_trial_ends_on < (now() at time zone 'Asia/Kolkata')::date, false)
    when 'active'
      then coalesce(p_paid_through < (now() at time zone 'Asia/Kolkata')::date, false)
    else false
  end;
$$;

-- ---------------------------------------------------------------------
-- Functions. The signatures are the contract the app is built against;
-- Tasks 2 and 3 of the plan replace the bodies.

-- 0045's summary plus the resort's subscription. A resort with no
-- subscription row gets null plan columns and lapsed = false ("No plan").
drop function public.platform_resorts();

create function public.platform_resorts()
returns table(
  property_id       uuid,
  name              text,
  status            text,
  owner_emails      text[],
  created_at        timestamptz,
  bookings_30d      int,
  revenue_30d       numeric,
  bookings_365d     int,
  revenue_365d      numeric,
  plan_tier         public.subscription_tier,
  plan_name         text,
  plan_status       public.subscription_status,
  trial_ends_on     date,
  paid_through      date,
  lapsed            boolean,
  monthly_price_inr numeric,
  plan_notes        text
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
      p.id,
      p.name,
      p.status,
      coalesce((
        select array_agg(u.email::text order by u.email)
          from public.resort_members m
          join auth.users u on u.id = m.user_id
         where m.property_id = p.id and m.role = 'owner'), '{}'),
      p.created_at,
      coalesce(b.bookings_30d, 0),
      coalesce(b.revenue_30d, 0),
      coalesce(b.bookings_365d, 0),
      coalesce(b.revenue_365d, 0),
      s.tier,
      pl.name,
      s.status,
      s.trial_ends_on,
      s.paid_through,
      public.subscription_lapsed(s.status, s.trial_ends_on, s.paid_through),
      pl.monthly_price_inr,
      s.notes
    from public.properties p
    left join public.resort_subscriptions s on s.property_id = p.id
    left join public.subscription_plans pl on pl.tier = s.tier
    left join lateral (
      select
        (count(*) filter (where r.created_at >= now() - interval '30 days'))::int
          as bookings_30d,
        sum((r.quote ->> 'total')::numeric)
          filter (where r.created_at >= now() - interval '30 days') as revenue_30d,
        count(*)::int as bookings_365d,
        sum((r.quote ->> 'total')::numeric) as revenue_365d
      from public.reservations r
      where r.property_id = p.id
        and r.kind = 'booking'
        and r.status in ('confirmed','checked_in','checked_out')
        and r.created_at >= now() - interval '365 days'
    ) b on true
    order by p.created_at, p.name;
end;
$$;

-- The console's three cards (spec decisions 6 and 7). Archived resorts,
-- and resorts with no subscription row, count for nothing. MRR uses each
-- plan's current price.
create function public.platform_summary()
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
    where p.status <> 'archived';
end;
$$;

-- The resort's own plan, for its owners and admins (spec decision 8).
-- A read, so it works at a suspended resort; anyone else, including the
-- platform admin, gets P0020. Zero rows when the resort has no plan.
create function public.my_resort_subscription(p_property uuid)
returns table(
  plan_tier         public.subscription_tier,
  plan_name         text,
  plan_status       public.subscription_status,
  trial_ends_on     date,
  paid_through      date,
  lapsed            boolean,
  monthly_price_inr numeric,
  plan_notes        text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_resort_role(p_property, false, 'owner','admin');

  return query
    select s.tier, pl.name, s.status, s.trial_ends_on, s.paid_through,
           public.subscription_lapsed(s.status, s.trial_ends_on, s.paid_through),
           pl.monthly_price_inr, s.notes
      from public.resort_subscriptions s
      join public.subscription_plans pl on pl.tier = s.tier
     where s.property_id = p_property;
end;
$$;

-- Adds a tier and trial days. Dropping the two-argument version keeps
-- PostgREST and SQL callers from ever hitting an ambiguous overload. Until
-- Task 3 the body is 0045's and ignores the new parameters.
drop function public.create_resort(text, text);

create function public.create_resort(
  p_name        text,
  p_owner_email text,
  p_tier        public.subscription_tier default 'starter',
  p_trial_days  int default 30
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
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if coalesce(trim(p_name), '') = '' then
    raise exception 'name is required' using errcode = 'P0005';
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

  return v_id;
end;
$$;

create function public.set_resort_subscription(
  p_property      uuid,
  p_tier          public.subscription_tier,
  p_status        public.subscription_status,
  p_trial_ends_on date default null,
  p_paid_through  date default null,
  p_notes         text default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'set_resort_subscription is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.set_plan_price(
  p_tier              public.subscription_tier,
  p_monthly_price_inr numeric
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'set_plan_price is not implemented yet' using errcode = '0A000';
end;
$$;

revoke execute on function public.platform_resorts() from public, anon;
revoke execute on function public.platform_summary() from public, anon;
revoke execute on function public.my_resort_subscription(uuid) from public, anon;
revoke execute on function public.create_resort(text, text, public.subscription_tier, int) from public, anon;
revoke execute on function public.set_resort_subscription(uuid, public.subscription_tier, public.subscription_status, date, date, text) from public, anon;
revoke execute on function public.set_plan_price(public.subscription_tier, numeric) from public, anon;
grant execute on function public.platform_resorts() to authenticated;
grant execute on function public.platform_summary() to authenticated;
grant execute on function public.my_resort_subscription(uuid) to authenticated;
grant execute on function public.create_resort(text, text, public.subscription_tier, int) to authenticated;
grant execute on function public.set_resort_subscription(uuid, public.subscription_tier, public.subscription_status, date, date, text) to authenticated;
grant execute on function public.set_plan_price(public.subscription_tier, numeric) to authenticated;
