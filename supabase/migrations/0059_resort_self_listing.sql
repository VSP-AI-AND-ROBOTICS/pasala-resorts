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
