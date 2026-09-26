# Guest Search and Discovery (P11) — Design

## Why

ResortHub lists every active resort on the guest browse screen
(`lib/features/browse/browse_screen.dart`, route `/`). Once more than a
handful of resorts join, a guest needs to find one:

- The only narrowing today is a single-select amenity chip row, filtered in
  the app over the whole list that `CatalogRepository.properties()` reads
  straight from `properties`.
- There is no text search, no sort, and a card shows no price, rating or
  distance. The guest has to open each resort to learn what a night costs.
- `properties.lat` / `properties.lng` (`double precision`) have existed since
  `0003_properties_units.sql`, but nothing reads or writes them and there is
  no screen to set them.
- The browse hero already resolves the guest's position for its
  location badge (`LocationBadge`, `DeviceLocationService`), but only turns
  it into a "City, Country" label. The position is thrown away.
- A signed-in resort member sees their own suspended resort on the browse
  screen too, because `properties_read` lets members read their own rows.

The gap-closing round (2026-09-25, section P11 of the accepted decisions)
asks for search, sorting, distance and a price and rating on each card.

## Decisions (auto-approved 2026-09-25)

Accepted from the product owner:

1. **Coordinates.** Resorts carry a latitude and longitude. The owner sets them
   in property settings, with "Use my current location" or by typing them.
   Pasala is seeded from its address if the coordinates are known, and left
   empty if not.
2. **Price.** Each resort shows a minimum nightly price, derived from
   `rate_rules`.
3. **Browse screen.** It gets a search box that matches the name, city,
   description and amenities. It gets a sort with four options: Recommended,
   Distance, Price low to high, and Rating. Distance uses the position behind
   the location badge, and the option is hidden when there is no position.
   The amenity filter chips stay. Each card shows its distance, such as
   "12 km".
4. **Server-side search.** A function `search_resorts(p_query, p_lat, p_lng,
   p_sort, p_amenities)` searches active resorts only and is callable by
   anon. It returns the card fields plus `distance_km`, `min_price` and
   `avg_rating`.
5. **Empty results.** The screen shows an empty state with "Clear filters".

Judgment calls made for this spec:

6. **The existing `lat` / `lng` columns are reused.** They are not renamed and
   no new columns are added. The migration clears any half-set or
   out-of-range pair and then adds three checks: both set or both null,
   latitude in −90..90, and longitude in −180..180. The Dart model exposes the
   columns as `Property.latitude` / `Property.longitude`.
7. **Pasala's coordinates stay empty.** The seeded address ("Bommalaramaram
   Rd, Rangapuram, Telangana") has no verified coordinates, so neither the
   migration nor `supabase/seed.sql` guesses them. The owner sets them once,
   on site, with "Use my current location".
8. **`min_price` is computed on each search and never stored.** A stored
   column would need triggers on `rate_rules` and `units`, and those triggers
   could go stale. The price is the lowest `rate_rules.price` over rules that
   meet all of these conditions:
   - the rule is nightly (`slot_type_id is null`)
   - it belongs to an active unit whose `booking_mode` is `nightly` or `both`
   - it has not expired (`valid_to` is null or on or after today, in the
     resort's timezone)

   The price is before tax, like the rate rules themselves. It is null for a
   resort with no nightly rate, such as a day-use-only resort.
9. **The rating is `avg(reviews.overall_rating)`** rounded to one decimal,
   plus `review_count`. The property page computes its average the same way.
   Anon cannot read `reviews` (`reviews_read` is for `authenticated` only).
   `search_resorts` is `security definer`, so it can return these aggregates
   to anon. It never returns review text or authors.
10. **"City" is matched inside `address`.** `properties` has no city column.
    The address holds the town, as in Pasala's "…, Rangapuram, Telangana".
    If a later project adds a city column, adding it to the match is a
    one-line change.
11. **Matching rules.** The query is trimmed and split on whitespace. Every
    word must appear, case-insensitively, in at least one of: name, address,
    description, or an amenity. `%`, `_` and `\` typed by a guest match
    literally. A blank query matches everything. The query can be at most 100
    characters; a longer one raises P0041.
12. **Amenity filter.** `p_amenities` must all be present on the resort,
    compared case-insensitively. Blank entries are ignored. The screen keeps
    its single-select chip row and passes zero or one amenity. The chip list
    comes from an unfiltered search, so picking a chip never hides the other
    chips.
13. **Sort orders.** Every order ends with name, then id, so it is
    deterministic.
    - `recommended`: a rating score shrunk toward 4 by three phantom reviews,
      `(sum of overall ratings + 12) / (review_count + 3)`, highest first.
      Resorts with a photo come before resorts without one.
    - `distance`: `distance_km` ascending, with no-coordinate resorts last. If
      no position is given, this sort falls back to the `recommended` order
      and raises no error.
    - `price`: `min_price` ascending, with nulls last.
    - `rating`: `avg_rating` descending with nulls last, then `review_count`
      descending.
    - A null or blank `p_sort` means `recommended`. Any other value raises
      P0041.
14. **Distance is great-circle distance** (haversine, R = 6371 km), computed in
    SQL and rounded to 0.1 km. No PostGIS, and no extension. The card shows
    `< 1 km` below one kilometre and whole kilometres above it (`12 km`).
15. **The guest's position leaves the device coarse only.** Before any call,
    the app rounds the position to 2 decimal places (about 1 km). Only that
    rounded point is cached in `shared_preferences` and sent to
    `search_resorts`. The Nominatim lookup for the badge is unchanged.
16. **One device fix serves both the badge and distance.** When the cache is
    empty, `DeviceLocationService` shares one in-flight low-accuracy fix
    between `currentPlace()` and `approximatePosition()`, so the permission is
    asked once. The owner's "Use my current location" takes a separate fresh,
    high-accuracy fix that is not cached.
17. **P0041 `invalid_search`** is raised for:
    - an unknown sort
    - only one of `p_lat` / `p_lng`
    - an out-of-range coordinate
    - a query over 100 characters

    The app maps it to readable copy. The app never sends these inputs, so
    the error is a backstop.
18. **Browse reads search results only.** `propertiesProvider` stays for the
    owner and admin screens that already use it. The browse screen now shows
    only bookable resorts (status `active` and `is_active`). This includes
    what a signed-in member sees: they no longer see their own suspended,
    archived or (after P10) pending resort there.
19. **No write function.** The owner saves coordinates through the existing
    `properties_update` policy (owner or admin, and the resort must not be
    suspended) with `CatalogRepository.updateSettings`, the same way the Tax
    and Booking-rules screens save. The only UI entry is a "Map location"
    tile in Owner Settings. The admin role keeps its RLS right but gets no
    new screen.
20. **Search results replace the list without blanking it.** While a new
    search loads, the previous results stay on screen under a thin progress
    bar. The search box keeps focus. Typing is debounced by 300 ms, and
    pressing search on the keyboard runs the search at once.

## Data model — `supabase/migrations/0060_guest_search.sql`

- `properties`: no new columns. The existing `lat` and `lng` are first
  cleaned: any pair that is half-set or out of range is set to null. Then
  these checks are added:
  - `properties_coordinates_pair check ((lat is null) = (lng is null))`
  - `properties_lat_range check (lat is null or lat between -90 and 90)`
  - `properties_lng_range check (lng is null or lng between -180 and 180)`
- No new tables, policies or grants on tables. Writes to `lat` / `lng` use the
  existing `properties_update` policy from `0044_resort_policies.sql`.

## Functions (security definer, `search_path = public, pg_temp`)

- `search_resorts(p_query text default null, p_lat double precision default
  null, p_lng double precision default null, p_sort text default
  'recommended', p_amenities text[] default null)`, `stable`.
  - Returns one row per matching resort whose `status = 'active'` and
    `is_active`, whoever calls it.
  - Row columns: `id, name, slug, description, address, images, amenities,
    check_in_time, check_out_time, is_active, lat, lng, distance_km numeric,
    min_price numeric, avg_rating numeric, review_count int`. The first twelve
    carry the names `Property.fromJson` reads.
  - Filtering, pricing, rating, distance and ordering follow decisions 8–14.
  - Validation raises P0041 `invalid_search` (decision 17).
  - Execute is revoked from `public` and granted to `anon` and
    `authenticated`. This is the same pattern as `ical_export_public`: the
    function only exposes what the anon catalog policies already expose,
    plus the rating aggregates.
  - The definer allow-list in `37_tenancy_isolation_test.sql` gains
    `search_resorts`. The function takes no resort id and returns only active
    resorts, so it needs no role assertion.

## App

- `lib/core/location/geo_point.dart`: `GeoPoint(latitude, longitude)`, with
  `isValid`, `coarse()` (rounded to 2 decimal places), and value equality.
- `lib/core/location/position_service.dart`: `abstract class
  PositionService` has `approximatePosition()` (coarse, cached for 24 h,
  never throws) and `precisePosition()` (fresh, not cached, never throws).
  `NoPositionService` returns null from both. `positionServiceProvider` uses
  `locationServiceProvider`'s instance when that instance also implements
  `PositionService`, and `NoPositionService` otherwise, so existing test fakes
  keep compiling. `currentPositionProvider` is a `FutureProvider<GeoPoint?>`.
- `DeviceLocationService` implements `PositionService`, sharing its fix with
  `currentPlace()` (decision 16). `LocationCache` gains
  `readPoint()` / `writePoint()`, which always store the coarse point with the
  same 24 h validity. The badge's "Set location" retry invalidates both
  providers.
- `lib/data/models/resort_search.dart`:
  - `ResortSort` has the values recommended, distance, priceLow and rating,
    with `dbValue` and `label`.
  - `ResortSearchQuery` holds text, sort, amenities and origin. It has value
    equality, so it can be a provider family key, plus `toParams()` and
    `hasFilters`. `ResortSearchQuery.all` is the unfiltered query.
  - `ResortSearchResult` wraps a `Property` and adds `distanceKm`, `minPrice`,
    `avgRating` and `reviewCount`, with `fromJson`.
  - `distanceLabel(km)` formats a distance.
- `lib/data/repositories/resort_search_repository.dart`: a `ResortSearchSource`
  seam with a single method, `search(query)`, and `ResortSearchRepository`
  implementing it over the `search_resorts` RPC with
  `_guard`/`mapPostgrestError`. It also provides
  `resortSearchSourceProvider` and `resortSearchProvider`
  (`FutureProvider.autoDispose.family<List<ResortSearchResult>,
  ResortSearchQuery>`).
- `Property` gains `latitude`, `longitude` (read from `lat`, `lng`; not in
  `toInsert`) and a `location` getter.
- `lib/core/errors.dart`: P0041 maps to `InvalidSearch`, with the copy "That
  search could not be run. Clear the filters and try again."
- Browse screen (`/`):
  - The hero is unchanged. Below it, a new `BrowseFilterBar`
    (`lib/features/browse/browse_filter_bar.dart`) holds:
    - a search field labelled "Search resorts", hinted "Name, city or
      amenity", with a clear button and a 100-character limit
    - a sort dropdown with Recommended, Distance (only with a position),
      "Price: low to high" and Rating
    - a "Clear filters" button when a query or amenity is active
    - the existing amenity chip row, with "All" first
  - Results: a grid on wide screens and a list on narrow ones, as today.
    Cards show a meta line built from the pieces that exist:
    `★ 4.5 (2)`, `12 km`, `from ₹4,000 / night`. The line is
    `ResortMetaLine` in `lib/features/browse/resort_meta_line.dart`, and
    `PropertyCard` gains optional `distanceKm`, `minPrice`, `avgRating` and
    `reviewCount`.
  - When a search matches nothing: "No resorts match your search", "Try a
    different word or clear the filters.", and a "Clear filters" button that
    resets the text, the amenity and the sort. With no resorts at all, the
    existing "No properties yet" message stays. On a failure, `FailureView`
    shows with Retry. Pull-to-refresh invalidates the search family.
- Owner Settings (`/owner/settings`): under PROPERTY, a new "Map location"
  tile shows the saved pair, or "Not set. Guests will not see how far away
  you are." It opens `LocationSettingsScreen`
  (`lib/features/owner/location_settings_screen.dart`), which has:
  - Latitude and Longitude fields
  - "Use my current location" (`precisePosition()`, filled to 6 decimals)
  - Save, which validates with `parseCoordinates` and calls
    `updateSettings(id, {'lat', 'lng'})`. Leaving both fields empty clears
    the location.

## Rules

- `search_resorts` never returns a resort that is not `active` and
  `is_active`, whatever the caller's memberships.
- The function returns only catalog fields that anon can already read through
  RLS, plus aggregate ratings. It returns no review text, no author and no
  reservation data.
- The only precision at which the guest's position leaves the device, or is
  stored on it, is 2 decimal places.
- The coordinate checks are enforced in the table. The owner screen validates
  first, so the table check is a backstop.
- No existing policy is widened.

## Testing

- pgTAP `supabase/tests/50_guest_search_test.sql`:
  - The contract: signature, OUT columns, anon and authenticated execute,
    definer with a pinned `search_path`, and the three coordinate checks.
  - Filtering: suspended and inactive resorts excluded, even for their owner;
    name, address (city), description and amenity matching; every word
    required; literal `%` and `_`; blank query; amenity filter
    (case-insensitive, all required, blanks ignored).
  - Card fields: `min_price`, which excludes slot rates, inactive units and
    expired overrides, and is null for day-use only; `avg_rating` and
    `review_count`; `distance_km`.
  - P0041 cases.
  - The four sort orders with their tie-breaks, and distance with no position.
  - The same results for anon and a signed-in guest.
  - The owner can set coordinates; staff and guests change 0 rows.
- `37_tenancy_isolation_test.sql`: the allow-list gains `search_resorts`.
- Flutter:
  - `GeoPoint` rounding and validity
  - `positionServiceProvider` fallback
  - `LocationCache` point round trip and expiry
  - the badge retry invalidating the position
  - `ResortSearchResult.fromJson`, `ResortSearchQuery.toParams` and equality,
    and `distanceLabel`
  - the provider passing its key through
  - `Property` lat/lng
  - P0041 copy
  - `ResortMetaLine` and `PropertyCard` meta line
  - Browse:
    - debounced search
    - amenity chip
    - sort menu with and without a position
    - coarse origin sent
    - distance shown on the card
    - previous results kept while loading
    - no-match state and Clear filters
    - error and Retry
    - no resorts at all
    - no overflow at the wide breakpoint
    - the existing hero tests, kept
  - `LocationSettingsScreen`: prefill, current location, unavailable
    location, validation, save, clear
  - the Owner Settings tile
- Playwright (`e2e/tests/guest.spec.ts`): typing a resort's name narrows the
  list, a nonsense word shows the empty state, and "Clear filters" brings
  every resort back.

## Coordination with other projects in this round

- P10 adds a `pending` resort status. `search_resorts` filters on
  `status = 'active'`, so pending resorts stay hidden with no change here.
- P4 also adds fields to `Property`, and P1, P8 and P10 add tiles or cards to
  Owner Settings. Each of these changes only adds lines, so merges are
  additive.

## Out of scope

- A map view.
- Geocoding an address into coordinates (Nominatim forward search).
- Date-aware availability search ("free this weekend").
- Price filters or ranges.
- Full-text ranking or `pg_trgm` indexes. The resort count is small, and a
  sequential scan per search is fine until it is not.
- Saved searches.
- Showing distance on the property page.
- A city column.
