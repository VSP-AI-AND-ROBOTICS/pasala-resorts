-- The refund policy engine. `refund_rules` is a per-property ladder: the
-- rule that applies to a given cancellation is the one with the greatest
-- `min_days_before` that does not exceed the actual number of days between
-- the cancellation and check-in, computed in the PROPERTY's timezone, not
-- the session's. A cancellation at 01:00 IST is still the previous day in
-- UTC -- casting under the wrong timezone would shift a booking across a
-- tier and change what the customer is owed, exactly the trap
-- `report_revenue`/`report_occupancy` already had to guard against (see
-- migration 0015's `at time zone p.timezone` casts); `compute_refund` below
-- uses the same pattern.

create table public.refund_rules (
  id              uuid primary key default gen_random_uuid(),
  property_id     uuid not null references public.properties(id) on delete cascade,
  min_days_before int not null check (min_days_before >= 0),
  refund_pct      numeric(5,2) not null
    check (refund_pct >= 0 and refund_pct <= 100),
  created_at      timestamptz not null default now(),
  -- Two rules for the same property at the same threshold would make "the
  -- matching rule" ambiguous -- `compute_refund`'s `order by ... limit 1`
  -- would then depend on row order rather than being well-defined.
  unique (property_id, min_days_before)
);

create index refund_rules_property_idx on public.refund_rules(property_id);

grant select on public.refund_rules to authenticated;
grant insert, update, delete on public.refund_rules to authenticated;

alter table public.refund_rules enable row level security;

create policy refund_rules_read on public.refund_rules
  for select to authenticated
  using (public.is_staff_or_above());

create policy refund_rules_admin_write on public.refund_rules
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- The reservation records what it was actually refunded, alongside the
-- percentage that produced it, so a later report or dispute never has to
-- re-derive the figure from a refund_rules row that may since have changed.
alter table public.reservations
  add column refund_pct numeric(5,2)
    check (refund_pct is null or (refund_pct >= 0 and refund_pct <= 100)),
  add column refund_amount numeric(12,2)
    check (refund_amount is null or refund_amount >= 0);

-- Computes what a reservation would be refunded if cancelled right now.
-- Returns `{days_before, refund_pct, refund_amount, rule_id}` -- a property
-- with no matching rule (including one with no rules at all) yields a ZERO
-- refund with a null rule_id, never an error and never NULL arithmetic:
-- `v_pct`/`v_amount` start at 0 and are only overwritten once a matching
-- rule is actually found.
create function public.compute_refund(p_reservation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid         uuid := auth.uid();
  v_row         public.reservations;
  v_property_id uuid;
  v_tz          text;
  v_total       numeric;
  v_days_before int;
  v_rule        public.refund_rules;
  v_pct         numeric(5,2) := 0;
  v_amount      numeric(12,2) := 0;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations where id = p_reservation_id;
  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  -- Same ownership rule as `cancel_booking`: the owning customer, or an
  -- admin. A refund preview is exactly as sensitive as the cancellation it
  -- previews.
  if v_row.customer_id is distinct from v_uid and not public.is_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  select u.property_id, p.timezone into v_property_id, v_tz
  from public.units u join public.properties p on p.id = u.property_id
  where u.id = v_row.unit_id;

  -- Property-local calendar dates, not raw elapsed hours -- the same
  -- `at time zone v_tz` pattern `report_revenue`/`report_occupancy` use, so
  -- a cancellation just after property-local midnight isn't shifted onto
  -- the wrong side of UTC midnight and into the wrong tier.
  v_days_before := (lower(v_row.period) at time zone v_tz)::date
                  - (now() at time zone v_tz)::date;

  select * into v_rule
  from public.refund_rules
  where property_id = v_property_id
    and min_days_before <= v_days_before
  order by min_days_before desc
  limit 1;

  -- `v_row.quote` is NULL for an admin block (no customer, no price) --
  -- coalesce keeps the arithmetic below well-defined rather than NULL.
  v_total := coalesce((v_row.quote ->> 'total')::numeric, 0);

  if v_rule.id is not null then
    v_pct    := v_rule.refund_pct;
    v_amount := round(v_total * v_pct / 100, 2);
  end if;

  return jsonb_build_object(
    'days_before',   v_days_before,
    'refund_pct',    v_pct,
    'refund_amount', v_amount,
    'rule_id',       v_rule.id
  );
end;
$$;

grant execute on function public.compute_refund to authenticated;
-- C1 sweep: close the default PUBLIC EXECUTE gap consistently -- see
-- 0018_ical.sql's header comment on `ical_import_event` for the full
-- reasoning. `compute_refund` already requires `auth.uid()` in its body,
-- so this is defense-in-depth, not the primary fix for this function, but
-- applying it everywhere is what makes the primary fix (0018) actually
-- trustworthy as a pattern rather than a one-off.
revoke execute on function public.compute_refund from public;
revoke execute on function public.compute_refund from anon;

-- `cancel_booking` now records what the customer is owed at the moment of
-- cancellation -- `refund_pct`/`refund_amount` -- rather than only freeing
-- the dates. The idempotent early return for an already-cancelled
-- reservation is unchanged and deliberately skips recomputing: a second
-- call happens later in time, when `compute_refund` would legitimately
-- produce a DIFFERENT (lower) figure, and overwriting the original
-- cancellation-time figure with that would silently understate what the
-- customer was actually promised.
create or replace function public.cancel_booking(
  p_reservation_id uuid,
  p_reason         text
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_row    public.reservations;
  v_refund jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  if v_row.customer_id is distinct from v_uid and not public.is_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if v_row.status = 'cancelled' then
    return v_row;
  end if;

  v_refund := public.compute_refund(p_reservation_id);

  update public.reservations
     set status        = 'cancelled',
         cancel_reason  = p_reason,
         cancelled_at   = now(),
         refund_pct     = (v_refund ->> 'refund_pct')::numeric,
         refund_amount  = (v_refund ->> 'refund_amount')::numeric
   where id = p_reservation_id
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.cancel_booking to authenticated;
-- C1 sweep: same defense-in-depth as `compute_refund` above. `cancel_booking`
-- is redefined again in migration 0016 (same signature -- `create or
-- replace` there does not reset this ACL), which repeats this revoke too,
-- matching the same belt-and-suspenders convention this branch already
-- uses for `release_expired_holds` (defined in 0007, revoked there,
-- redefined and re-revoked again in 0016).
revoke execute on function public.cancel_booking from public;
revoke execute on function public.cancel_booking from anon;

-- Seed the default ladder -- full refund beyond 7 days out, 50% within 7
-- days, nothing within 48 hours -- for every property that already exists
-- at the time this migration runs. In this project's local dev/test
-- databases that set is empty (the demo properties in `seed.sql` are
-- inserted AFTER every migration, including this one, as part of the same
-- `db reset`), so this insert is a harmless no-op here; against a real
-- deployment with existing properties it backfills every one of them so
-- refunds don't silently fall back to the zero-rule case the moment this
-- feature ships.
insert into public.refund_rules (property_id, min_days_before, refund_pct)
select id, tier.min_days_before, tier.refund_pct
from public.properties
cross join (values (0, 0), (2, 50), (8, 100)) as tier(min_days_before, refund_pct);
