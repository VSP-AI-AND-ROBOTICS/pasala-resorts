# Guest Search and Discovery (P11) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a guest search every bookable resort by name, city, description or amenity; sort by Recommended, Distance, Price or Rating; and see each resort's distance, lowest nightly price and rating on its card. Let an owner set their resort's map position.

**Architecture:** A single `security definer` SQL function, `search_resorts`, runs the whole search. Anon can call it. It filters active resorts, computes the minimum nightly price from `rate_rules` and the rating from `reviews`, computes the haversine distance, and orders the rows. The existing `properties.lat`/`lng` columns gain range checks. The owner writes them through the existing `properties_update` policy. On the app side:
- A `ResortSearchSource` seam feeds a Riverpod family keyed by a value-equal `ResortSearchQuery`.
- A `PositionService` provides the guest's coarse position, from the same device fix as the browse hero's location badge.
- The browse screen gets a filter bar and a meta line on each card. Owner Settings gets a Map location screen.

**Tech Stack:** Supabase Postgres 15 (plpgsql, RLS, pgTAP via `supabase test db`), Flutter 3.44 / Dart 3.10, Riverpod 3.3, go_router 17, geolocator 14, shared_preferences, Playwright (e2e).

**Spec:** `docs/superpowers/specs/2026-09-25-p11-guest-search-and-discovery-design.md`

## Global Constraints

- **Migration.** There is one migration, `supabase/migrations/0060_guest_search.sql`, and Tasks 1–3 each edit it.
  - After every edit, rebuild with `supabase db reset`, which re-runs every migration and `supabase/seed.sql`, then run pgTAP.
  - Before the first reset in this plan, dump the local data: `mkdir -p ../pasala-db-backups && supabase db dump --local --data-only -f ../pasala-db-backups/local-before-p11.sql`.
- **pgTAP file.** The new file is `supabase/tests/50_guest_search_test.sql`. Tasks 1–3 build it up section by section.
  - Run one file with `supabase test db supabase/tests/50_guest_search_test.sql`.
  - Run the whole suite with `supabase test db`.
- **Error code.** The new error code is **P0041 `invalid_search`**, raised with `raise exception using errcode = 'P0041', message = 'invalid_search'`.
- **Function contract.** `search_resorts` is `security definer` and has `set search_path = public, pg_temp`.
  - Revoke it from `public` and grant it to `anon, authenticated`.
  - Add it to the definer allow-list in `supabase/tests/37_tenancy_isolation_test.sql`.
- **Resort visibility.** Only resorts with `status = 'active' and is_active` are ever returned, whoever the caller is.
- **Pre-existing failures.** Three pgTAP failures appear only between 00:00 and 05:30 IST: 25/9, 26/3 and 34/2. Every other test must pass.
- **Analyzer baseline.** The `flutter analyze` baseline is 2 infos, both in `service_request_screen.dart`.
- **Dart conventions.**
  - Repositories wrap every call in `_guard`, which maps errors through `mapPostgrestError` (`lib/core/errors.dart`).
  - Widget tests use fakes from `test/support/` and never a real `SupabaseClient`, geolocator or network.
- **Guest position privacy.** The guest's position is rounded to 2 decimal places (`GeoPoint.coarse()`) before it is cached or sent anywhere. The owner's precise fix is used only to fill the owner's own form.
- **UI copy, exact:**
  - `Search resorts` (search field label), `Name, city or amenity` (hint), `Clear search` (tooltip)
  - Sort labels: `Recommended`, `Distance`, `Price: low to high`, `Rating`
  - `Clear filters`, `No resorts match your search`, `Try a different word or clear the filters.`
  - Card meta: `4.5 (2)`, `12 km`, `< 1 km`, `from ₹4,000 / night`, rating semantics `Rated 4.5 out of 5 from 2 reviews`
  - Owner: `Map location`, `Use my current location`, `Latitude`, `Longitude`, `Not set. Guests will not see how far away you are.`
- **Commands.**
  - Run `flutter test <path>`, `flutter test` and `flutter analyze`.
  - Never run `dart format` over whole directories or over pre-existing files; format only the lines you write.
  - Revert SDK-only `pubspec.lock` bumps.
  - Never commit secrets.
- **Commits.** Every commit message ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Pass it as a second `-m`, as the commit steps below show. Do not push.

## Review Focus

1. **A guest types faster than the search answers.** The list must not blank, the search box must keep its focus, and only the latest query's results may end up on screen. Owning test: Task 6 ("keeps the previous results under a progress bar while the next search loads").
2. **A guest types `%`, `_` or `\`.** These must match literally, not as LIKE wildcards, so `%` must not match every resort. Owning tests: Task 2 (`%` finds only the resort whose description says "100%", and `_` finds nothing).
3. **No position, or permission denied.** "Distance" must not be offered. If distance is requested without coordinates anyway, the server falls back to Recommended instead of failing. Owning tests: Task 6 (the sort menu has no Distance without a position) and Task 3 (distance without a position gives the recommended order).
4. **A resort with no nightly price** (day-use only, or every nightly rate expired). It must show no price text, must sort last by price, and must never show "₹0". Owning tests: Task 2 (a day-use-only resort's `min_price` is null), Task 3 (last in the price sort) and Task 5 (the card without a price).
5. **An owner types half a coordinate, an out-of-range value, or a comma decimal (`17,385`).** The owner must get a message and nothing may be saved. The table refuses the same values if the app is bypassed. Owning tests: Task 7 (each invalid form is refused and nothing is sent) and Task 1 (the table checks).

## Plan decisions (where the spec is silent)

- **Split of `search_resorts` work.** Task 2 writes the filtering and card fields and orders rows by name. Task 3 replaces only the ordering. Tests in Task 2 compare sets (the `pg_temp.found_set` helper), so Task 3's reordering cannot break them.
- **Test helpers.** The pgTAP helpers only look at rows whose slug starts with `p11-`. The seeded Pasala resort, and anything else in the local database, never affects the results.
- **Position provider fallback.** `positionServiceProvider` picks the `locationServiceProvider` instance when that instance also implements `PositionService`, and `NoPositionService` otherwise. Existing tests that override `locationServiceProvider` with a place-only fake therefore keep compiling and simply have no position.
- **Amenity chips.** The chips come from `resortSearchProvider(ResortSearchQuery.all)`, so choosing a chip never removes the other chips. The currently selected amenity is always kept in the chip list.
- **Empty results use `_CenteredMessage`.** The browse results area shows its empty states with a private `_CenteredMessage`, a plain `Column`, not `EmptyState`. `SliverFillRemaining(hasScrollBody: false)` measures its child's intrinsic height, and `EmptyState`'s `LayoutBuilder` cannot report one.
- **Grid aspect ratio.** The wide grid's `childAspectRatio` goes from 0.82 to 0.76, making room for the meta line. A test pins "no overflow" at the 840 px breakpoint.
- **Where the owner edits coordinates.** The owner edits them on a new `LocationSettingsScreen`, not in `PropertyFormScreen`. P4 and P10 also touch the property form, and a separate screen keeps this project's edit to one new tile in Owner Settings.
- **Allow-list anchor.** `search_resorts` is added at the end of the allow-list, after `'reviews_set_author_name'`. Other projects in this round anchor on other lines, so merges are additive.

## Execution tracks

After Task 1, the database track and the app track share no files, so they can run in parallel. For example, run them in two worktrees branched from Task 1's commit and merge both back before Task 8. App tasks never need a database, because their tests use `FakeResortSearchSource` and `FakePositionService`.

| Task | Track | Depends on | Files it owns |
|---|---|---|---|
| 1 Interface contract | both | none | `0060` (checks + stub), `50` (fixtures + contract), `37` (allow-list), `geo_point.dart`, `position_service.dart`, `resort_search.dart`, `resort_search_repository.dart`, `property.dart`, `errors.dart`, `fake_resort_search_source.dart`, `fake_position_service.dart` |
| 2 Filtering and card fields | DB | 1 | `0060`, `50` |
| 3 Sort orders and access | DB | 2 | `0060`, `50` |
| 4 Device position | App | 1 | `location_cache.dart`, `device_location_service.dart`, `location_badge.dart` |
| 5 Card meta line | App | 1 | `resort_meta_line.dart`, `browse_screen.dart` (`PropertyCard` only) |
| 6 Browse search, sort, filters | App | 5 | `browse_screen.dart` (`BrowseScreen`), `browse_filter_bar.dart` |
| 7 Owner map location | App | 1 | `location_settings_screen.dart`, `owner_settings_screen.dart` |
| 8 Integration | both | 2–7 | `e2e/tests/guest.spec.ts` |

- The database track is strictly sequential, because Tasks 2 and 3 share one migration, one test file and one local Postgres.
- In the app track, Task 6 waits for Task 5, since both edit `browse_screen.dart`. Tasks 4, 5 and 7 can run in parallel.

---

## File Structure

**Database**
- Create `supabase/migrations/0060_guest_search.sql`: the coordinate cleanup and the three checks on `properties`, and `search_resorts` with its grants.
- Create `supabase/tests/50_guest_search_test.sql`: the fixtures, the contract, filtering, card fields, validation, sort orders, access, and owner writes.
- Modify `supabase/tests/37_tenancy_isolation_test.sql`: add `search_resorts` to the definer allow-list.

**App**
- Create `lib/core/location/geo_point.dart`: `GeoPoint` (validity, `coarse()`, equality).
- Create `lib/core/location/position_service.dart`: `PositionService`, `NoPositionService`, `positionServiceProvider`, `currentPositionProvider`.
- Modify `lib/core/location/location_cache.dart`: `readPoint()` / `writePoint()`.
- Modify `lib/core/location/device_location_service.dart`: implements `PositionService` with one shared low-accuracy fix.
- Modify `lib/features/browse/location_badge.dart`: "Set location" also retries the position.
- Create `lib/data/models/resort_search.dart`: `ResortSort`, `ResortSearchQuery`, `ResortSearchResult`, `distanceLabel`.
- Create `lib/data/repositories/resort_search_repository.dart`: `ResortSearchSource`, `ResortSearchRepository`, providers.
- Modify `lib/data/models/property.dart`: `latitude`, `longitude`, `location`.
- Modify `lib/core/errors.dart`: P0041 → `InvalidSearch`.
- Create `lib/features/browse/resort_meta_line.dart`: `ResortMetaLine`.
- Create `lib/features/browse/browse_filter_bar.dart`: `BrowseFilterBar`.
- Modify `lib/features/browse/browse_screen.dart`: `BrowseScreen` on `search_resorts`, and `PropertyCard` meta parameters.
- Create `lib/features/owner/location_settings_screen.dart`: `LocationSettingsScreen`, `parseCoordinates`.
- Modify `lib/features/owner/owner_settings_screen.dart`: the "Map location" tile.

**Tests**
- Create `test/support/fake_resort_search_source.dart` and `test/support/fake_position_service.dart`.
- Create `test/core/location/geo_point_test.dart`, `test/core/location/position_service_test.dart`, `test/data/resort_search_test.dart`, `test/data/resort_search_provider_test.dart`, `test/features/browse/resort_meta_line_test.dart` and `test/features/owner/location_settings_screen_test.dart`.
- Modify `test/data/property_test.dart`, `test/core/errors_test.dart`, `test/core/location/location_cache_test.dart`, `test/features/browse/location_badge_test.dart`, `test/features/browse/property_card_test.dart`, `test/features/browse/browse_screen_test.dart` (rewritten), `test/features/browse/browse_screen_dark_mode_test.dart` and `test/features/owner/owner_settings_screen_test.dart`.
- Modify `e2e/tests/guest.spec.ts`.

---

## Phase 0: Interface

### Task 1: Interface contract (checks, function signature, Dart API)

**Track:** both. Every later task depends on it.

**Files:**
- Create: `supabase/migrations/0060_guest_search.sql`
- Create: `supabase/tests/50_guest_search_test.sql`
- Modify: `supabase/tests/37_tenancy_isolation_test.sql` (definer allow-list, near the end of the file)
- Create: `lib/core/location/geo_point.dart`
- Create: `lib/core/location/position_service.dart`
- Create: `lib/data/models/resort_search.dart`
- Create: `lib/data/repositories/resort_search_repository.dart`
- Modify: `lib/data/models/property.dart`
- Modify: `lib/core/errors.dart`
- Create: `test/support/fake_resort_search_source.dart`, `test/support/fake_position_service.dart`
- Test: `test/core/location/geo_point_test.dart`, `test/core/location/position_service_test.dart`, `test/data/resort_search_test.dart`, `test/data/resort_search_provider_test.dart`, `test/data/property_test.dart`, `test/core/errors_test.dart`

**Interfaces:**
- Consumes (existing code):
  - `properties.lat`/`lng` (`0003`), `properties_update` (`0044`)
  - `locationServiceProvider` / `LocationService` (`lib/core/location/location_service.dart`)
  - `Property.fromJson`, `mapPostgrestError`, `supabaseProvider`
- Produces (SQL; Tasks 2 and 3 replace only the body):
  - `public.search_resorts(p_query text default null, p_lat double precision default null, p_lng double precision default null, p_sort text default 'recommended', p_amenities text[] default null) returns table (id uuid, name text, slug text, description text, address text, images text[], amenities text[], check_in_time time, check_out_time time, is_active boolean, lat double precision, lng double precision, distance_km numeric, min_price numeric, avg_rating numeric, review_count int)`
  - Constraints `properties_coordinates_pair`, `properties_lat_range`, `properties_lng_range`.
- Produces (Dart):
  - `class GeoPoint { final double latitude, longitude; bool get isValid; GeoPoint coarse(); }` with value equality.
  - `abstract class PositionService { Future<GeoPoint?> approximatePosition(); Future<GeoPoint?> precisePosition(); }`
  - `class NoPositionService implements PositionService`
  - `positionServiceProvider` (`Provider<PositionService>`) and `currentPositionProvider` (`FutureProvider<GeoPoint?>`).
  - `enum ResortSort { recommended, distance, priceLow, rating }` with the extension getters `dbValue` (`recommended|distance|price|rating`) and `label`.
  - `class ResortSearchQuery`:
    - `const ResortSearchQuery({String text = '', ResortSort sort = ResortSort.recommended, List<String> amenities = const [], GeoPoint? origin})`
    - `static const all`, `bool get hasFilters`, `Map<String, dynamic> toParams()`
    - value `==`/`hashCode`
  - `class ResortSearchResult`:
    - `{Property property; double? distanceKm; num? minPrice; double? avgRating; int reviewCount}`
    - `factory ResortSearchResult.fromJson(Map<String, dynamic>)`
  - `String distanceLabel(double km)`.
  - `abstract class ResortSearchSource { Future<List<ResortSearchResult>> search(ResortSearchQuery query); }`
  - `ResortSearchRepository`, `resortSearchRepositoryProvider`, `resortSearchSourceProvider` (`Provider<ResortSearchSource>`) and `resortSearchProvider` (`FutureProvider.autoDispose.family<List<ResortSearchResult>, ResortSearchQuery>`).
  - `Property.latitude`, `Property.longitude` (`double?`, read from `lat`/`lng`), `GeoPoint? get location`.
  - `class InvalidSearch extends BookingFailure`, which P0041 maps to.
  - Test support:
    - `FakeResortSearchSource`, with the fields `results`, `respond`, `error`, `hold` and `calls`
    - `respondLikeServer(List<ResortSearchResult>)`
    - `searchResult({...})`
    - `FakePositionService`, with the fields `approximate`, `precise`, `approximateCalls` and `preciseCalls`

- [ ] **Step 1: Record the baselines**

Run: `supabase db reset && supabase test db 2>&1 | tail -20`, then `flutter analyze 2>&1 | tail -5`, then `flutter test 2>&1 | tail -3`
Expected: record these three numbers, which later tasks compare against:
- the pgTAP failures: only the known time-of-day ones, and none outside 00:00–05:30 IST
- the analyzer issue count: 2 infos
- the Flutter pass count

- [ ] **Step 2: Write the failing pgTAP contract test**

Create `supabase/tests/50_guest_search_test.sql`:

```sql
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
select plan(10);

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

select * from finish();
rollback;
```

- [ ] **Step 3: Run it to verify it fails**

Run: `supabase test db supabase/tests/50_guest_search_test.sql`
Expected: FAIL. `create function pg_temp.found` errors with `function public.search_resorts(text, double precision, double precision, text, text[]) does not exist`.

- [ ] **Step 4: Write the migration's checks and the function stub**

Create `supabase/migrations/0060_guest_search.sql`:

```sql
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
```

- [ ] **Step 5: Add the function to the definer allow-list**

In `supabase/tests/37_tenancy_isolation_test.sql`, replace:

```sql
        'properties_guard_status','reviews_set_author_name'])),
```

with:

```sql
        'properties_guard_status','reviews_set_author_name',
        -- 0060: guest search. It takes no resort id and returns only
        -- active resorts' catalog fields and rating aggregates, so anon
        -- may call it and it needs no role assertion.
        'search_resorts'])),
```

- [ ] **Step 6: Run the database tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/50_guest_search_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: PASS. File 50 reports 10/10 and file 37 reports 77/77.

- [ ] **Step 7: Write the failing Dart tests**

Create `test/core/location/geo_point_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/location/geo_point.dart';

void main() {
  test('coarse() rounds both coordinates to 2 decimal places', () {
    expect(const GeoPoint(17.38512, 78.48671).coarse(),
        const GeoPoint(17.39, 78.49));
    expect(const GeoPoint(-12.344, -45.678).coarse(),
        const GeoPoint(-12.34, -45.68));
  });

  test('isValid accepts the table ranges and refuses anything outside', () {
    expect(const GeoPoint(90, 180).isValid, isTrue);
    expect(const GeoPoint(-90, -180).isValid, isTrue);
    expect(const GeoPoint(90.01, 0).isValid, isFalse);
    expect(const GeoPoint(0, -180.5).isValid, isFalse);
    expect(const GeoPoint(double.nan, 0).isValid, isFalse);
  });

  test('two points with the same coordinates are equal', () {
    expect(const GeoPoint(1, 2), const GeoPoint(1, 2));
    expect(const GeoPoint(1, 2).hashCode, const GeoPoint(1, 2).hashCode);
    expect(const GeoPoint(1, 2), isNot(const GeoPoint(2, 1)));
  });
}
```

Create `test/core/location/position_service_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/location/geo_point.dart';
import 'package:pasala/core/location/location_service.dart';
import 'package:pasala/core/location/place_label.dart';
import 'package:pasala/core/location/position_service.dart';

class _PlaceOnly implements LocationService {
  @override
  Future<PlaceLabel?> currentPlace() async => null;
}

class _PlaceAndPosition implements LocationService, PositionService {
  @override
  Future<PlaceLabel?> currentPlace() async => null;

  @override
  Future<GeoPoint?> approximatePosition() async => const GeoPoint(17.39, 78.49);

  @override
  Future<GeoPoint?> precisePosition() async => const GeoPoint(17.385044, 78.486671);
}

void main() {
  test('falls back to NoPositionService when the location service only '
      'resolves places', () async {
    final container = ProviderContainer(
      overrides: [locationServiceProvider.overrideWithValue(_PlaceOnly())],
    );
    addTearDown(container.dispose);

    expect(container.read(positionServiceProvider), isA<NoPositionService>());
    expect(await container.read(currentPositionProvider.future), isNull);
  });

  test('uses the location service itself when it also gives positions',
      () async {
    final service = _PlaceAndPosition();
    final container = ProviderContainer(
      overrides: [locationServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    expect(container.read(positionServiceProvider), same(service));
    expect(await container.read(currentPositionProvider.future),
        const GeoPoint(17.39, 78.49));
  });
}
```

Create `test/data/resort_search_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/location/geo_point.dart';
import 'package:pasala/data/models/resort_search.dart';

void main() {
  group('ResortSearchResult.fromJson', () {
    test('parses a full search_resorts row', () {
      final result = ResortSearchResult.fromJson(const <String, dynamic>{
        'id': 'r1',
        'name': 'Lakeview Retreat',
        'slug': 'lakeview',
        'description': 'Quiet lakeside cottages',
        'address': 'Gandipet Road, Hyderabad',
        'images': ['https://example.com/l.jpg'],
        'amenities': ['Pool', 'Wi-Fi'],
        'check_in_time': '14:00:00',
        'check_out_time': '11:00:00',
        'is_active': true,
        'lat': 17.385,
        'lng': 78.4867,
        'distance_km': 12.3,
        'min_price': 4000.00,
        'avg_rating': 4.5,
        'review_count': 2,
      });

      expect(result.property.id, 'r1');
      expect(result.property.name, 'Lakeview Retreat');
      expect(result.property.checkInTime, '14:00');
      expect(result.property.location, const GeoPoint(17.385, 78.4867));
      expect(result.distanceKm, 12.3);
      expect(result.minPrice, 4000);
      expect(result.avgRating, 4.5);
      expect(result.reviewCount, 2);
    });

    test('a row without distance, price or reviews parses to nulls and 0',
        () {
      final result = ResortSearchResult.fromJson(const <String, dynamic>{
        'id': 'r2',
        'name': 'Day Only Park',
        'slug': 'day-only',
        'images': [],
        'amenities': [],
        'lat': null,
        'lng': null,
        'distance_km': null,
        'min_price': null,
        'avg_rating': null,
        'review_count': 0,
      });

      expect(result.distanceKm, isNull);
      expect(result.minPrice, isNull);
      expect(result.avgRating, isNull);
      expect(result.reviewCount, 0);
      expect(result.property.location, isNull);
    });

    test('a whole-number distance arrives as an int and still parses', () {
      final result = ResortSearchResult.fromJson(const <String, dynamic>{
        'id': 'r3',
        'name': 'X',
        'slug': 'x',
        'distance_km': 12,
        'avg_rating': 5,
      });

      expect(result.distanceKm, 12.0);
      expect(result.avgRating, 5.0);
    });
  });

  group('ResortSearchQuery', () {
    test('the unfiltered query sends nulls and the recommended sort', () {
      expect(ResortSearchQuery.all.toParams(), {
        'p_query': null,
        'p_lat': null,
        'p_lng': null,
        'p_sort': 'recommended',
        'p_amenities': null,
      });
    });

    test('trims the text and sends every set field', () {
      const query = ResortSearchQuery(
        text: '  lake view ',
        sort: ResortSort.priceLow,
        amenities: ['Pool'],
        origin: GeoPoint(17.39, 78.49),
      );

      expect(query.toParams(), {
        'p_query': 'lake view',
        'p_lat': 17.39,
        'p_lng': 78.49,
        'p_sort': 'price',
        'p_amenities': ['Pool'],
      });
    });

    test('blank text sends a null query', () {
      expect(const ResortSearchQuery(text: '   ').toParams()['p_query'], isNull);
    });

    test('hasFilters is true for text or an amenity, not for a sort alone', () {
      expect(const ResortSearchQuery(text: '  ').hasFilters, isFalse);
      expect(const ResortSearchQuery(text: 'lake').hasFilters, isTrue);
      expect(const ResortSearchQuery(amenities: ['Pool']).hasFilters, isTrue);
      expect(const ResortSearchQuery(sort: ResortSort.rating).hasFilters, isFalse);
    });

    test('two queries with equal fields are equal, even with separate lists',
        () {
      final a = ResortSearchQuery(text: 'lake', amenities: List.of(['Pool']));
      final b = ResortSearchQuery(text: 'lake', amenities: List.of(['Pool']));

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(ResortSearchQuery(text: 'lake', amenities: List.of(['Spa']))));
      expect(
        const ResortSearchQuery(origin: GeoPoint(1, 2)),
        isNot(const ResortSearchQuery(origin: GeoPoint(2, 1))),
      );
    });
  });

  test('ResortSort maps to the server values and the screen labels', () {
    expect(ResortSort.values.map((s) => s.dbValue),
        ['recommended', 'distance', 'price', 'rating']);
    expect(ResortSort.values.map((s) => s.label),
        ['Recommended', 'Distance', 'Price: low to high', 'Rating']);
  });

  test('distanceLabel rounds to whole kilometres, with "< 1 km" below one', () {
    expect(distanceLabel(0.4), '< 1 km');
    expect(distanceLabel(1.0), '1 km');
    expect(distanceLabel(12.3), '12 km');
    expect(distanceLabel(455.3), '455 km');
  });
}
```

Create `test/data/resort_search_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/resort_search.dart';
import 'package:pasala/data/repositories/resort_search_repository.dart';

import '../support/fake_resort_search_source.dart';

void main() {
  test('resortSearchProvider asks the source for the query it is keyed by',
      () async {
    final source = FakeResortSearchSource()..results = [searchResult(id: 'r1')];
    final container = ProviderContainer(
      overrides: [resortSearchSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    const query = ResortSearchQuery(text: 'lake', sort: ResortSort.rating);
    final sub = container.listen(resortSearchProvider(query), (_, _) {});
    addTearDown(sub.close);

    final rows = await container.read(resortSearchProvider(query).future);

    expect(rows.single.property.id, 'r1');
    expect(source.calls, [query]);
  });

  test('an equal query built separately reuses the same search', () async {
    final source = FakeResortSearchSource();
    final container = ProviderContainer(
      overrides: [resortSearchSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    final first = ResortSearchQuery(amenities: List.of(['Pool']));
    final second = ResortSearchQuery(amenities: List.of(['Pool']));
    final sub = container.listen(resortSearchProvider(first), (_, _) {});
    addTearDown(sub.close);

    await container.read(resortSearchProvider(first).future);
    await container.read(resortSearchProvider(second).future);

    expect(source.calls, hasLength(1));
  });
}
```

Append to `test/data/property_test.dart`. Insert the group before the file's final closing `}` of `main()`:

```dart
  group('Property coordinates', () {
    test('reads lat/lng into latitude, longitude and location', () {
      final property = Property.fromJson(const {
        'id': 'p1',
        'name': 'Pasala Riverside',
        'slug': 'riverside',
        'lat': 17.385044,
        'lng': 78.486671,
      });

      expect(property.latitude, 17.385044);
      expect(property.longitude, 78.486671);
      expect(property.location, const GeoPoint(17.385044, 78.486671));
    });

    test('location is null when the resort has no coordinates', () {
      final property = Property.fromJson(const {
        'id': 'p1',
        'name': 'Pasala Riverside',
        'slug': 'riverside',
      });

      expect(property.latitude, isNull);
      expect(property.location, isNull);
    });

    test('toInsert never writes the coordinates (Map location owns them)', () {
      const property = Property(
        id: 'p1',
        name: 'Pasala Riverside',
        slug: 'riverside',
        description: null,
        address: null,
        images: [],
        amenities: [],
        checkInTime: '14:00',
        checkOutTime: '11:00',
        isActive: true,
        latitude: 17.3,
        longitude: 78.4,
      );

      expect(property.toInsert().containsKey('lat'), isFalse);
      expect(property.toInsert().containsKey('lng'), isFalse);
    });
  });
```

Also add this import at the top of `test/data/property_test.dart`:

```dart
import 'package:pasala/core/location/geo_point.dart';
```

In `test/core/errors_test.dart`, add after the `P0031 maps to AlreadyDispatched` test:

```dart
  test('P0041 maps to InvalidSearch with readable copy', () {
    final failure = map('P0041', 'invalid_search');
    expect(failure, isA<InvalidSearch>());
    expect(failure.message,
        'That search could not be run. Clear the filters and try again.');
  });
```

- [ ] **Step 8: Run them to verify they fail**

Run: `flutter test test/core/location/geo_point_test.dart test/core/location/position_service_test.dart test/data/resort_search_test.dart test/data/resort_search_provider_test.dart test/data/property_test.dart test/core/errors_test.dart`
Expected: FAIL to compile. The errors say `geo_point.dart`, `position_service.dart`, `resort_search.dart` and `fake_resort_search_source.dart` do not exist, and that `InvalidSearch` and `latitude` are undefined.

- [ ] **Step 9: Write the Dart contract**

Create `lib/core/location/geo_point.dart`:

```dart
/// A latitude/longitude pair in decimal degrees: the shape of
/// `properties.lat`/`lng` and of a device position fix.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// Within the ranges the `properties_lat_range` / `properties_lng_range`
  /// checks (0060_guest_search.sql) accept. NaN is never valid.
  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  /// Rounded to 2 decimal places, about 1 km. This is the only precision
  /// at which the guest's own position is cached or sent to this app's
  /// backend (spec decision 15).
  GeoPoint coarse() => GeoPoint(_round2(latitude), _round2(longitude));

  static double _round2(double value) => (value * 100).roundToDouble() / 100;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}
```

Create `lib/core/location/position_service.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'geo_point.dart';
import 'location_service.dart';

/// The device's position as a coordinate. The browse screen uses it for
/// the Distance sort and card distances, and the owner's Map location
/// screen uses it for "Use my current location". Abstract, so tests
/// override [positionServiceProvider] with `FakePositionService` instead
/// of touching geolocator.
abstract class PositionService {
  /// The guest's position, already rounded with [GeoPoint.coarse], from a
  /// low-accuracy fix that is cached for 24 h. Null when it cannot be
  /// resolved (permission denied, location off, no platform support).
  /// Never throws.
  Future<GeoPoint?> approximatePosition();

  /// A fresh high-accuracy fix, never cached, or null. Never throws. Only
  /// the owner's Map location screen asks for it.
  Future<GeoPoint?> precisePosition();
}

/// No position at all: what a place-only [LocationService] (e.g. a test
/// fake) provides.
class NoPositionService implements PositionService {
  const NoPositionService();

  @override
  Future<GeoPoint?> approximatePosition() async => null;

  @override
  Future<GeoPoint?> precisePosition() async => null;
}

/// The same object as [locationServiceProvider] when it can also give
/// positions (the real `DeviceLocationService`), so the badge and the
/// Distance sort share one device fix and one permission prompt.
/// Otherwise [NoPositionService].
final positionServiceProvider = Provider<PositionService>((ref) {
  final location = ref.watch(locationServiceProvider);
  return switch (location) {
    final PositionService position => position,
    _ => const NoPositionService(),
  };
});

/// The guest's coarse position for the browse screen. Not `autoDispose`,
/// the same as `currentPlaceProvider`: `LocationBadge`'s "Set location"
/// invalidates both.
final currentPositionProvider = FutureProvider<GeoPoint?>(
  (ref) => ref.watch(positionServiceProvider).approximatePosition(),
);
```

Create `lib/data/models/resort_search.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../core/location/geo_point.dart';
import 'property.dart';

/// The browse screen's sort options, in menu order.
enum ResortSort { recommended, distance, priceLow, rating }

extension ResortSortX on ResortSort {
  /// The `p_sort` value `search_resorts` expects.
  String get dbValue => switch (this) {
        ResortSort.recommended => 'recommended',
        ResortSort.distance => 'distance',
        ResortSort.priceLow => 'price',
        ResortSort.rating => 'rating',
      };

  String get label => switch (this) {
        ResortSort.recommended => 'Recommended',
        ResortSort.distance => 'Distance',
        ResortSort.priceLow => 'Price: low to high',
        ResortSort.rating => 'Rating',
      };
}

/// One call to `search_resorts`. Value-equal, so it can key
/// `resortSearchProvider`: rebuilding the browse screen with the same
/// filters reuses the same search instead of starting a new one.
@immutable
class ResortSearchQuery {
  const ResortSearchQuery({
    this.text = '',
    this.sort = ResortSort.recommended,
    this.amenities = const [],
    this.origin,
  });

  /// Every active resort, recommended order, no position: the source of
  /// the amenity chips.
  static const all = ResortSearchQuery();

  final String text;
  final ResortSort sort;
  final List<String> amenities;

  /// The guest's position, already rounded by the caller.
  final GeoPoint? origin;

  /// A search term or an amenity is narrowing the list. A sort alone never
  /// hides a resort.
  bool get hasFilters => text.trim().isNotEmpty || amenities.isNotEmpty;

  Map<String, dynamic> toParams() {
    final trimmed = text.trim();
    return {
      'p_query': trimmed.isEmpty ? null : trimmed,
      'p_lat': origin?.latitude,
      'p_lng': origin?.longitude,
      'p_sort': sort.dbValue,
      'p_amenities': amenities.isEmpty ? null : amenities,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ResortSearchQuery &&
      other.text == text &&
      other.sort == sort &&
      listEquals(other.amenities, amenities) &&
      other.origin == origin;

  @override
  int get hashCode =>
      Object.hash(text, sort, Object.hashAll(amenities), origin);
}

/// One `search_resorts` row: the resort's card fields plus what search
/// adds. [distanceKm] is null without a position or without coordinates.
/// [minPrice] is null for a resort with no nightly rate. [avgRating] is
/// null when [reviewCount] is 0.
class ResortSearchResult {
  const ResortSearchResult({
    required this.property,
    this.distanceKm,
    this.minPrice,
    this.avgRating,
    this.reviewCount = 0,
  });

  final Property property;
  final double? distanceKm;
  final num? minPrice;
  final double? avgRating;
  final int reviewCount;

  factory ResortSearchResult.fromJson(Map<String, dynamic> json) =>
      ResortSearchResult(
        property: Property.fromJson(json),
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        minPrice: json['min_price'] as num?,
        avgRating: (json['avg_rating'] as num?)?.toDouble(),
        reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      );
}

/// A card's distance: `< 1 km` below one kilometre, whole kilometres
/// above it. The origin is only accurate to about 1 km (it is coarse), so
/// decimals would promise more than we know.
String distanceLabel(double km) => km < 1 ? '< 1 km' : '${km.round()} km';
```

Create `lib/data/repositories/resort_search_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/resort_search.dart';

/// What the browse screen needs from search. Tests override
/// [resortSearchSourceProvider] with `FakeResortSearchSource`
/// (test/support/fake_resort_search_source.dart).
abstract class ResortSearchSource {
  Future<List<ResortSearchResult>> search(ResortSearchQuery query);
}

/// Backs search with `search_resorts` (0060_guest_search.sql). Anon may
/// call it, so this works signed out. A bad input comes back as P0041,
/// which [mapPostgrestError] turns into `InvalidSearch`.
class ResortSearchRepository implements ResortSearchSource {
  ResortSearchRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<List<ResortSearchResult>> search(ResortSearchQuery query) =>
      _guard(() async {
        final rows = await _db.rpc('search_resorts', params: query.toParams())
            as List<dynamic>;
        return rows
            .map((e) => ResortSearchResult.fromJson(e as Map<String, dynamic>))
            .toList();
      });
}

final resortSearchRepositoryProvider = Provider<ResortSearchRepository>(
  (ref) => ResortSearchRepository(ref.watch(supabaseProvider)),
);

/// The [ResortSearchSource] seam every screen calls through.
final resortSearchSourceProvider = Provider<ResortSearchSource>(
  (ref) => ref.watch(resortSearchRepositoryProvider),
);

/// One search, keyed by its query. `autoDispose`: a guest typing leaves a
/// trail of abandoned queries, and each is dropped once no widget watches
/// it.
final resortSearchProvider = FutureProvider.autoDispose
    .family<List<ResortSearchResult>, ResortSearchQuery>(
      (ref, query) => ref.watch(resortSearchSourceProvider).search(query),
    );
```

In `lib/data/models/property.dart`:

1. Add the import at the top of the file:

```dart
import '../../core/location/geo_point.dart';
```

2. In the constructor, replace:

```dart
    this.paymentDisplayMethods = const [],
    this.gatewayDisplayName,
  });
```

with:

```dart
    this.paymentDisplayMethods = const [],
    this.gatewayDisplayName,
    this.latitude,
    this.longitude,
  });
```

3. Replace:

```dart
  final List<String> paymentDisplayMethods;
  final String? gatewayDisplayName;
```

with:

```dart
  final List<String> paymentDisplayMethods;
  final String? gatewayDisplayName;

  /// `properties.lat`/`lng`: the resort's map position. The owner sets it
  /// on the Map location screen through `CatalogRepository.updateSettings`,
  /// and it is not part of [toInsert]. The table requires both or neither
  /// (0060_guest_search.sql).
  final double? latitude;
  final double? longitude;

  GeoPoint? get location => latitude != null && longitude != null
      ? GeoPoint(latitude!, longitude!)
      : null;
```

4. In `fromJson`, replace:

```dart
        gatewayDisplayName: json['gateway_display_name'] as String?,
      );
```

with:

```dart
        gatewayDisplayName: json['gateway_display_name'] as String?,
        latitude: (json['lat'] as num?)?.toDouble(),
        longitude: (json['lng'] as num?)?.toDouble(),
      );
```

In `lib/core/errors.dart`:

1. After the `AlreadyDispatched` class, add:

```dart
/// P0041 -- `search_resorts` refused its input: an unknown sort, half a
/// position, an out-of-range coordinate, or a query over 100 characters.
/// The browse screen never sends any of these, so this is a backstop.
class InvalidSearch extends BookingFailure {
  const InvalidSearch()
      : super('That search could not be run. Clear the filters and try again.');
}
```

2. In `mapPostgrestError`, replace:

```dart
    'P0031' => const AlreadyDispatched(),
```

with:

```dart
    'P0031' => const AlreadyDispatched(),
    // P0041: guest search (0060). The server sends the bare code word
    // `invalid_search`, so the copy lives here.
    'P0041' => const InvalidSearch(),
```

Create `test/support/fake_resort_search_source.dart`:

```dart
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/resort_search.dart';
import 'package:pasala/data/repositories/resort_search_repository.dart';

/// In-memory [ResortSearchSource].
/// - [results]: what every search returns. [respond] computes the answer
///   per query instead (see [respondLikeServer]).
/// - [error]: when set, every search throws it.
/// - [hold]: when set, each search waits for it before answering.
/// - [calls]: every query a screen asked for, in order.
class FakeResortSearchSource implements ResortSearchSource {
  List<ResortSearchResult> results = [];
  List<ResortSearchResult> Function(ResortSearchQuery query)? respond;
  Object? error;
  Future<void>? hold;
  final List<ResortSearchQuery> calls = [];

  @override
  Future<List<ResortSearchResult>> search(ResortSearchQuery query) async {
    calls.add(query);
    final gate = hold;
    if (gate != null) await gate;
    if (error != null) throw error!;
    return respond?.call(query) ?? results;
  }
}

/// A [FakeResortSearchSource.respond] that narrows [all] the way
/// `search_resorts` does:
/// - every word must appear in the name, address, description or
///   amenities
/// - every requested amenity must be present
/// - comparison is case-insensitive
///
/// It keeps [all]'s order. Sorting is the server's job, and pgTAP tests
/// it.
List<ResortSearchResult> Function(ResortSearchQuery) respondLikeServer(
  List<ResortSearchResult> all,
) =>
    (query) {
      final words = query.text
          .trim()
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty);
      final wanted = query.amenities
          .map((a) => a.trim().toLowerCase())
          .where((a) => a.isNotEmpty);
      return all.where((r) {
        final p = r.property;
        final haystack = [
          p.name,
          p.address ?? '',
          p.description ?? '',
          p.amenities.join(' '),
        ].join(' ').toLowerCase();
        final have = p.amenities.map((a) => a.toLowerCase()).toSet();
        return words.every(haystack.contains) && wanted.every(have.contains);
      }).toList();
    };

/// A search row with defaults. Override only what a test is about.
ResortSearchResult searchResult({
  String id = 'r1',
  String name = 'Lakeview Retreat',
  String? description,
  String? address,
  List<String> images = const [],
  List<String> amenities = const [],
  double? distanceKm,
  num? minPrice,
  double? avgRating,
  int reviewCount = 0,
}) =>
    ResortSearchResult(
      property: Property(
        id: id,
        name: name,
        slug: id,
        description: description,
        address: address,
        images: images,
        amenities: amenities,
        checkInTime: '14:00',
        checkOutTime: '11:00',
        isActive: true,
      ),
      distanceKm: distanceKm,
      minPrice: minPrice,
      avgRating: avgRating,
      reviewCount: reviewCount,
    );
```

Create `test/support/fake_position_service.dart`:

```dart
import 'package:pasala/core/location/geo_point.dart';
import 'package:pasala/core/location/position_service.dart';

/// A [PositionService] that answers from fields and counts its calls.
class FakePositionService implements PositionService {
  FakePositionService({this.approximate, this.precise});

  GeoPoint? approximate;
  GeoPoint? precise;
  int approximateCalls = 0;
  int preciseCalls = 0;

  @override
  Future<GeoPoint?> approximatePosition() async {
    approximateCalls++;
    return approximate;
  }

  @override
  Future<GeoPoint?> precisePosition() async {
    preciseCalls++;
    return precise;
  }
}
```

- [ ] **Step 10: Run the Dart tests and the analyzer to verify they pass**

Run: `flutter test test/core/location/geo_point_test.dart test/core/location/position_service_test.dart test/data/resort_search_test.dart test/data/resort_search_provider_test.dart test/data/property_test.dart test/core/errors_test.dart && flutter analyze`
Expected: all PASS. The analyzer shows only the baseline issues.

- [ ] **Step 11: Commit**

```bash
git add supabase/migrations/0060_guest_search.sql supabase/tests/50_guest_search_test.sql \
  supabase/tests/37_tenancy_isolation_test.sql \
  lib/core/location/geo_point.dart lib/core/location/position_service.dart \
  lib/data/models/resort_search.dart lib/data/repositories/resort_search_repository.dart \
  lib/data/models/property.dart lib/core/errors.dart \
  test/support/fake_resort_search_source.dart test/support/fake_position_service.dart \
  test/core/location/geo_point_test.dart test/core/location/position_service_test.dart \
  test/data/resort_search_test.dart test/data/resort_search_provider_test.dart \
  test/data/property_test.dart test/core/errors_test.dart
git commit -m "feat(search): P11 contract - coordinate checks, search_resorts stub, Dart search API" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Phase 1: Database track (Tasks 2 → 3, sequential)

### Task 2: `search_resorts` filtering and card fields

**Track:** DB. **Depends on:** Task 1.

**Files:**
- Modify: `supabase/migrations/0060_guest_search.sql` (replace the stub body)
- Test: `supabase/tests/50_guest_search_test.sql`

**Interfaces:**
- Consumes: the Task 1 signature and fixtures, and the helpers `pg_temp.found_set`.
- Produces: `search_resorts` returns the right rows with correct `min_price`, `avg_rating`, `review_count` and `distance_km`, and raises P0041 on bad input. At this stage rows are ordered by `name, id`; Task 3 replaces only the ordering.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/50_guest_search_test.sql`, change `select plan(10);` to `select plan(43);`. Then insert this section immediately before `select * from finish();`:

```sql
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/50_guest_search_test.sql`
Expected: FAIL. The first Task 2 assertion dies with `search_resorts is not implemented yet` (SQLSTATE 0A000).

- [ ] **Step 3: Write the implementation**

In `supabase/migrations/0060_guest_search.sql`, replace the whole stub, from `create function public.search_resorts(` through its closing `$$;`. Keep the comment block above it and the `revoke`/`grant` lines below it. The replacement is:

```sql
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
           coalesce(rt.review_count, 0)               as review_count
      from matched m
      left join prices  pr on pr.property_id = m.id
      left join ratings rt on rt.property_id = m.id
  )
  select c.id, c.name, c.slug, c.description, c.address, c.images,
         c.amenities, c.check_in_time, c.check_out_time, c.is_active,
         c.lat, c.lng, c.distance_km, c.min_price, c.avg_rating,
         c.review_count
    from cards c
   order by c.name, c.id;
end;
$$;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/50_guest_search_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: PASS. File 50 reports 43/43 and file 37 reports 77/77.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0060_guest_search.sql supabase/tests/50_guest_search_test.sql
git commit -m "feat(search): search_resorts filters active resorts and returns price, rating, distance" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Sort orders, who can search, and who can set coordinates

**Track:** DB. **Depends on:** Task 2.

**Files:**
- Modify: `supabase/migrations/0060_guest_search.sql` (the `cards` CTE and the final `order by`)
- Test: `supabase/tests/50_guest_search_test.sql`

**Interfaces:**
- Consumes: Task 2's `search_resorts`, the helpers `pg_temp.found`, `pg_temp.found_set` and `pg_temp.rows_affected`, and the fixture users.
- Produces: the four sort orders from spec decision 13, including the fallback when distance is requested without a position. It also pins, with tests, that members see the guest list and that owners, not staff or guests, write coordinates.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/50_guest_search_test.sql`, change `select plan(43);` to `select plan(57);`. Then insert this section immediately before `select * from finish();`:

```sql
-- === Task 3: sort orders, who can search, and who can set coordinates ====
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

-- Recommended score (sum of ratings + 12) / (count + 3):
-- Coastal 17/4 = 4.25, Lakeview 21/5 = 4.2, Hilltop 4.0 (photo),
-- Day Only 4.0 (no photo).
select is(pg_temp.found(),
  array['Coastal Nest','Lakeview Retreat','Hilltop Farm','Day Only Park'],
  'recommended: shrunk rating first, then resorts with a photo');
select is(pg_temp.found(p_sort => 'recommended'),
  array['Coastal Nest','Lakeview Retreat','Hilltop Farm','Day Only Park'],
  'recommended is also the default');
select is(pg_temp.found(p_sort => 'price'),
  array['Hilltop Farm','Lakeview Retreat','Coastal Nest','Day Only Park'],
  'price: cheapest nightly price first, no price last');
select is(pg_temp.found(p_sort => 'rating'),
  array['Coastal Nest','Lakeview Retreat','Day Only Park','Hilltop Farm'],
  'rating: best average first, unrated last by name');
select is(pg_temp.found(p_lat => 17.39, p_lng => 78.49, p_sort => 'distance'),
  array['Lakeview Retreat','Day Only Park','Hilltop Farm','Coastal Nest'],
  'distance: nearest first, no coordinates last');
select is(pg_temp.found(p_sort => 'distance'),
  array['Coastal Nest','Lakeview Retreat','Hilltop Farm','Day Only Park'],
  'distance without a position falls back to recommended');
select is(pg_temp.found(p_sort => 'price', p_amenities => array['Pool']),
  array['Lakeview Retreat','Coastal Nest'],
  'a filtered search keeps its sort');

set local role authenticated;
set local request.jwt.claims to '{"sub":"c1100000-0000-4000-8000-0000000000a1","role":"authenticated"}';
select is(pg_temp.found(),
  array['Coastal Nest','Lakeview Retreat','Hilltop Farm','Day Only Park'],
  'a signed-in guest gets the same results as anon');

set local request.jwt.claims to '{"sub":"c1100000-0000-4000-8000-0000000000a4","role":"authenticated"}';
select is(pg_temp.found_set('closed'), '{}'::text[],
  'the owner of a suspended resort does not find it either');
select is(pg_temp.found(),
  array['Coastal Nest','Lakeview Retreat','Hilltop Farm','Day Only Park'],
  'a resort member sees exactly the guest list');

set local request.jwt.claims to '{"sub":"c1100000-0000-4000-8000-0000000000a3","role":"authenticated"}';
select is(pg_temp.rows_affected(
    $$update public.properties set lat = 1, lng = 1 where slug = 'p11-lakeview'$$),
  0, 'staff cannot move their resort');
set local request.jwt.claims to '{"sub":"c1100000-0000-4000-8000-0000000000a1","role":"authenticated"}';
select is(pg_temp.rows_affected(
    $$update public.properties set lat = 1, lng = 1 where slug = 'p11-lakeview'$$),
  0, 'a guest cannot move a resort');
set local request.jwt.claims to '{"sub":"c1100000-0000-4000-8000-0000000000a2","role":"authenticated"}';
select is(pg_temp.rows_affected(
    $$update public.properties set lat = 17.4, lng = 78.5 where slug = 'p11-lakeview'$$),
  1, 'the owner sets their resort''s coordinates');
select is((select s.distance_km from public.search_resorts(null, 17.4, 78.5) s
            where s.slug = 'p11-lakeview'),
  0.0::numeric, 'search uses the coordinates the owner saved');

reset role;
set local request.jwt.claims to '';
```

- [ ] **Step 2: Run it to verify it fails**

Run: `supabase test db supabase/tests/50_guest_search_test.sql`
Expected: FAIL. The recommended, price, rating and distance assertions report the alphabetical order `{Coastal Nest,Day Only Park,Hilltop Farm,Lakeview Retreat}`. The access and owner-write assertions already pass.

- [ ] **Step 3: Write the implementation**

In `supabase/migrations/0060_guest_search.sql`, inside `search_resorts`, make two edits.

1. In the `cards` CTE, replace:

```sql
           coalesce(rt.review_count, 0)               as review_count
      from matched m
```

with:

```sql
           coalesce(rt.review_count, 0)               as review_count,
           -- Recommended: the average shrunk toward 4 by three phantom
           -- reviews, so one 5-star review does not outrank many 4.5s.
           (coalesce(rt.rating_sum, 0) + 12)
             / (coalesce(rt.review_count, 0) + 3)     as score,
           cardinality(m.images) > 0                  as has_photo
      from matched m
```

2. Replace:

```sql
    from cards c
   order by c.name, c.id;
```

with:

```sql
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/50_guest_search_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: PASS. File 50 reports 57/57 and file 37 reports 77/77.

- [ ] **Step 5: Run the whole pgTAP suite**

Run: `supabase test db 2>&1 | tail -20`
Expected: every file passes except the known 00:00–05:30 IST ones, if you are in that window.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/0060_guest_search.sql supabase/tests/50_guest_search_test.sql
git commit -m "feat(search): recommended, distance, price and rating sort orders" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Phase 2: App track (after Task 1; 4, 5 and 7 in parallel, 6 after 5)

### Task 4: The device position behind the badge

**Track:** App. **Depends on:** Task 1.

**Files:**
- Modify: `lib/core/location/location_cache.dart`
- Modify: `lib/core/location/device_location_service.dart`
- Modify: `lib/features/browse/location_badge.dart`
- Test: `test/core/location/location_cache_test.dart`, `test/features/browse/location_badge_test.dart`

**Interfaces:**
- Consumes: `GeoPoint`, `PositionService`, `positionServiceProvider`, `currentPositionProvider` and `FakePositionService` (Task 1).
- Produces:
  - `LocationCache.readPoint()` → `GeoPoint?` and `LocationCache.writePoint(GeoPoint)` → `Future<void>`. It always stores the coarse point under the keys `location_cache_lat`, `location_cache_lng` and `location_cache_point_at_ms`.
  - `DeviceLocationService implements LocationService, PositionService`.
  - `LocationBadge`'s "Set location" invalidates `currentPlaceProvider` and `currentPositionProvider`.

- [ ] **Step 1: Write the failing tests**

Append to `test/core/location/location_cache_test.dart`, inside `main()`, after the last existing test:

```dart
  group('position', () {
    test('readPoint() is null when no point has been cached', () async {
      SharedPreferences.setMockInitialValues({});
      final cache = LocationCache(await SharedPreferences.getInstance());

      expect(cache.readPoint(), isNull);
    });

    test('writePoint() stores only the coarse point, and readPoint() returns '
        'it within 24h', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime(2026, 1, 1, 12);
      final cache = LocationCache(prefs, clock: () => now);

      await cache.writePoint(const GeoPoint(17.38512, 78.48671));
      now = now.add(const Duration(hours: 23, minutes: 59));

      expect(cache.readPoint(), const GeoPoint(17.39, 78.49));
      expect(prefs.getDouble('location_cache_lat'), 17.39);
      expect(prefs.getDouble('location_cache_lng'), 78.49);
    });

    test('readPoint() is null once the point is 24h old', () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 1, 1, 12);
      final cache =
          LocationCache(await SharedPreferences.getInstance(), clock: () => now);

      await cache.writePoint(const GeoPoint(17.39, 78.49));
      now = now.add(const Duration(hours: 24, minutes: 1));

      expect(cache.readPoint(), isNull);
    });

    test('the place and the point expire independently', () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 1, 1, 12);
      final cache =
          LocationCache(await SharedPreferences.getInstance(), clock: () => now);

      await cache.write(label);
      now = now.add(const Duration(hours: 23));
      await cache.writePoint(const GeoPoint(17.39, 78.49));
      now = now.add(const Duration(hours: 2));

      expect(cache.read(), isNull);
      expect(cache.readPoint(), const GeoPoint(17.39, 78.49));
    });
  });
```

Add this import to the top of `test/core/location/location_cache_test.dart`:

```dart
import 'package:pasala/core/location/geo_point.dart';
```

Append to `test/features/browse/location_badge_test.dart`, inside `main()`, after the last existing test:

```dart
  testWidgets('"Set location" also asks for the position again', (
    tester,
  ) async {
    final service = _FakeLocationService(() async => null);
    final position = FakePositionService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(service),
          positionServiceProvider.overrideWithValue(position),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const LocationBadge(),
                // Stands in for the browse screen, which watches the
                // position for its Distance sort.
                Consumer(
                  builder: (context, ref, _) {
                    ref.watch(currentPositionProvider);
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(position.approximateCalls, 1);

    await tester.tap(find.text('Set location'));
    await tester.pumpAndSettle();

    expect(service.callCount, 2);
    expect(position.approximateCalls, 2);
  });
```

Add these imports to the top of `test/features/browse/location_badge_test.dart`:

```dart
import 'package:pasala/core/location/position_service.dart';

import '../../support/fake_position_service.dart';
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/location/location_cache_test.dart test/features/browse/location_badge_test.dart`
Expected: FAIL. `readPoint` and `writePoint` are not defined, and the badge test reports `approximateCalls` of 1 where 2 was expected.

- [ ] **Step 3: Write the implementation**

In `lib/core/location/location_cache.dart`:

1. Add the import after `import 'package:shared_preferences/shared_preferences.dart';`:

```dart
import 'geo_point.dart';
```

2. Replace:

```dart
  static const _cachedAtKey = 'location_cache_cached_at_ms';
```

with:

```dart
  static const _cachedAtKey = 'location_cache_cached_at_ms';

  static const _latKey = 'location_cache_lat';
  static const _lngKey = 'location_cache_lng';
  static const _pointAtKey = 'location_cache_point_at_ms';
```

3. Add these two methods after `write`, before the class's closing `}`:

```dart
  /// The cached coarse position, or null when nothing is cached or it is
  /// older than [validFor]. Kept apart from the place label: each is
  /// written when it resolves, so each expires on its own.
  GeoPoint? readPoint() {
    final lat = _prefs.getDouble(_latKey);
    final lng = _prefs.getDouble(_lngKey);
    final cachedAtMs = _prefs.getInt(_pointAtKey);
    if (lat == null || lng == null || cachedAtMs == null) return null;

    final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
    if (_clock().difference(cachedAt) > validFor) return null;

    return GeoPoint(lat, lng);
  }

  /// Persists [point] rounded with [GeoPoint.coarse], whatever precision
  /// the caller passed. No exact position is ever stored on the device.
  Future<void> writePoint(GeoPoint point) async {
    final coarse = point.coarse();
    await _prefs.setDouble(_latKey, coarse.latitude);
    await _prefs.setDouble(_lngKey, coarse.longitude);
    await _prefs.setInt(_pointAtKey, _clock().millisecondsSinceEpoch);
  }
```

Replace the whole of `lib/core/location/device_location_service.dart` with:

```dart
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'geo_point.dart';
import 'location_cache.dart';
import 'location_service.dart';
import 'nominatim.dart';
import 'place_label.dart';
import 'position_service.dart';

/// The real [LocationService] and [PositionService]. It checks and
/// requests the device permission, takes a position fix, and
/// reverse-geocodes it against OpenStreetMap's Nominatim.
///
/// The label and a coarse position are each cached for
/// [LocationCache.validFor], so a returning guest is not asked again on
/// every app open. Only a coarse ([GeoPoint.coarse]) position is ever
/// sent to this app's backend, for distance sorting. The exact
/// coordinate goes only to Nominatim, to resolve a city name.
class DeviceLocationService implements LocationService, PositionService {
  DeviceLocationService({required Future<SharedPreferences> prefs, http.Client? client})
    : _prefsFuture = prefs,
      _client = client ?? http.Client();

  final Future<SharedPreferences> _prefsFuture;
  final http.Client _client;

  /// The low-accuracy fix in flight, shared by [currentPlace] and
  /// [approximatePosition]. The browse screen asks for both at once, and
  /// without sharing a cold start would request the permission twice.
  Future<Position?>? _lowFix;

  static const _reverseUrl = 'https://nominatim.openstreetmap.org/reverse';

  @override
  Future<PlaceLabel?> currentPlace() async {
    // Wrapped end-to-end, not just around the geolocator/http calls:
    // `_prefsFuture` and `cache.write` are fallible too, and must degrade
    // to "unresolved" like a denied permission, never an uncaught error.
    try {
      final prefs = await _prefsFuture;
      final cache = LocationCache(prefs);

      final cached = cache.read();
      if (cached != null) return cached;

      final position = await _sharedLowFix();
      if (position == null) return null;
      final resolved =
          await _reverseGeocode(position.latitude, position.longitude);
      if (resolved != null) await cache.write(resolved);
      return resolved;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<GeoPoint?> approximatePosition() async {
    try {
      final prefs = await _prefsFuture;
      final cache = LocationCache(prefs);

      final cached = cache.readPoint();
      if (cached != null) return cached;

      final position = await _sharedLowFix();
      if (position == null) return null;
      final point = GeoPoint(position.latitude, position.longitude).coarse();
      await cache.writePoint(point);
      return point;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<GeoPoint?> precisePosition() async {
    try {
      final position = await _fix(LocationAccuracy.high);
      return position == null
          ? null
          : GeoPoint(position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<Position?> _sharedLowFix() => _lowFix ??=
      _fix(LocationAccuracy.low).whenComplete(() => _lowFix = null);

  Future<Position?> _fix(LocationAccuracy accuracy) async {
    if (!await _hasPermission()) return null;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: accuracy),
      );
    } catch (_) {
      // Location services off, a platform error, or a timed-out fix --
      // none of these should crash a caller, just leave it unresolved.
      return null;
    }
  }

  Future<bool> _hasPermission() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (_) {
      // No host platform implementation (e.g. web without the geolocator
      // web plugin registered, or a test harness with no platform channel)
      // -- treat exactly like a denial rather than crashing.
      return false;
    }
  }

  Future<PlaceLabel?> _reverseGeocode(double lat, double lon) async {
    final uri = Uri.parse(_reverseUrl).replace(
      queryParameters: {
        'format': 'jsonv2',
        'zoom': '10',
        'lat': '$lat',
        'lon': '$lon',
      },
    );

    try {
      final response = await _client.get(
        uri,
        // Nominatim's usage policy requires an identifying User-Agent for
        // every request.
        headers: const {'User-Agent': 'ResortHub/1.0 (guest browse hero)'},
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      return parseNominatimReverse(body);
    } catch (_) {
      // A network failure must never surface as an error state on the
      // badge -- just leave the location unresolved.
      return null;
    }
  }
}
```

In `lib/features/browse/location_badge.dart`:

1. Add the import after `import '../../core/location/location_service.dart';`:

```dart
import '../../core/location/position_service.dart';
```

2. Replace:

```dart
      error: (_, _) => _SetLocationChip(
        onTap: () => ref.invalidate(currentPlaceProvider),
      ),
      data: (label) => label == null
          ? _SetLocationChip(onTap: () => ref.invalidate(currentPlaceProvider))
          : _PlaceLabelText(text: '${label.locality}, ${label.country}'),
    );
  }
```

with:

```dart
      error: (_, _) => _SetLocationChip(onTap: () => _retry(ref)),
      data: (label) => label == null
          ? _SetLocationChip(onTap: () => _retry(ref))
          : _PlaceLabelText(text: '${label.locality}, ${label.country}'),
    );
  }

  /// "Set location" asks again for both the badge's place and the
  /// position behind the browse screen's Distance sort, so granting the
  /// permission here enables both.
  static void _retry(WidgetRef ref) {
    ref.invalidate(currentPlaceProvider);
    ref.invalidate(currentPositionProvider);
  }
```

- [ ] **Step 4: Run the tests and the analyzer to verify they pass**

Run: `flutter test test/core/location/ test/features/browse/location_badge_test.dart && flutter analyze`
Expected: PASS. The analyzer shows only the baseline issues.

- [ ] **Step 5: Commit**

```bash
git add lib/core/location/location_cache.dart lib/core/location/device_location_service.dart \
  lib/features/browse/location_badge.dart \
  test/core/location/location_cache_test.dart test/features/browse/location_badge_test.dart
git commit -m "feat(search): the device gives a coarse, cached position alongside the badge's place" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: The card's rating, distance and price line

**Track:** App. **Depends on:** Task 1.

**Files:**
- Create: `lib/features/browse/resort_meta_line.dart`
- Modify: `lib/features/browse/browse_screen.dart` (only the imports and `PropertyCard`)
- Test: `test/features/browse/resort_meta_line_test.dart`, `test/features/browse/property_card_test.dart`

**Interfaces:**
- Consumes: `distanceLabel` (Task 1) and `formatInr` (`lib/core/format.dart`).
- Produces:
  - `ResortMetaLine({double? avgRating, int reviewCount = 0, double? distanceKm, num? minPrice})`.
  - `PropertyCard({required Property property, VoidCallback? onTap, double? distanceKm, num? minPrice, double? avgRating, int reviewCount = 0})`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/browse/resort_meta_line_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/browse/resort_meta_line.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('shows rating, distance and price', (tester) async {
    await tester.pumpWidget(_wrap(const ResortMetaLine(
      avgRating: 4.5,
      reviewCount: 2,
      distanceKm: 12.3,
      minPrice: 4000,
    )));

    expect(find.text('4.5 (2)'), findsOneWidget);
    expect(find.text('12 km'), findsOneWidget);
    expect(find.text('from ₹4,000 / night'), findsOneWidget);
    expect(find.bySemanticsLabel('Rated 4.5 out of 5 from 2 reviews'),
        findsOneWidget);
    expect(find.bySemanticsLabel('12 km away'), findsOneWidget);
  });

  testWidgets('a single review reads "1 review"', (tester) async {
    await tester.pumpWidget(
        _wrap(const ResortMetaLine(avgRating: 5, reviewCount: 1)));

    expect(find.text('5.0 (1)'), findsOneWidget);
    expect(find.bySemanticsLabel('Rated 5.0 out of 5 from 1 review'),
        findsOneWidget);
  });

  testWidgets('a nearby resort reads "< 1 km"', (tester) async {
    await tester.pumpWidget(_wrap(const ResortMetaLine(distanceKm: 0.6)));

    expect(find.text('< 1 km'), findsOneWidget);
  });

  testWidgets('shows no rating without reviews', (tester) async {
    await tester.pumpWidget(
        _wrap(const ResortMetaLine(avgRating: 4.0, reviewCount: 0, minPrice: 2500)));

    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.text('from ₹2,500 / night'), findsOneWidget);
  });

  testWidgets('renders nothing when there is nothing to show', (tester) async {
    await tester.pumpWidget(_wrap(const ResortMetaLine()));

    expect(find.byType(Wrap), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
```

Append to `test/features/browse/property_card_test.dart`, inside `main()`, after the last existing test:

```dart
  testWidgets('shows the search meta line when search data is given',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PropertyCard(
            property: property,
            distanceKm: 12.3,
            minPrice: 4000,
            avgRating: 4.5,
            reviewCount: 2,
          ),
        ),
      ),
    ));

    expect(find.text('4.5 (2)'), findsOneWidget);
    expect(find.text('12 km'), findsOneWidget);
    expect(find.text('from ₹4,000 / night'), findsOneWidget);
  });

  testWidgets('a day-use-only resort shows distance and rating but no price',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PropertyCard(
            property: property,
            distanceKm: 3,
            avgRating: 4.0,
            reviewCount: 3,
          ),
        ),
      ),
    ));

    expect(find.text('3 km'), findsOneWidget);
    expect(find.textContaining('₹'), findsNothing);
  });

  testWidgets('without search data the card looks as before (admin screens)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PropertyCard(property: property)),
    ));

    expect(find.byIcon(Icons.near_me_outlined), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.textContaining('/ night'), findsNothing);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/browse/resort_meta_line_test.dart test/features/browse/property_card_test.dart`
Expected: FAIL to compile. `resort_meta_line.dart` does not exist, and `PropertyCard` has no parameter `distanceKm`.

- [ ] **Step 3: Write the implementation**

Create `lib/features/browse/resort_meta_line.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/resort_search.dart';

/// A browse card's summary line: the rating, the distance and the lowest
/// nightly price. Each piece shows only when `search_resorts` returned it.
/// It renders nothing when there is nothing to show, so admin screens
/// that reuse `PropertyCard` without search data look exactly as before.
/// Every piece carries an icon and text; none relies on colour.
class ResortMetaLine extends StatelessWidget {
  const ResortMetaLine({
    super.key,
    this.avgRating,
    this.reviewCount = 0,
    this.distanceKm,
    this.minPrice,
  });

  final double? avgRating;
  final int reviewCount;
  final double? distanceKm;
  final num? minPrice;

  bool get _hasRating => avgRating != null && reviewCount > 0;

  @override
  Widget build(BuildContext context) {
    if (!_hasRating && distanceKm == null && minPrice == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: scheme.onSurfaceVariant);

    Widget piece(IconData icon, String text, String semantics) => Semantics(
          label: semantics,
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: Spacing.xs),
              Text(text, style: style),
            ],
          ),
        );

    final rating = avgRating?.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Wrap(
        spacing: Spacing.md,
        runSpacing: Spacing.xs,
        children: [
          if (_hasRating)
            piece(
              Icons.star_rounded,
              '$rating ($reviewCount)',
              'Rated $rating out of 5 from $reviewCount '
                  '${reviewCount == 1 ? 'review' : 'reviews'}',
            ),
          if (distanceKm != null)
            piece(
              Icons.near_me_outlined,
              distanceLabel(distanceKm!),
              '${distanceLabel(distanceKm!)} away',
            ),
          if (minPrice != null)
            piece(
              Icons.sell_outlined,
              'from ${formatInr(minPrice!)} / night',
              'from ${formatInr(minPrice!)} per night',
            ),
        ],
      ),
    );
  }
}
```

In `lib/features/browse/browse_screen.dart`:

1. Replace:

```dart
import 'location_badge.dart';
import 'providers.dart';
```

with:

```dart
import 'location_badge.dart';
import 'providers.dart';
import 'resort_meta_line.dart';
```

2. Replace:

```dart
class PropertyCard extends StatefulWidget {
  const PropertyCard({super.key, required this.property, this.onTap});

  final Property property;
  final VoidCallback? onTap;
```

with:

```dart
class PropertyCard extends StatefulWidget {
  const PropertyCard({
    super.key,
    required this.property,
    this.onTap,
    this.distanceKm,
    this.minPrice,
    this.avgRating,
    this.reviewCount = 0,
  });

  final Property property;
  final VoidCallback? onTap;

  /// What `search_resorts` adds on the browse screen, shown by
  /// [ResortMetaLine]. These are null on admin screens that reuse this
  /// card, and then the line renders nothing.
  final double? distanceKm;
  final num? minPrice;
  final double? avgRating;
  final int reviewCount;
```

3. Replace:

```dart
                      const SizedBox(height: Spacing.sm),
                      AmenityWrap(amenities: property.amenities),
```

with:

```dart
                      ResortMetaLine(
                        avgRating: widget.avgRating,
                        reviewCount: widget.reviewCount,
                        distanceKm: widget.distanceKm,
                        minPrice: widget.minPrice,
                      ),
                      const SizedBox(height: Spacing.sm),
                      AmenityWrap(amenities: property.amenities),
```

- [ ] **Step 4: Run the tests and the analyzer to verify they pass**

Run: `flutter test test/features/browse/ test/features/admin/ && flutter analyze`
Expected: PASS. The analyzer shows only the baseline issues. The admin tests reuse `PropertyCard` and must be unchanged.

- [ ] **Step 5: Commit**

```bash
git add lib/features/browse/resort_meta_line.dart lib/features/browse/browse_screen.dart \
  test/features/browse/resort_meta_line_test.dart test/features/browse/property_card_test.dart
git commit -m "feat(search): browse cards show rating, distance and the lowest nightly price" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: Browse screen search, sort and filters

**Track:** App. **Depends on:** Task 5, which also edits `browse_screen.dart`.

**Files:**
- Create: `lib/features/browse/browse_filter_bar.dart`
- Modify: `lib/features/browse/browse_screen.dart` (imports and `BrowseScreen`; `_BrowseHero` and everything after it are unchanged)
- Test: `test/features/browse/browse_screen_test.dart` (rewritten), `test/features/browse/browse_screen_dark_mode_test.dart`

**Interfaces:**
- Consumes:
  - from Task 1: `resortSearchProvider`, `resortSearchSourceProvider`, `ResortSearchQuery`, `ResortSort`, `currentPositionProvider`, `positionServiceProvider`, `GeoPoint.coarse()`, `FakeResortSearchSource`, `respondLikeServer`, `searchResult` and `FakePositionService`
  - from Task 5: `PropertyCard`'s meta parameters
- Produces:
  - `BrowseScreen.searchDebounce` (`Duration(milliseconds: 300)`).
  - `BrowseFilterBar` (keys `browse-search`, `browse-sort`, `browse-clear-filters`).
  - Results-area keys `browse-searching` (the progress bar) and `browse-empty-clear`.

- [ ] **Step 1: Write the failing tests**

Replace the whole of `test/features/browse/browse_screen_test.dart` with:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 exports `Override` from misc.dart only (as in
// checkout_screen_test.dart).
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/core/location/geo_point.dart';
import 'package:pasala/core/location/location_service.dart';
import 'package:pasala/core/location/place_label.dart';
import 'package:pasala/core/location/position_service.dart';
import 'package:pasala/core/theme/theme_toggle_button.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_search.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/resort_search_repository.dart';
import 'package:pasala/features/browse/browse_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_position_service.dart';
import '../../support/fake_resort_search_source.dart';

/// A [LocationService] that resolves instantly with no place. The badge
/// has its own tests (`location_badge_test.dart`); here it only has to
/// settle.
class _FakeLocationService implements LocationService {
  @override
  Future<PlaceLabel?> currentPlace() async => null;
}

final _twoResorts = [
  searchResult(id: 'a1', name: 'Pasala Riverside'),
  searchResult(id: 'a2', name: 'Pasala Hilltop'),
];

final _catalog = [
  searchResult(
    id: 'r1',
    name: 'Lakeview Retreat',
    address: 'Gandipet Road, Hyderabad',
    amenities: ['Pool', 'Wi-Fi'],
    distanceKm: 12.3,
    minPrice: 4000,
    avgRating: 4.5,
    reviewCount: 2,
  ),
  searchResult(
    id: 'r2',
    name: 'Hilltop Farm',
    address: 'Nandi Hills, Bengaluru',
    amenities: ['Wi-Fi', 'Bonfire'],
  ),
];

FakeResortSearchSource _sourceFor(List<ResortSearchResult> all) =>
    FakeResortSearchSource()..respond = respondLikeServer(all);

List<Override> _overrides(
  FakeResortSearchSource source, {
  AppUser? user,
  PositionService? position,
}) =>
    [
      resortSearchSourceProvider.overrideWithValue(source),
      locationServiceProvider.overrideWithValue(_FakeLocationService()),
      positionServiceProvider
          .overrideWithValue(position ?? FakePositionService()),
      currentUserProvider.overrideWith((ref) => Stream.value(user)),
    ];

Widget _appFor(
  FakeResortSearchSource source, {
  AppUser? user,
  PositionService? position,
}) =>
    ProviderScope(
      // Riverpod 3 retries failed providers by default; without this an
      // error state never settles.
      retry: (_, _) => null,
      overrides: _overrides(source, user: user, position: position),
      child: const MaterialApp(home: Scaffold(body: BrowseScreen())),
    );

/// A tall, phone-width (list layout) view, so that every card in these
/// tests is built and on screen. The filter bar pushes the second card
/// below an 800x600 view.
void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('browse-search')), text);
  await tester.pump(BrowseScreen.searchDebounce);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows a hero header above the property list', (tester) async {
    _useTallView(tester);
    await tester.pumpWidget(_appFor(_sourceFor(_twoResorts)));
    await tester.pumpAndSettle();

    expect(find.text('Discover your stay'), findsOneWidget);
    expect(find.text('Pasala Riverside'), findsOneWidget);
    expect(find.text('Pasala Hilltop'), findsOneWidget);
  });

  testWidgets('lays properties out in a grid on a wide viewport', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appFor(_sourceFor(_twoResorts)));
    await tester.pumpAndSettle();

    expect(find.byType(SliverGrid), findsOneWidget);
  });

  testWidgets('lays properties out in a single column on a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appFor(_sourceFor(_twoResorts)));
    await tester.pumpAndSettle();

    expect(find.byType(SliverList), findsOneWidget);
  });

  for (final width in [1400.0, 840.0]) {
    testWidgets(
      'does not overflow a grid tile with a long address, many amenities and '
      'a meta line at ${width.toInt()} px',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final longOne = searchResult(
          id: 'a3',
          name: 'Pasala Overlook',
          address: '1234 Extremely Long Winding Countryside Road, Near the Old '
              'Bridge, Beyond the Third Hill, Sector 7, Farmhouse District',
          amenities: [
            'Swimming pool',
            'Bonfire pit',
            'Free parking',
            'Air conditioning',
            'Board games',
            'Pet friendly',
          ],
          distanceKm: 123.4,
          minPrice: 125000,
          avgRating: 4.8,
          reviewCount: 120,
        );

        await tester.pumpWidget(_appFor(_sourceFor([..._twoResorts, longOne])));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'stays on the list -- and shows the card -- with exactly one active '
    'resort (ResortHub lists every resort; no single-property redirect)',
    (tester) async {
      _useTallView(tester);
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: BrowseScreen()),
          ),
          GoRoute(
            path: '/property/:id',
            builder: (_, state) =>
                Text('Property page: ${state.pathParameters['id']}'),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(_sourceFor(
              [searchResult(id: 'solo-1', name: 'Pasala Farm House')])),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pasala Farm House'), findsOneWidget);
      expect(find.textContaining('Property page:'), findsNothing);
    },
  );

  testWidgets('tapping a card opens that resort', (tester) async {
    _useTallView(tester);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: BrowseScreen()),
        ),
        GoRoute(
          path: '/property/:id',
          builder: (_, state) =>
              Text('Property page: ${state.pathParameters['id']}'),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(_sourceFor(_catalog)),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Hilltop Farm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hilltop Farm'));
    await tester.pumpAndSettle();

    expect(find.text('Property page: r2'), findsOneWidget);
  });

  testWidgets('cards show the rating, distance and price search returned',
      (tester) async {
    _useTallView(tester);
    await tester.pumpWidget(_appFor(_sourceFor(_catalog)));
    await tester.pumpAndSettle();

    expect(find.text('4.5 (2)'), findsOneWidget);
    expect(find.text('12 km'), findsOneWidget);
    expect(find.text('from ₹4,000 / night'), findsOneWidget);
  });

  group('amenity chips', () {
    testWidgets('an amenity chip filters on the server, and All resets it',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = _sourceFor(_catalog);

      await tester.pumpWidget(_appFor(source));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Pool'));
      await tester.pumpAndSettle();

      expect(source.calls.last.amenities, ['Pool']);
      expect(find.text('Lakeview Retreat'), findsOneWidget);
      expect(find.text('Hilltop Farm'), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'All'));
      await tester.pumpAndSettle();

      expect(find.text('Lakeview Retreat'), findsOneWidget);
      expect(find.text('Hilltop Farm'), findsOneWidget);
    });

    testWidgets('choosing a chip keeps every other chip on offer',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_appFor(_sourceFor(_catalog)));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Bonfire'));
      await tester.pumpAndSettle();

      expect(find.text('Lakeview Retreat'), findsNothing);
      expect(find.widgetWithText(FilterChip, 'Pool'), findsOneWidget);
    });
  });

  group('search box', () {
    testWidgets('searches once typing pauses for the debounce', (tester) async {
      _useTallView(tester);
      final source = _sourceFor(_catalog);
      await tester.pumpWidget(_appFor(source));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('browse-search')), 'lake');
      await tester.pump(
          BrowseScreen.searchDebounce - const Duration(milliseconds: 1));
      expect(source.calls.where((q) => q.text == 'lake'), isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      expect(source.calls.last.text, 'lake');
      expect(find.text('Lakeview Retreat'), findsOneWidget);
      expect(find.text('Hilltop Farm'), findsNothing);
    });

    testWidgets('pressing search on the keyboard searches at once',
        (tester) async {
      _useTallView(tester);
      final source = _sourceFor(_catalog);
      await tester.pumpWidget(_appFor(source));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('browse-search')), 'nandi');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(source.calls.last.text, 'nandi');
      expect(find.text('Hilltop Farm'), findsOneWidget);
      expect(find.text('Lakeview Retreat'), findsNothing);
    });

    testWidgets(
        'keeps the previous results under a progress bar while the next '
        'search loads, and the search box keeps its focus', (tester) async {
      _useTallView(tester);
      final source = _sourceFor(_catalog);
      await tester.pumpWidget(_appFor(source));
      await tester.pumpAndSettle();

      final gate = Completer<void>();
      source.hold = gate.future;
      await tester.enterText(find.byKey(const Key('browse-search')), 'lake');
      await tester.pump(BrowseScreen.searchDebounce);
      await tester.pump();

      expect(find.byKey(const Key('browse-searching')), findsOneWidget);
      expect(find.text('Hilltop Farm'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
        isTrue,
      );

      source.hold = null;
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('browse-searching')), findsNothing);
      expect(find.text('Hilltop Farm'), findsNothing);
      expect(find.text('Lakeview Retreat'), findsOneWidget);
    });

    testWidgets(
        'no match shows the empty state, and Clear filters brings every '
        'resort back', (tester) async {
      _useTallView(tester);
      final source = _sourceFor(_catalog);
      await tester.pumpWidget(_appFor(source));
      await tester.pumpAndSettle();

      await _search(tester, 'zzz');

      expect(find.text('No resorts match your search'), findsOneWidget);
      expect(find.text('Try a different word or clear the filters.'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('browse-empty-clear')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('browse-search')))
            .controller!
            .text,
        '',
      );
      // The unfiltered search is still alive (the chips watch it), so
      // clearing shows it again without a new call.
      expect(find.text('Lakeview Retreat'), findsOneWidget);
      expect(find.text('Hilltop Farm'), findsOneWidget);
    });

    testWidgets('the bar offers Clear filters only while something narrows '
        'the list', (tester) async {
      _useTallView(tester);
      await tester.pumpWidget(_appFor(_sourceFor(_catalog)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('browse-clear-filters')), findsNothing);

      await _search(tester, 'lake');
      expect(find.byKey(const Key('browse-clear-filters')), findsOneWidget);

      await tester.tap(find.byKey(const Key('browse-clear-filters')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('browse-clear-filters')), findsNothing);
      expect(find.text('Hilltop Farm'), findsOneWidget);
    });
  });

  group('sort', () {
    testWidgets('without a position there is no Distance option',
        (tester) async {
      _useTallView(tester);
      final source = _sourceFor(_catalog);
      await tester.pumpWidget(_appFor(source));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('browse-sort')));
      await tester.pumpAndSettle();

      expect(find.text('Distance'), findsNothing);
      expect(find.text('Rating'), findsWidgets);

      await tester.tap(find.text('Price: low to high').last);
      await tester.pumpAndSettle();

      expect(source.calls.last.sort, ResortSort.priceLow);
    });

    testWidgets(
        'with a position, Distance is offered and every search sends the '
        'rounded position', (tester) async {
      _useTallView(tester);
      final source = _sourceFor(_catalog);
      await tester.pumpWidget(_appFor(
        source,
        position: FakePositionService(
            approximate: const GeoPoint(17.38512, 78.48671)),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('browse-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Distance').last);
      await tester.pumpAndSettle();

      expect(source.calls.last.sort, ResortSort.distance);
      final withOrigin = source.calls.where((q) => q.origin != null).toList();
      expect(withOrigin, isNotEmpty);
      expect(withOrigin.every((q) => q.origin == const GeoPoint(17.39, 78.49)),
          isTrue);
    });
  });

  testWidgets('a failed search shows the failure and Retry searches again',
      (tester) async {
    _useTallView(tester);
    final source = _sourceFor(_catalog)..error = const NetworkFailure();
    await tester.pumpWidget(_appFor(source));
    await tester.pumpAndSettle();

    expect(find.text('Cannot reach the server. Check your connection.'),
        findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    source.error = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Lakeview Retreat'), findsOneWidget);
  });

  testWidgets('with no resorts at all it says so', (tester) async {
    await tester.pumpWidget(_appFor(FakeResortSearchSource()));
    await tester.pumpAndSettle();

    expect(find.text('No properties yet'), findsOneWidget);
  });

  group('hero greeting', () {
    testWidgets('greets a signed-in user by their first name', (tester) async {
      await tester.pumpWidget(
        _appFor(
          _sourceFor(_twoResorts),
          user: const AppUser(
            id: 'u1',
            email: 'ravi@pasala.test',
            fullName: 'Ravi Kumar',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').endsWith(', Ravi'),
        ),
        findsOneWidget,
      );
      expect(find.text('Discover your stay'), findsOneWidget);
    });

    testWidgets('shows "Welcome" for a signed-out guest', (tester) async {
      await tester.pumpWidget(_appFor(_sourceFor(_twoResorts)));
      await tester.pumpAndSettle();

      expect(find.text('Welcome'), findsOneWidget);
    });
  });

  group('hero profile button', () {
    testWidgets("opens the signed-in user's account sheet", (tester) async {
      await tester.pumpWidget(
        _appFor(
          _sourceFor(_twoResorts),
          user: const AppUser(
            id: 'u1',
            email: 'ravi@pasala.test',
            fullName: 'Ravi Kumar',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('browse-hero-profile')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account-sheet-sign-out')), findsOneWidget);
    });

    testWidgets('sends a signed-out guest to /login', (tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: BrowseScreen()),
          ),
          GoRoute(path: '/login', builder: (_, _) => const Text('Login screen')),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(_sourceFor(_twoResorts)),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('browse-hero-profile')));
      await tester.pumpAndSettle();

      expect(find.text('Login screen'), findsOneWidget);
    });
  });

  group('hero location badge', () {
    testWidgets('renders the location badge in the hero', (tester) async {
      await tester.pumpWidget(_appFor(_sourceFor(_twoResorts)));
      await tester.pumpAndSettle();

      expect(find.text('Set location'), findsOneWidget);
    });
  });

  group('hero theme toggle', () {
    testWidgets(
      'shows the theme toggle in the action row, before the profile button',
      (tester) async {
        await tester.pumpWidget(_appFor(_sourceFor(_twoResorts)));
        await tester.pumpAndSettle();

        expect(find.byType(ThemeToggleButton), findsOneWidget);

        final actionRow = tester.widget<Row>(
          find.ancestor(
            of: find.byType(ThemeToggleButton),
            matching: find.byType(Row),
          ),
        );
        final toggleIndex = actionRow.children.indexWhere(
          (w) => w is IconTheme && w.child is ThemeToggleButton,
        );
        final profileIndex = actionRow.children.indexWhere(
          (w) => w.key == const Key('browse-hero-profile'),
        );
        expect(toggleIndex, greaterThanOrEqualTo(0));
        expect(profileIndex, greaterThanOrEqualTo(0));
        expect(toggleIndex, lessThan(profileIndex));
      },
    );
  });
}
```

In `test/features/browse/browse_screen_dark_mode_test.dart`, make these edits:

1. Replace the imports:

```dart
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/browse/browse_screen.dart';
import 'package:pasala/features/browse/providers.dart';
```

with:

```dart
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/resort_search_repository.dart';
import 'package:pasala/features/browse/browse_screen.dart';

import '../../support/fake_resort_search_source.dart';
```

2. Delete the whole `const _properties = [ ... ];` block.

3. Replace:

```dart
            propertiesProvider.overrideWith((ref) => Future.value(_properties)),
```

with:

```dart
            resortSearchSourceProvider.overrideWithValue(
              FakeResortSearchSource()
                ..results = [
                  searchResult(
                    id: 'a1',
                    name: 'Pasala Riverside',
                    amenities: ['Pool'],
                    distanceKm: 4,
                    minPrice: 3500,
                    avgRating: 4.2,
                    reviewCount: 5,
                  ),
                ],
            ),
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/browse/browse_screen_test.dart test/features/browse/browse_screen_dark_mode_test.dart`
Expected: FAIL. `BrowseScreen.searchDebounce` is undefined, and `browse-search` is not found.

- [ ] **Step 3: Write the filter bar**

Create `lib/features/browse/browse_filter_bar.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/resort_search.dart';

/// The browse screen's search box, sort menu, "Clear filters" and amenity
/// chips. Stateless: `BrowseScreen` owns every value and hears about every
/// change through a callback, so there is one place that decides what to
/// search.
class BrowseFilterBar extends StatelessWidget {
  const BrowseFilterBar({
    super.key,
    required this.controller,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.sort,
    required this.sortOptions,
    required this.onSortChanged,
    required this.amenities,
    required this.selectedAmenity,
    required this.onAmenitySelected,
    required this.showClear,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;

  /// Always one of [sortOptions].
  final ResortSort sort;
  final List<ResortSort> sortOptions;
  final ValueChanged<ResortSort> onSortChanged;
  final List<String> amenities;
  final String? selectedAmenity;
  final ValueChanged<String?> onAmenitySelected;
  final bool showClear;
  final VoidCallback onClear;

  /// `search_resorts` refuses anything longer (P0041).
  static const maxQueryLength = 100;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.md, Spacing.md, Spacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('browse-search'),
            controller: controller,
            onChanged: onSearchChanged,
            onSubmitted: onSearchSubmitted,
            textInputAction: TextInputAction.search,
            maxLength: maxQueryLength,
            decoration: InputDecoration(
              labelText: 'Search resorts',
              hintText: 'Name, city or amenity',
              prefixIcon: const Icon(Icons.search),
              counterText: '',
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          controller.clear();
                          onSearchSubmitted('');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Row(
            children: [
              Icon(Icons.sort, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: Spacing.xs),
              DropdownButton<ResortSort>(
                key: const Key('browse-sort'),
                value: sort,
                underline: const SizedBox.shrink(),
                items: [
                  for (final option in sortOptions)
                    DropdownMenuItem(value: option, child: Text(option.label)),
                ],
                onChanged: (value) {
                  if (value != null) onSortChanged(value);
                },
              ),
              const Spacer(),
              if (showClear)
                TextButton(
                  key: const Key('browse-clear-filters'),
                  onPressed: onClear,
                  child: const Text('Clear filters'),
                ),
            ],
          ),
          if (amenities.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: selectedAmenity == null,
                    onSelected: (_) => onAmenitySelected(null),
                  ),
                  const SizedBox(width: Spacing.xs),
                  for (final amenity in amenities) ...[
                    FilterChip(
                      label: Text(amenity),
                      selected: selectedAmenity == amenity,
                      onSelected: (selected) =>
                          onAmenitySelected(selected ? amenity : null),
                    ),
                    const SizedBox(width: Spacing.xs),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Rewrite `BrowseScreen` on search**

In `lib/features/browse/browse_screen.dart`, replace everything from the first line of the file through the closing `}` of `class _BrowseScreenState`, which is the line just before `class _BrowseHero extends ConsumerWidget {`. The replacement is:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/greeting.dart';
import '../../core/location/geo_point.dart';
import '../../core/location/position_service.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/theme_toggle_button.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../core/widgets/hero_backdrop.dart';
import '../../core/widgets/staggered_fade_in.dart';
import '../../data/models/app_user.dart';
import '../../data/models/property.dart';
import '../../data/models/resort_search.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/resort_search_repository.dart';
import '../shell/app_shell.dart' show showAccountSheet;
import 'browse_filter_bar.dart';
import 'location_badge.dart';
import 'resort_meta_line.dart';

/// `/`: every bookable resort, searched and sorted by `search_resorts`
/// (0060_guest_search.sql). ResortHub lists every active resort; the
/// 2026-08-13 single-property redirect is superseded by the 2026-09-24
/// tenancy spec.
///
/// The hero and the filter bar always stay on screen. Only the results
/// area below them loads, fails or empties, so a guest typing into the
/// search box never loses the field or its focus.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  /// How long typing must pause before a search runs.
  static const searchDebounce = Duration(milliseconds: 300);

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _text = '';
  ResortSort _sort = ResortSort.recommended;
  String? _selectedAmenity;

  /// The last results that finished loading, shown under a progress bar
  /// while the next search runs (spec decision 20).
  List<ResortSearchResult>? _lastResults;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(BrowseScreen.searchDebounce, () {
      if (mounted) setState(() => _text = value.trim());
    });
  }

  void _onSearchSubmitted(String value) {
    _debounce?.cancel();
    setState(() => _text = value.trim());
  }

  void _clearFilters() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _text = '';
      _selectedAmenity = null;
      _sort = ResortSort.recommended;
    });
  }

  /// Distance needs a position. Without one the sort quietly falls back to
  /// Recommended, and the menu does not offer Distance at all.
  ResortSearchQuery _queryFor(GeoPoint? origin) => ResortSearchQuery(
        text: _text,
        sort: _sort == ResortSort.distance && origin == null
            ? ResortSort.recommended
            : _sort,
        amenities: [?_selectedAmenity],
        origin: origin?.coarse(),
      );

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= PasalaTokens.wideBreakpoint;
    final origin = ref.watch(currentPositionProvider).value;
    final query = _queryFor(origin);
    final results = ref.watch(resortSearchProvider(query));
    // The chips come from the unfiltered list, so picking one never hides
    // the others.
    final everything = ref.watch(resortSearchProvider(ResortSearchQuery.all));

    final fresh = results.value;
    if (fresh != null) _lastResults = fresh;
    final shown = fresh ?? _lastResults;

    final amenities = <String>{
      for (final r in everything.value ?? const <ResortSearchResult>[])
        ...r.property.amenities,
      ?_selectedAmenity,
    }.toList()
      ..sort();
    final sortOptions = [
      for (final option in ResortSort.values)
        if (option != ResortSort.distance || origin != null) option,
    ];

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(resortSearchProvider),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _BrowseHero(wide: wide)),
          SliverToBoxAdapter(
            child: BrowseFilterBar(
              controller: _searchController,
              onSearchChanged: _onSearchChanged,
              onSearchSubmitted: _onSearchSubmitted,
              sort: query.sort,
              sortOptions: sortOptions,
              onSortChanged: (sort) => setState(() => _sort = sort),
              amenities: amenities,
              selectedAmenity: _selectedAmenity,
              onAmenitySelected: (amenity) =>
                  setState(() => _selectedAmenity = amenity),
              showClear: query.hasFilters,
              onClear: _clearFilters,
            ),
          ),
          if (results.isLoading && shown != null)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(
                key: Key('browse-searching'),
                minHeight: 2,
              ),
            ),
          ..._resultSlivers(context, results, shown, query, wide),
        ],
      ),
    );
  }

  List<Widget> _resultSlivers(
    BuildContext context,
    AsyncValue<List<ResortSearchResult>> results,
    List<ResortSearchResult>? shown,
    ResortSearchQuery query,
    bool wide,
  ) {
    if (results.hasError && !results.isLoading) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: FailureView(
            error: results.error!,
            onRetry: () => ref.invalidate(resortSearchProvider(query)),
          ),
        ),
      ];
    }
    if (shown == null) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (shown.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: query.hasFilters
              ? _CenteredMessage(
                  icon: Icons.search_off,
                  title: 'No resorts match your search',
                  message: 'Try a different word or clear the filters.',
                  action: TextButton(
                    key: const Key('browse-empty-clear'),
                    onPressed: _clearFilters,
                    child: const Text('Clear filters'),
                  ),
                )
              : const _CenteredMessage(
                  icon: Icons.villa_outlined,
                  title: 'No properties yet',
                  message: 'Ask an admin to add one.',
                ),
        ),
      ];
    }

    Widget card(int i) {
      final result = shown[i];
      return StaggeredFadeIn(
        key: ValueKey(result.property.id),
        index: i,
        child: PropertyCard(
          property: result.property,
          distanceKm: result.distanceKm,
          minPrice: result.minPrice,
          avgRating: result.avgRating,
          reviewCount: result.reviewCount,
          onTap: () => context.go('/property/${result.property.id}'),
        ),
      );
    }

    if (wide) {
      return [
        SliverPadding(
          padding: const EdgeInsets.all(Spacing.md),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: Spacing.md,
              crossAxisSpacing: Spacing.md,
              // 0.76, not 0.82: room for the meta line at the 840 px
              // breakpoint.
              childAspectRatio: 0.76,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => card(i),
              childCount: shown.length,
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.all(Spacing.md),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: card(i),
            ),
            childCount: shown.length,
          ),
        ),
      ),
    ];
  }
}

/// The results area's empty states. This is a plain `Column`, not
/// `EmptyState`: `SliverFillRemaining(hasScrollBody: false)` measures its
/// child's intrinsic height, and `EmptyState`'s `LayoutBuilder` cannot
/// report one.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.outline),
            const SizedBox(height: Spacing.md),
            Text(title,
                style: textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: Spacing.sm),
            Text(
              message,
              style:
                  textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: Spacing.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run the tests and the analyzer to verify they pass**

Run: `flutter test test/features/browse/ && flutter analyze`
Expected: PASS. The analyzer shows only the baseline issues. `providers.dart` is still used by the owner screens and `property_screen.dart`, so only `browse_screen.dart` stops importing it.

- [ ] **Step 6: Run the whole Flutter suite**

Run: `flutter test 2>&1 | tail -3`
Expected: all pass. The count is the Task 1 baseline plus the tests added so far.

- [ ] **Step 7: Commit**

```bash
git add lib/features/browse/browse_filter_bar.dart lib/features/browse/browse_screen.dart \
  test/features/browse/browse_screen_test.dart test/features/browse/browse_screen_dark_mode_test.dart
git commit -m "feat(search): browse search box, sort menu, server-side amenity filter and empty state" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: The owner's Map location

**Track:** App. **Depends on:** Task 1.

**Files:**
- Create: `lib/features/owner/location_settings_screen.dart`
- Modify: `lib/features/owner/owner_settings_screen.dart`
- Test: `test/features/owner/location_settings_screen_test.dart`, `test/features/owner/owner_settings_screen_test.dart`

**Interfaces:**
- Consumes:
  - from Task 1: `positionServiceProvider` / `PositionService.precisePosition()`, `GeoPoint`, `Property.latitude`/`longitude`/`location` and `FakePositionService`
  - existing: `CatalogRepository.updateSettings(String, Map<String, dynamic>)`, `catalogRepositoryProvider`, `propertiesProvider` and `propertyProvider`
- Produces:
  - `({GeoPoint? point, String? error}) parseCoordinates(String latText, String lngText)`.
  - `LocationSettingsScreen({required Property property})`, with keys `location-lat`, `location-lng`, `location-use-current` and `location-save`.
  - The Owner Settings "Map location" tile.

- [ ] **Step 1: Write the failing tests**

Create `test/features/owner/location_settings_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/core/location/geo_point.dart';
import 'package:pasala/core/location/position_service.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/repositories/catalog_repository.dart';
import 'package:pasala/features/owner/location_settings_screen.dart';

import '../../support/fake_position_service.dart';

/// Records `updateSettings`; every other member is unused here.
class _RecordingCatalog implements CatalogRepository {
  final List<(String, Map<String, dynamic>)> updates = [];
  Object? error;

  @override
  Future<void> updateSettings(
      String propertyId, Map<String, dynamic> fields) async {
    updates.add((propertyId, fields));
    if (error != null) throw error!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Property _property({double? lat, double? lng}) => Property(
      id: 'p1',
      name: 'Pasala Farm House',
      slug: 'pasala-farm-house',
      description: null,
      address: null,
      images: const [],
      amenities: const [],
      checkInTime: '14:00',
      checkOutTime: '11:00',
      isActive: true,
      latitude: lat,
      longitude: lng,
    );

/// Pushes the screen from a launcher page, so that Save's `pop` has
/// somewhere to go back to.
Future<void> _open(
  WidgetTester tester, {
  required Property property,
  required _RecordingCatalog catalog,
  FakePositionService? position,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      catalogRepositoryProvider.overrideWithValue(catalog),
      positionServiceProvider
          .overrideWithValue(position ?? FakePositionService()),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LocationSettingsScreen(property: property),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  group('parseCoordinates', () {
    test('both empty clears the location', () {
      final r = parseCoordinates('  ', '');
      expect(r.point, isNull);
      expect(r.error, isNull);
    });

    test('a trimmed valid pair parses', () {
      final r = parseCoordinates(' 17.385044 ', '78.486671');
      expect(r.point, const GeoPoint(17.385044, 78.486671));
      expect(r.error, isNull);
    });

    test('only one of the two is refused', () {
      expect(parseCoordinates('17.3', '').error,
          'Enter both latitude and longitude, or leave both empty.');
      expect(parseCoordinates('', '78.4').error,
          'Enter both latitude and longitude, or leave both empty.');
    });

    test('a comma decimal or text is refused', () {
      expect(parseCoordinates('17,385', '78.48').error,
          'Latitude and longitude must be numbers, like 17.385 and 78.4867.');
      expect(parseCoordinates('north', '78.48').error,
          'Latitude and longitude must be numbers, like 17.385 and 78.4867.');
    });

    test('out of range, NaN or swapped coordinates are refused', () {
      const message = 'Latitude must be between -90 and 90, '
          'and longitude between -180 and 180.';
      expect(parseCoordinates('91', '78').error, message);
      expect(parseCoordinates('17', '181').error, message);
      expect(parseCoordinates('NaN', '78').error, message);
      expect(parseCoordinates('178.48', '17.38').error, message);
    });
  });

  testWidgets('prefills the saved coordinates', (tester) async {
    await _open(tester,
        property: _property(lat: 17.385044, lng: 78.486671),
        catalog: _RecordingCatalog());

    expect(_fieldText(tester, 'location-lat'), '17.385044');
    expect(_fieldText(tester, 'location-lng'), '78.486671');
  });

  testWidgets('"Use my current location" fills both fields from a precise fix',
      (tester) async {
    final position =
        FakePositionService(precise: const GeoPoint(17.3850441, 78.4866712));
    await _open(tester,
        property: _property(), catalog: _RecordingCatalog(), position: position);

    await tester.tap(find.byKey(const Key('location-use-current')));
    await tester.pumpAndSettle();

    expect(position.preciseCalls, 1);
    expect(position.approximateCalls, 0);
    expect(_fieldText(tester, 'location-lat'), '17.385044');
    expect(_fieldText(tester, 'location-lng'), '78.486671');
  });

  testWidgets('an unavailable location says what to do and changes nothing',
      (tester) async {
    await _open(tester,
        property: _property(lat: 1, lng: 2), catalog: _RecordingCatalog());

    await tester.tap(find.byKey(const Key('location-use-current')));
    await tester.pumpAndSettle();

    expect(
        find.text('Could not get your location. '
            'Allow location access, or type the coordinates.'),
        findsOneWidget);
    expect(_fieldText(tester, 'location-lat'), '1.000000');
  });

  testWidgets('Save sends both coordinates and closes', (tester) async {
    final catalog = _RecordingCatalog();
    await _open(tester, property: _property(), catalog: catalog);

    await tester.enterText(find.byKey(const Key('location-lat')), '17.385044');
    await tester.enterText(find.byKey(const Key('location-lng')), '78.486671');
    await tester.tap(find.byKey(const Key('location-save')));
    await tester.pumpAndSettle();

    // Records compare their fields with ==, and a Map's == is identity,
    // so check the two parts separately.
    expect(catalog.updates.single.$1, 'p1');
    expect(catalog.updates.single.$2, {'lat': 17.385044, 'lng': 78.486671});
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('clearing both fields removes the location', (tester) async {
    final catalog = _RecordingCatalog();
    await _open(tester,
        property: _property(lat: 17.3, lng: 78.4), catalog: catalog);

    await tester.enterText(find.byKey(const Key('location-lat')), '');
    await tester.enterText(find.byKey(const Key('location-lng')), '');
    await tester.tap(find.byKey(const Key('location-save')));
    await tester.pumpAndSettle();

    expect(catalog.updates.single.$1, 'p1');
    expect(catalog.updates.single.$2, {'lat': null, 'lng': null});
  });

  testWidgets('an invalid form shows the reason and sends nothing',
      (tester) async {
    final catalog = _RecordingCatalog();
    await _open(tester, property: _property(), catalog: catalog);

    await tester.enterText(find.byKey(const Key('location-lat')), '17.385');
    await tester.tap(find.byKey(const Key('location-save')));
    await tester.pumpAndSettle();

    expect(find.text('Enter both latitude and longitude, or leave both empty.'),
        findsOneWidget);
    expect(catalog.updates, isEmpty);
    expect(find.byType(LocationSettingsScreen), findsOneWidget);
  });

  testWidgets('a refused save shows the failure and stays open',
      (tester) async {
    final catalog = _RecordingCatalog()..error = const ResortSuspended();
    await _open(tester, property: _property(), catalog: catalog);

    await tester.enterText(find.byKey(const Key('location-lat')), '17.3');
    await tester.enterText(find.byKey(const Key('location-lng')), '78.4');
    await tester.tap(find.byKey(const Key('location-save')));
    await tester.pumpAndSettle();

    expect(find.text(const ResortSuspended().message), findsOneWidget);
    expect(find.byType(LocationSettingsScreen), findsOneWidget);
  });
}
```

In `test/features/owner/owner_settings_screen_test.dart`:

1. Replace:

```dart
Future<void> _pump(WidgetTester tester, FakeResortPlanSource source) async {
```

with:

```dart
Future<void> _pump(WidgetTester tester, FakeResortPlanSource source,
    {Property property = _property}) async {
```

2. Replace:

```dart
      propertyProvider.overrideWith((ref, id) async => _property),
```

with:

```dart
      propertyProvider.overrideWith((ref, id) async => property),
```

3. Add these tests inside `main()`, after the last existing test:

```dart
  testWidgets('Map location says when the resort has no coordinates',
      (tester) async {
    await _pump(tester, FakeResortPlanSource());

    expect(find.text('Map location'), findsOneWidget);
    expect(find.text('Not set. Guests will not see how far away you are.'),
        findsOneWidget);
  });

  testWidgets('Map location shows the saved coordinates and opens the editor',
      (tester) async {
    const located = Property(
      id: 'p1',
      name: 'Pasala Farm House',
      slug: 'pasala-farm-house',
      description: null,
      address: null,
      images: [],
      amenities: [],
      checkInTime: '14:00',
      checkOutTime: '11:00',
      isActive: true,
      latitude: 17.385044,
      longitude: 78.486671,
    );
    await _pump(tester, FakeResortPlanSource(), property: located);

    expect(find.text('17.3850, 78.4867'), findsOneWidget);

    await tester.tap(find.text('Map location'));
    await tester.pumpAndSettle();

    expect(find.byType(LocationSettingsScreen), findsOneWidget);
    expect(find.text('Use my current location'), findsOneWidget);
  });
```

4. Add this import to the top of `test/features/owner/owner_settings_screen_test.dart`:

```dart
import 'package:pasala/features/owner/location_settings_screen.dart';
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/owner/location_settings_screen_test.dart test/features/owner/owner_settings_screen_test.dart`
Expected: FAIL to compile, because `location_settings_screen.dart` does not exist.

- [ ] **Step 3: Write the screen**

Create `lib/features/owner/location_settings_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/location/geo_point.dart';
import '../../core/location/position_service.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/property.dart';
import '../../data/repositories/catalog_repository.dart';
import '../browse/providers.dart';

/// Validates the Map location form. Both fields empty clears the location
/// (`point` and `error` both null). Anything else must be a valid pair;
/// otherwise `error` says what is wrong. The table's
/// `properties_coordinates_pair` and range checks (0060) are the backstop.
({GeoPoint? point, String? error}) parseCoordinates(
    String latText, String lngText) {
  final lat = latText.trim();
  final lng = lngText.trim();
  if (lat.isEmpty && lng.isEmpty) return (point: null, error: null);
  if (lat.isEmpty || lng.isEmpty) {
    return (
      point: null,
      error: 'Enter both latitude and longitude, or leave both empty.',
    );
  }
  final latitude = double.tryParse(lat);
  final longitude = double.tryParse(lng);
  if (latitude == null || longitude == null) {
    return (
      point: null,
      error: 'Latitude and longitude must be numbers, like 17.385 and 78.4867.',
    );
  }
  final point = GeoPoint(latitude, longitude);
  if (!point.isValid) {
    return (
      point: null,
      error: 'Latitude must be between -90 and 90, '
          'and longitude between -180 and 180.',
    );
  }
  return (point: point, error: null);
}

/// Map location: `properties.lat`/`lng`, pushed from Owner Settings.
/// Guests see the distance to these coordinates and can sort by it. The
/// save goes through the existing `properties_update` policy (owner or
/// admin; a suspended resort refuses with P0022), the same way the Tax and
/// Booking-rules screens save.
class LocationSettingsScreen extends ConsumerStatefulWidget {
  const LocationSettingsScreen({super.key, required this.property});

  final Property property;

  @override
  ConsumerState<LocationSettingsScreen> createState() =>
      _LocationSettingsScreenState();
}

class _LocationSettingsScreenState
    extends ConsumerState<LocationSettingsScreen> {
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  String? _error;
  bool _busy = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _lat = TextEditingController(
        text: widget.property.latitude?.toStringAsFixed(6) ?? '');
    _lng = TextEditingController(
        text: widget.property.longitude?.toStringAsFixed(6) ?? '');
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    final point = await ref.read(positionServiceProvider).precisePosition();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (point == null) {
        _error = 'Could not get your location. '
            'Allow location access, or type the coordinates.';
      } else {
        _lat.text = point.latitude.toStringAsFixed(6);
        _lng.text = point.longitude.toStringAsFixed(6);
      }
    });
  }

  Future<void> _save() async {
    final parsed = parseCoordinates(_lat.text, _lng.text);
    if (parsed.error != null) {
      setState(() => _error = parsed.error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(catalogRepositoryProvider).updateSettings(
        widget.property.id,
        {'lat': parsed.point?.latitude, 'lng': parsed.point?.longitude},
      );
      ref.invalidate(propertiesProvider);
      ref.invalidate(propertyProvider(widget.property.id));
      if (mounted) Navigator.of(context).pop();
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Map location')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(Spacing.lg),
            children: [
              Text(
                'Guests see how far away you are and can sort resorts by '
                'distance. Leave both fields empty to hide your distance.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              OutlinedButton.icon(
                key: const Key('location-use-current'),
                onPressed: _locating || _busy ? null : _useCurrentLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: const Text('Use my current location'),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                key: const Key('location-lat'),
                controller: _lat,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(
                  labelText: 'Latitude',
                  helperText: 'Between -90 and 90, e.g. 17.385044',
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                key: const Key('location-lng'),
                controller: _lng,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(
                  labelText: 'Longitude',
                  helperText: 'Between -180 and 180, e.g. 78.486671',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
              const SizedBox(height: Spacing.lg),
              FilledButton(
                key: const Key('location-save'),
                onPressed: _busy ? null : _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add the Owner Settings tile**

In `lib/features/owner/owner_settings_screen.dart`:

1. Replace:

```dart
import 'cancellation_policy_screen.dart';
```

with:

```dart
import 'cancellation_policy_screen.dart';
import 'location_settings_screen.dart';
```

2. Replace:

```dart
              _SettingsTile(
                icon: Icons.sell_outlined,
```

with:

```dart
              _SettingsTile(
                icon: Icons.place_outlined,
                title: 'Map location',
                subtitle: property.location == null
                    ? 'Not set. Guests will not see how far away you are.'
                    : '${property.latitude!.toStringAsFixed(4)}, '
                        '${property.longitude!.toStringAsFixed(4)}',
                color: scheme.primary,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => LocationSettingsScreen(property: property),
                )),
              ),
              _SettingsTile(
                icon: Icons.sell_outlined,
```

- [ ] **Step 5: Run the tests and the analyzer to verify they pass**

Run: `flutter test test/features/owner/ && flutter analyze`
Expected: PASS. The analyzer shows only the baseline issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/owner/location_settings_screen.dart lib/features/owner/owner_settings_screen.dart \
  test/features/owner/location_settings_screen_test.dart test/features/owner/owner_settings_screen_test.dart
git commit -m "feat(search): owners set their resort's map location" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Phase 3: Integration

### Task 8: Merge the tracks and verify end to end

**Track:** both. **Depends on:** Tasks 2–7.

**Files:**
- Modify: `e2e/tests/guest.spec.ts`

A fix belongs to the task that owns the file, and gets its own commit.

**Interfaces:**
- Consumes: everything above.
- Produces: a branch where the database and the app agree on names and shapes, with every suite green.

- [ ] **Step 1: Merge**

If the tracks ran in separate worktrees, merge the database branch and the app branch into the P11 branch. The tracks own disjoint files. If a conflict appears in a file both touched, keep both sides' additions.

- [ ] **Step 2: Check the contract by name**

Run: `grep -n "rpc('search_resorts'" lib/data/repositories/resort_search_repository.dart && grep -n "'p_query'\|'p_lat'\|'p_lng'\|'p_sort'\|'p_amenities'" lib/data/models/resort_search.dart && grep -n "create function public.search_resorts" -A6 supabase/migrations/0060_guest_search.sql`
Expected:
- The RPC name is `search_resorts`.
- The five parameter keys match the five parameter names in the migration.
- The `dbValue` strings `recommended|distance|price|rating` are exactly the values the function accepts.

- [ ] **Step 3: Run the full suites**

Run: `supabase db reset && supabase test db`, then `flutter test`, then `flutter analyze`
Expected:
- pgTAP: 50 at 57/57, 37 at 77/77, and every other file as in the Task 1 baseline.
- Flutter: all tests pass. The count is the baseline plus the tests this plan added.
- Analyzer: nothing beyond the 2-info baseline.

- [ ] **Step 4: Add the end-to-end search test**

In `e2e/tests/guest.spec.ts`, insert this test right after the `'amenity filter chips filter the resort list'` test:

```ts
test('the search box narrows the resort list and Clear filters restores it', async ({ page }) => {
  await login(page, bookingGuest);
  await expectAt(page, '/');

  // Every word must match: "Guest" and "Booking" only appear in
  // guestResort's name, so Resort A drops out.
  await fillField(page.getByLabel('Search resorts'), guestResort.name);
  await expect(resortCard(page, guestResort.name)).toBeVisible();
  await expect(resortCard(page, resortA.name)).toHaveCount(0);

  await fillField(page.getByLabel('Search resorts'), 'zzzz-no-such-resort');
  await expect(page.getByText('No resorts match your search')).toBeVisible();

  // Two "Clear filters" exist here (filter bar and empty state); either one
  // resets everything.
  await page.getByRole('button', { name: 'Clear filters', exact: true }).first().click();
  await expect(resortCard(page, resortA.name)).toBeVisible();
  await expect(resortCard(page, guestResort.name)).toBeVisible();
});
```

Run: `supabase start && cd e2e && ./build-app.sh && npx playwright test tests/guest.spec.ts`
Expected: every guest test passes, including the existing browse and amenity-chip tests. Those now go through `search_resorts`.

- [ ] **Step 5: Manual smoke test against the local stack**

Run `make run-web`, then:
1. **Signed out, on `/`.** Type `farm`: the list narrows after a short pause, and the field keeps focus. Clear it with the ✕.
2. **Sort.** Open the sort menu. Distance appears only after the badge shows a city. Choose Price: low to high, and check that resorts without a nightly rate go last and show no price.
3. **Owner.** Sign in as a seeded owner and open Settings → Map location. Tap "Use my current location" and allow it. Both fields fill; Save.
4. **Distance.** Sign out, and allow location on `/`. The owner's resort card shows a distance, and Distance sorts it first.
5. **Suspended resort.** Suspend a resort in the platform console. Search for it by name: it never appears, not even for its own owner signed in on `/`.

- [ ] **Step 6: Commit**

```bash
git add e2e/tests/guest.spec.ts
git commit -m "test(e2e): guest search narrows the list and Clear filters restores it" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

For each fix found in Steps 3–5, run `git add <the fixed files>`, then `git commit -m "fix(search): <what was wrong>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`.

---

## Self-Review

**1. Spec coverage**

| Spec requirement | Task |
|---|---|
| Coordinate checks on the existing `lat`/`lng`, cleanup of bad pairs | 1 |
| Pasala left null (no guessed coordinates) | 1 (nothing seeded; the migration does not touch the seed) |
| `search_resorts` signature, OUT columns, definer, `search_path`, anon/authenticated grants | 1 |
| Allow-list entry | 1 |
| Active-only (status and `is_active`), whoever calls | 2, 3 |
| Matching: name/address(city)/description/amenity, all words, literal wildcards, blank, 100-char cap | 2 |
| Amenity filter: all required, case-insensitive, blanks ignored | 2 |
| `min_price` rules (nightly only, active units, nightly/both, unexpired; null for day-use) | 2 |
| `avg_rating` / `review_count` | 2 |
| Haversine `distance_km`, null without origin or coordinates | 2 |
| P0041 cases | 2 |
| Sorts: recommended score + photo, distance (and fallback), price nulls last, rating, tie-breaks | 3 |
| Owner writes via `properties_update`; staff/guest cannot | 3 |
| `GeoPoint`, coarse rounding, `PositionService`, fallback provider | 1 |
| Shared low-accuracy fix, coarse cache, badge retry | 4 |
| Model, repository, providers, P0041 copy, `Property` lat/lng | 1 |
| Card meta line (rating, distance, price) | 5 |
| Search box, debounce, submit, sort menu (Distance only with a position), chips from the unfiltered list, Clear filters, empty and error states, keep-previous-results | 6 |
| Map location screen and Owner Settings tile | 7 |
| Playwright search test | 8 |

**2. Placeholder scan:** none of "TBD", "TODO" or "similar to Task N" appears. Every code step shows its code, and every SQL test uses literal ids and literal expected arrays.

**3. Type consistency:**
- `ResortSearchSource.search(ResortSearchQuery) → Future<List<ResortSearchResult>>` has the same shape in the repository, the fake, the provider and the screen.
- `PositionService.approximatePosition()` and `precisePosition()` are used the same way in the device service, the fake, the badge test, the browse screen and the owner screen.
- `ResortSort.dbValue` strings match the SQL `v_sort` values.
- The OUT columns pinned in test 50 match `ResortSearchResult.fromJson`'s and `Property.fromJson`'s keys (`lat`, `lng`, `distance_km`, `min_price`, `avg_rating`, `review_count`).
- `parseCoordinates` returns the record `({GeoPoint? point, String? error})` in both the screen and the tests.
- The key strings are consistent between widgets and tests: `browse-search`, `browse-sort`, `browse-clear-filters`, `browse-empty-clear`, `browse-searching`, `location-lat`, `location-lng`, `location-use-current` and `location-save`.

**4. Review Focus:** each of the five lines has its test in the owning task:
1. Task 6
2. Task 2
3. Tasks 3 and 6
4. Tasks 2, 3 and 5
5. Tasks 1 and 7

Other implied inputs are covered as well:
- privacy of the guest position: Tasks 1 (`coarse`), 4 (the cache stores only coarse) and 6 (the origin sent is coarse)
- a suspended resort's own owner: Task 3
- an empty catalogue: Task 6
- a failed search: Task 6
