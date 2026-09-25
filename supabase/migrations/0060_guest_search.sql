-- Guest search and discovery (P11): resort coordinates and the public
-- search_resorts function behind the browse screen's search box, sort and
-- amenity chips.
-- See docs/superpowers/specs/2026-09-25-p11-guest-search-and-discovery-design.md.
--
-- Error code: P0041 invalid_search. Raised for an unknown sort, only one
-- of p_lat/p_lng, an out-of-range coordinate, or a query over 100
-- characters.

-- ---------------------------------------------------------------------
-- properties.lat / lng have existed since 0003, but nothing wrote them
-- until now. First clear any half-set or out-of-range pair, then add the
-- checks. The owner writes them through the existing properties_update
-- policy (0044).
update public.properties
   set lat = null, lng = null
 where (lat is null) <> (lng is null)
    or lat not between -90 and 90
    or lng not between -180 and 180;

alter table public.properties
  add constraint properties_coordinates_pair
    check ((lat is null) = (lng is null)),
  add constraint properties_lat_range
    check (lat is null or lat between -90 and 90),
  add constraint properties_lng_range
    check (lng is null or lng between -180 and 180);

-- ---------------------------------------------------------------------
-- search_resorts: every active resort that matches, with the card fields
-- plus distance, lowest nightly price and rating. Security definer, so
-- it can aggregate reviews for anon. It returns no review text and
-- nothing about inactive, suspended, archived or pending resorts. The
-- signature is the contract the app is built against; Tasks 2 and 3 of
-- the plan replace the stub body.
create function public.search_resorts(
  p_query     text default null,
  p_lat       double precision default null,
  p_lng       double precision default null,
  p_sort      text default 'recommended',
  p_amenities text[] default null
) returns table (
  id             uuid,
  name           text,
  slug           text,
  description    text,
  address        text,
  images         text[],
  amenities      text[],
  check_in_time  time,
  check_out_time time,
  is_active      boolean,
  lat            double precision,
  lng            double precision,
  distance_km    numeric,
  min_price      numeric,
  avg_rating     numeric,
  review_count   int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'search_resorts is not implemented yet' using errcode = '0A000';
end;
$$;

revoke execute on function public.search_resorts(text, double precision, double precision, text, text[]) from public;
grant execute on function public.search_resorts(text, double precision, double precision, text, text[]) to anon, authenticated;
