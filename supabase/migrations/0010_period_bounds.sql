-- I2 belt-and-braces: `build_period` now raises P0005 on a NULL check-in or
-- check-out date, closing off the path that let `block_dates` (via an empty
-- or one-sided-unbounded `daterange`, whose `lower()`/`upper()` both
-- evaluate to NULL) persist a reservation with an unbounded period --
-- `tstzrange(v_start, NULL)` or worse, `tstzrange(NULL, NULL)` -- which
-- `reservations_period_nonempty` cannot catch, because an unbounded range is
-- not an empty one.
--
-- This constraint is the second, independent line of defence: even if some
-- future write path reaches the `reservations` table without going through
-- `build_period` at all (a new RPC, a migration backfill, a direct insert
-- under the admin policy), an unbounded period can never be stored.
alter table public.reservations
  add constraint reservations_period_bounded
  check (not lower_inf(period) and not upper_inf(period));
