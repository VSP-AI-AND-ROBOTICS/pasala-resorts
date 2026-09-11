-- The reservation lifecycle gains two states past `confirmed`:
-- `checked_in` (the guest has arrived and reception has verified the
-- booking) and `checked_out` (the stay is over and the final bill is
-- settled). Everything before this migration -- `create_hold`,
-- `confirm_booking`, `cancel_booking`, the exclusion constraint, RLS -- is
-- untouched; a `confirmed` reservation behaves exactly as it always has
-- until something new (0037's `check_in_booking`) explicitly moves it
-- forward. See docs/superpowers/specs/2026-09-01-guest-stay-experience-design.md.
--
-- A new enum value cannot be referenced in the same transaction that adds
-- it, so this migration does nothing else -- every RPC that uses
-- 'checked_in'/'checked_out' lives in a later migration file (each file is
-- its own transaction).
alter type public.reservation_status add value 'checked_in' after 'confirmed';
alter type public.reservation_status add value 'checked_out' after 'checked_in';

alter table public.reservations
  add column checked_in_at timestamptz,
  add column checked_out_at timestamptz,
  add constraint reservations_checkout_after_checkin
    check (checked_out_at is null or checked_in_at is null or checked_out_at > checked_in_at);
