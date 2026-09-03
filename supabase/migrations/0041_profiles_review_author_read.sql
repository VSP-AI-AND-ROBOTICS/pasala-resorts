-- I5: `reviews_read_all` (0040) made every review publicly readable as
-- "social proof," but `Review.fromJson`'s `profiles(full_name)` embed still
-- came back null for every review not authored by the viewer -- the
-- customer-facing reviews list (property page + standalone Reviews screen)
-- silently fell back to "Guest" for every OTHER customer's review, since
-- `profiles_select_self` (0002_profiles.sql) only lets a customer read
-- their own profile row.
--
-- Scoped to exactly the profiles that have actually authored a (now-public)
-- review -- not a blanket "any customer can read any customer's profile"
-- grant. Note this technically also exposes a review author's `phone`
-- column to any authenticated reader (RLS is row-level, not column-level,
-- and `profiles` already carries a table-wide `grant select ... to
-- authenticated` from 0002) -- accepted here since this is a single
-- -property, name-as-social-proof feature and every seeded profile's phone
-- is unset regardless; a real deployment storing real phone numbers should
-- revisit this via a narrower view instead.
create policy profiles_review_author_read on public.profiles
  for select to authenticated
  using (exists (
    select 1 from public.reviews r where r.customer_id = profiles.id
  ));
