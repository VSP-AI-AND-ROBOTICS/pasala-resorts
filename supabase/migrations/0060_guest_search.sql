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
#variable_conflict use_column
declare
  v_sort     text := coalesce(nullif(btrim(p_sort), ''), 'recommended');
  v_patterns text[];
  v_wanted   text[];
begin
  if v_sort not in ('recommended', 'distance', 'price', 'rating')
     or (p_lat is null) <> (p_lng is null)
     or p_lat not between -90 and 90
     or p_lng not between -180 and 180
     or length(p_query) > 100 then
    raise exception using errcode = 'P0041', message = 'invalid_search';
  end if;

  -- One ILIKE pattern per word. The guest's own \, % and _ are escaped so
  -- they match literally.
  select coalesce(array_agg('%' || replace(replace(replace(w, '\', '\\'),
                                                   '%', '\%'),
                                           '_', '\_') || '%'),
                  '{}')
    into v_patterns
    from regexp_split_to_table(btrim(coalesce(p_query, '')), '\s+') as w
   where w <> '';

  -- The amenities the guest asked for, lower-cased, with blanks dropped.
  select coalesce(array_agg(distinct lower(btrim(a))), '{}')
    into v_wanted
    from unnest(coalesce(p_amenities, '{}'::text[])) as a
   where btrim(a) <> '';

  return query
  with matched as (
    select p.*
      from public.properties p
     where p.status = 'active'
       and p.is_active
       -- every word appears in some field
       and not exists (
             select 1 from unnest(v_patterns) as pat
              where not (p.name ilike pat
                         or coalesce(p.address, '') ilike pat
                         or coalesce(p.description, '') ilike pat
                         or array_to_string(p.amenities, ' ') ilike pat))
       -- every requested amenity is present
       and not exists (
             select 1 from unnest(v_wanted) as want
              where not exists (select 1 from unnest(p.amenities) as have
                                 where lower(btrim(have)) = want))
  ),
  prices as (
    -- Lowest nightly price: nightly rules (no slot type) of active units
    -- that take nightly bookings, not yet expired in the resort's own
    -- timezone.
    select u.property_id, min(r.price) as min_price
      from matched m
      join public.units u on u.property_id = m.id
      join public.rate_rules r on r.unit_id = u.id
     where u.is_active
       and u.booking_mode in ('nightly', 'both')
       and r.slot_type_id is null
       and (r.valid_to is null
            or r.valid_to >= (now() at time zone m.timezone)::date)
     group by u.property_id
  ),
  ratings as (
    select rv.property_id,
           count(*)::int                    as review_count,
           sum(rv.overall_rating)::numeric  as rating_sum
      from matched m
      join public.reviews rv on rv.property_id = m.id
     group by rv.property_id
  ),
  cards as (
    select m.id, m.name, m.slug, m.description, m.address, m.images,
           m.amenities, m.check_in_time, m.check_out_time, m.is_active,
           m.lat, m.lng,
           -- Haversine, R = 6371 km, rounded to 0.1 km.
           case when p_lat is not null and m.lat is not null then
             round((2 * 6371 * asin(least(1.0::double precision, sqrt(
                 power(sin(radians(m.lat - p_lat) / 2), 2)
                 + cos(radians(p_lat)) * cos(radians(m.lat))
                   * power(sin(radians(m.lng - p_lng) / 2), 2)))))::numeric, 1)
           end                                        as distance_km,
           pr.min_price::numeric                      as min_price,
           round(rt.rating_sum / rt.review_count, 1)  as avg_rating,
           coalesce(rt.review_count, 0)               as review_count,
           -- Recommended: the average shrunk toward 4 by three phantom
           -- reviews, so one 5-star review does not outrank many 4.5s.
           (coalesce(rt.rating_sum, 0) + 12)
             / (coalesce(rt.review_count, 0) + 3)     as score,
           cardinality(m.images) > 0                  as has_photo
      from matched m
      left join prices  pr on pr.property_id = m.id
      left join ratings rt on rt.property_id = m.id
  )
  select c.id, c.name, c.slug, c.description, c.address, c.images,
         c.amenities, c.check_in_time, c.check_out_time, c.is_active,
         c.lat, c.lng, c.distance_km, c.min_price, c.avg_rating,
         c.review_count
    from cards c
   order by
     case when v_sort = 'distance' and p_lat is not null
          then c.distance_km end asc nulls last,
     case when v_sort = 'price'  then c.min_price  end asc nulls last,
     case when v_sort = 'rating' then c.avg_rating end desc nulls last,
     case when v_sort = 'rating' then c.review_count end desc,
     -- Recommended, and distance requested without a position.
     case when v_sort = 'recommended' or (v_sort = 'distance' and p_lat is null)
          then c.score end desc,
     case when v_sort = 'recommended' or (v_sort = 'distance' and p_lat is null)
          then c.has_photo end desc,
     c.name, c.id;
end;
$$;

revoke execute on function public.search_resorts(text, double precision, double precision, text, text[]) from public;
grant execute on function public.search_resorts(text, double precision, double precision, text, text[]) to anon, authenticated;
