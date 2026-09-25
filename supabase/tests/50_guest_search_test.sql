-- Guest search and discovery (P11), added in 0060_guest_search.sql. See
-- docs/superpowers/specs/2026-09-25-p11-guest-search-and-discovery-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Fixtures. Every slug starts with p11-, and the helpers below only look
-- at those rows, so the seeded Pasala resort never interferes.
--   Lakeview Retreat  active, Hyderabad, photo, Pool + Wi-Fi, reviews 5 and 4,
--                     nightly 4000 (weekend 5500). Rates that must NOT
--                     count: a slot rate of 1200, an inactive unit's 1000,
--                     an expired override of 900.
--   Hilltop Farm      active, Bengaluru, photo, Wi-Fi + Bonfire,
--                     "100% organic", nightly 2500, no reviews.
--   Coastal Nest      active, Goa, no photo, no coordinates, Pool + Spa,
--                     nightly 6000, one review of 5.
--   Day Only Park     active, Hyderabad, no photo, slot-only unit (1500),
--                     so no nightly price; no reviews.
--   Closed Camp       suspended.
--   Hidden Hut        is_active = false.
--                     Both of these sit at the search origin and match
--                     "hyderabad" and "pool", so any leak would show up.
-- Users: Gita (guest), Lakeview's owner, Lakeview's staff member, and
-- Closed Camp's owner.
begin;
select plan(43);

-- Rows a statement changed, run as the current role (0 when RLS filters
-- it). Used by later sections.
create function pg_temp.rows_affected(p_sql text) returns int
language plpgsql as $f$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$f$;

-- The fixture resorts search_resorts returned, in its order.
create function pg_temp.found(
  p_query     text default null,
  p_lat       double precision default null,
  p_lng       double precision default null,
  p_sort      text default 'recommended',
  p_amenities text[] default null
) returns text[] language sql as $f$
  select coalesce(array_agg(s.name order by s.ordinality), '{}')
    from public.search_resorts(p_query, p_lat, p_lng, p_sort, p_amenities)
         with ordinality s
   where s.slug like 'p11-%';
$f$;

-- The same, alphabetically: for tests about which resorts match, not
-- their order.
create function pg_temp.found_set(
  p_query     text default null,
  p_lat       double precision default null,
  p_lng       double precision default null,
  p_sort      text default 'recommended',
  p_amenities text[] default null
) returns text[] language sql as $f$
  select coalesce(array_agg(s.name order by s.name), '{}')
    from public.search_resorts(p_query, p_lat, p_lng, p_sort, p_amenities) s
   where s.slug like 'p11-%';
$f$;

insert into auth.users (id, email) values
  ('c1100000-0000-4000-8000-0000000000a1','p11-guest@example.com'),
  ('c1100000-0000-4000-8000-0000000000a2','p11-lake-owner@example.com'),
  ('c1100000-0000-4000-8000-0000000000a3','p11-lake-staff@example.com'),
  ('c1100000-0000-4000-8000-0000000000a4','p11-camp-owner@example.com');

insert into public.properties
  (id, name, slug, description, address, images, amenities, lat, lng, status, is_active)
values
  ('c1100000-0000-4000-8000-000000000001','Lakeview Retreat','p11-lakeview',
   'Quiet lakeside cottages','Gandipet Road, Hyderabad, Telangana',
   array['https://example.com/lakeview.jpg'], array['Pool','Wi-Fi'],
   17.3850, 78.4867, 'active', true),
  ('c1100000-0000-4000-8000-000000000002','Hilltop Farm','p11-hilltop',
   'Farm stay with 100% organic food','Nandi Hills, Bengaluru, Karnataka',
   array['https://example.com/hilltop.jpg'], array['Wi-Fi','Bonfire'],
   13.3702, 77.6835, 'active', true),
  ('c1100000-0000-4000-8000-000000000003','Coastal Nest','p11-coastal',
   'Beach huts','Calangute, Goa',
   '{}', array['Pool','Spa'], null, null, 'active', true),
  ('c1100000-0000-4000-8000-000000000004','Closed Camp','p11-closed',
   'Closed for now','Hyderabad',
   '{}', array['Pool'], 17.3900, 78.4900, 'suspended', true),
  ('c1100000-0000-4000-8000-000000000005','Hidden Hut','p11-hidden',
   'Not listed','Hyderabad',
   '{}', array['Pool'], 17.3900, 78.4900, 'active', false),
  ('c1100000-0000-4000-8000-000000000006','Day Only Park','p11-dayonly',
   'Picnic lawns for day visits','Shamshabad, Hyderabad, Telangana',
   '{}', array['Parking'], 17.2403, 78.4294, 'active', true);

insert into public.resort_members (property_id, user_id, role) values
  ('c1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-0000000000a2','owner'),
  ('c1100000-0000-4000-8000-000000000001','c1100000-0000-4000-8000-0000000000a3','staff'),
  ('c1100000-0000-4000-8000-000000000004','c1100000-0000-4000-8000-0000000000a4','owner');

insert into public.slot_types (id, property_id, code, start_time, end_time) values
  ('c1100000-0000-4000-8000-000000000101','c1100000-0000-4000-8000-000000000001','day','09:00','18:00'),
  ('c1100000-0000-4000-8000-000000000106','c1100000-0000-4000-8000-000000000006','day','09:00','18:00');

insert into public.units (id, property_id, name, capacity_base, capacity_max, booking_mode, is_active) values
  ('c1100000-0000-4000-8000-000000000011','c1100000-0000-4000-8000-000000000001','Lake Cottage',2,4,'nightly',true),
  ('c1100000-0000-4000-8000-000000000012','c1100000-0000-4000-8000-000000000001','Lake Deck',2,4,'both',true),
  ('c1100000-0000-4000-8000-000000000013','c1100000-0000-4000-8000-000000000001','Old Shed',2,4,'nightly',false),
  ('c1100000-0000-4000-8000-000000000021','c1100000-0000-4000-8000-000000000002','Hill Room',2,4,'nightly',true),
  ('c1100000-0000-4000-8000-000000000031','c1100000-0000-4000-8000-000000000003','Sea Room',2,4,'nightly',true),
  ('c1100000-0000-4000-8000-000000000041','c1100000-0000-4000-8000-000000000004','Camp Tent',2,4,'nightly',true),
  ('c1100000-0000-4000-8000-000000000051','c1100000-0000-4000-8000-000000000005','Hut',2,4,'nightly',true),
  ('c1100000-0000-4000-8000-000000000061','c1100000-0000-4000-8000-000000000006','Picnic Lawn',10,40,'slot',true);

insert into public.rate_rules
  (unit_id, kind, price, slot_type_id, weekdays, valid_from, valid_to, priority)
values
  ('c1100000-0000-4000-8000-000000000011','base',     4000, null, null, null, null, 0),
  ('c1100000-0000-4000-8000-000000000011','weekend',  5500, null, array[6,7], null, null, 10),
  ('c1100000-0000-4000-8000-000000000011','override',  900, null, null, current_date - 10, current_date - 2, 20),
  ('c1100000-0000-4000-8000-000000000012','base',     4800, null, null, null, null, 0),
  ('c1100000-0000-4000-8000-000000000012','base',     1200, 'c1100000-0000-4000-8000-000000000101', null, null, null, 0),
  ('c1100000-0000-4000-8000-000000000013','base',     1000, null, null, null, null, 0),
  ('c1100000-0000-4000-8000-000000000021','base',     2500, null, null, null, null, 0),
  ('c1100000-0000-4000-8000-000000000031','base',     6000, null, null, null, null, 0),
  ('c1100000-0000-4000-8000-000000000041','base',      500, null, null, null, null, 0),
  ('c1100000-0000-4000-8000-000000000051','base',      500, null, null, null, null, 0),
  ('c1100000-0000-4000-8000-000000000061','base',     1500, 'c1100000-0000-4000-8000-000000000106', null, null, null, 0);

insert into public.reservations (id, unit_id, period, kind, status, customer_id) values
  ('c1100000-0000-4000-8000-000000000201','c1100000-0000-4000-8000-000000000011',
   public.build_period('c1100000-0000-4000-8000-000000000011', current_date - 20, current_date - 18),
   'booking','checked_out','c1100000-0000-4000-8000-0000000000a1'),
  ('c1100000-0000-4000-8000-000000000202','c1100000-0000-4000-8000-000000000011',
   public.build_period('c1100000-0000-4000-8000-000000000011', current_date - 10, current_date - 8),
   'booking','checked_out','c1100000-0000-4000-8000-0000000000a1'),
  ('c1100000-0000-4000-8000-000000000203','c1100000-0000-4000-8000-000000000031',
   public.build_period('c1100000-0000-4000-8000-000000000031', current_date - 15, current_date - 13),
   'booking','checked_out','c1100000-0000-4000-8000-0000000000a1');

insert into public.reviews
  (reservation_id, customer_id, farmhouse_rating, cleanliness_rating,
   food_rating, service_rating, activities_rating, overall_rating)
values
  ('c1100000-0000-4000-8000-000000000201','c1100000-0000-4000-8000-0000000000a1',5,5,5,5,5,5),
  ('c1100000-0000-4000-8000-000000000202','c1100000-0000-4000-8000-0000000000a1',4,4,4,4,4,4),
  ('c1100000-0000-4000-8000-000000000203','c1100000-0000-4000-8000-0000000000a1',5,5,5,5,5,5);

-- === Task 1: the contract ===================================================

select has_function('public', 'search_resorts',
  array['text', 'double precision', 'double precision', 'text', 'text[]'],
  'search_resorts(text, double precision, double precision, text, text[]) exists');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'search_resorts'
              and p.parameter_mode = 'OUT'),
  array['id','name','slug','description','address','images','amenities',
        'check_in_time','check_out_time','is_active','lat','lng',
        'distance_km','min_price','avg_rating','review_count'],
  'search_resorts returns the columns ResortSearchResult.fromJson reads');
select ok(has_function_privilege('anon',
    'public.search_resorts(text, double precision, double precision, text, text[])', 'execute'),
  'anon can search (guests browse signed out)');
select ok(has_function_privilege('authenticated',
    'public.search_resorts(text, double precision, double precision, text, text[])', 'execute'),
  'signed-in users can search');
select ok((select prosecdef from pg_proc
            where oid = 'public.search_resorts(text, double precision, double precision, text, text[])'::regprocedure),
  'search_resorts is security definer (it reads review aggregates anon cannot)');
select ok((select proconfig @> array['search_path=public, pg_temp'] from pg_proc
            where oid = 'public.search_resorts(text, double precision, double precision, text, text[])'::regprocedure),
  'search_resorts pins its search_path');

select throws_ok($$update public.properties set lat = 15.5 where slug = 'p11-coastal'$$,
  '23514', null, 'a latitude without a longitude is refused');
select throws_ok($$update public.properties set lat = 91, lng = 78 where slug = 'p11-coastal'$$,
  '23514', null, 'a latitude above 90 is refused');
select throws_ok($$update public.properties set lat = 15, lng = 181 where slug = 'p11-coastal'$$,
  '23514', null, 'a longitude above 180 is refused');
select lives_ok($$update public.properties set lat = 15.5449, lng = 73.7553 where slug = 'p11-coastal'$$,
  'a valid pair is accepted');
update public.properties set lat = null, lng = null where slug = 'p11-coastal';

-- === Task 2: which resorts match, and what each card carries =============
-- Run as anon: guests browse signed out.
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select is(pg_temp.found_set(),
  array['Coastal Nest','Day Only Park','Hilltop Farm','Lakeview Retreat'],
  'anon sees every active resort, and no suspended or inactive one');
select is(pg_temp.found_set('closed'), '{}'::text[],
  'a suspended resort never matches, even by its own name');
select is(pg_temp.found_set('hidden'), '{}'::text[],
  'an inactive resort never matches, even by its own name');
select is(pg_temp.found_set('LAKE'), array['Lakeview Retreat'],
  'names match case-insensitively');
select is(pg_temp.found_set('hyderabad'), array['Day Only Park','Lakeview Retreat'],
  'the city inside the address matches');
select is(pg_temp.found_set('organic'), array['Hilltop Farm'],
  'the description matches');
select is(pg_temp.found_set('bonfire'), array['Hilltop Farm'],
  'an amenity matches');
select is(pg_temp.found_set('  pool   goa '), array['Coastal Nest'],
  'every word must match, each in any field');
select is(pg_temp.found_set('%'), array['Hilltop Farm'],
  'a typed % matches a literal percent sign only');
select is(pg_temp.found_set('_'), '{}'::text[],
  'a typed _ matches a literal underscore only');
select is(pg_temp.found_set('   '),
  array['Coastal Nest','Day Only Park','Hilltop Farm','Lakeview Retreat'],
  'a blank query matches everything');
select is(pg_temp.found_set(p_amenities => array['pool']),
  array['Coastal Nest','Lakeview Retreat'],
  'amenities match case-insensitively');
select is(pg_temp.found_set(p_amenities => array['Pool','Wi-Fi']),
  array['Lakeview Retreat'], 'every requested amenity must be present');
select is(pg_temp.found_set(p_amenities => array['Sauna']), '{}'::text[],
  'an amenity nobody has matches nothing');
select is(pg_temp.found_set(p_amenities => array['', '  ']),
  array['Coastal Nest','Day Only Park','Hilltop Farm','Lakeview Retreat'],
  'blank amenities are ignored');
select is(pg_temp.found_set('hyderabad', p_amenities => array['pool']),
  array['Lakeview Retreat'], 'the query and the amenity filter combine');

select is((select s.min_price from public.search_resorts('lakeview') s
            where s.slug = 'p11-lakeview'),
  4000.00::numeric,
  'min_price ignores slot rates, inactive units and expired overrides');
select is((select s.avg_rating from public.search_resorts() s
            where s.slug = 'p11-lakeview'),
  4.5::numeric, 'avg_rating averages overall_rating');
select is((select s.review_count from public.search_resorts() s
            where s.slug = 'p11-lakeview'),
  2, 'review_count counts the reviews');
select ok((select s.avg_rating = 5.0 and s.review_count = 1
             from public.search_resorts() s where s.slug = 'p11-coastal'),
  'a single review is its own average');
select is((select s.min_price from public.search_resorts() s
            where s.slug = 'p11-dayonly'),
  null::numeric, 'a day-use-only resort has no nightly price');
select ok((select s.avg_rating is null and s.review_count = 0
             from public.search_resorts() s where s.slug = 'p11-hilltop'),
  'a resort without reviews has no rating and a count of 0');
select is((select s.address from public.search_resorts() s
            where s.slug = 'p11-lakeview'),
  'Gandipet Road, Hyderabad, Telangana', 'rows carry the Property fields');

select ok((select bool_and(s.distance_km is null) from public.search_resorts() s
            where s.slug like 'p11-%'),
  'without a position no distance is computed');
select is((select s.distance_km from public.search_resorts(null, 17.3850, 78.4867) s
            where s.slug = 'p11-lakeview'),
  0.0::numeric, 'a resort at the search origin is 0 km away');
select ok((select s.distance_km between 440 and 470
             from public.search_resorts(null, 17.39, 78.49) s
            where s.slug = 'p11-hilltop'),
  'Hyderabad to Nandi Hills is about 455 km');
select is((select s.distance_km from public.search_resorts(null, 17.39, 78.49) s
            where s.slug = 'p11-coastal'),
  null::numeric, 'a resort without coordinates has no distance');

select throws_ok($$select * from public.search_resorts(null, null, null, 'cheapest', null)$$,
  'P0041', 'invalid_search', 'an unknown sort is refused');
select throws_ok($$select * from public.search_resorts(null, 17.39, null)$$,
  'P0041', 'invalid_search', 'a latitude without a longitude is refused');
select throws_ok($$select * from public.search_resorts(null, 91, 0)$$,
  'P0041', 'invalid_search', 'an out-of-range latitude is refused');
select throws_ok(format('select * from public.search_resorts(%L)', repeat('a', 101)),
  'P0041', 'invalid_search', 'a query over 100 characters is refused');
select lives_ok(format('select * from public.search_resorts(%L)', repeat('a', 100)),
  'a 100-character query is fine');
select lives_ok($$select * from public.search_resorts(null, null, null, null, null)$$,
  'a null sort means recommended');

reset role;
set local request.jwt.claims to '';

select * from finish();
rollback;
