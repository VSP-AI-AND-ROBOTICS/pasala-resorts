-- Reviews as social proof: the customer-facing property page now shows an
-- average rating and recent reviews from every guest, not just the
-- reviewing customer's own. `reviews_read` (0036_reviews.sql) restricted
-- select to staff-or-above or the review's own author -- too narrow for
-- that, since it would make every other customer's row invisible to a
-- browsing customer. This is a single-property app, so "can read reviews"
-- has no per-property scoping to worry about: any authenticated user
-- (customer, staff, or admin) may read every review.
--
-- Replaces `reviews_read` outright, rather than adding a second permissive
-- policy alongside it -- the new `using (true)` is already a superset of
-- the old condition, so keeping both would just be two policies enforcing
-- one rule.
drop policy reviews_read on public.reviews;

create policy reviews_read_all on public.reviews
  for select to authenticated
  using (true);
