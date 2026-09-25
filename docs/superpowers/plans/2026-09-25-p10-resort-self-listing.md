# Resort Self-Listing (P10) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let any signed-in user apply to list a resort on ResortHub: the resort starts `pending` (hidden from guests, unbookable), its new owner works through a six-item setup checklist on `/owner` and submits it for review, and the platform admin approves it (it goes live) or rejects it with a reason (it is archived and the applicant sees why). Every step is audited and the owner is emailed through the outbox.

**Architecture:** `properties.status` gains `pending`, which `has_resort_role` / `assert_resort_role` treat like `active` for members while every guest path keeps demanding `active`. Application state lives in a new platform-owned table, `listing_applications`, written only by seven `security definer` functions (`apply_for_listing`, `my_listing_applications`, `listing_setup_status`, `submit_listing_for_review`, `platform_listing_applications`, `approve_listing`, `reject_listing`); the checklist is computed on every read by an internal helper. On the app side, one `ListingRepository` backs two seams (`ListingSource` for applicants and owners, `ListingReviewSource` for the console), a `PropertyPhotosSource` uploads to a new public Storage bucket, and four screens change: a new `/list-your-resort`, a checklist card on `/owner`, a Photos screen, and a review queue on `/platform`.

**Tech Stack:** Supabase Postgres 15 (plpgsql, RLS, Storage policies, pgTAP via `supabase test db`), Flutter 3.44 / Dart 3.10, Riverpod 3.3, go_router 17, `image_picker` (already a dependency).

**Spec:** `docs/superpowers/specs/2026-09-25-p10-resort-self-listing-design.md`

## Global Constraints

- One migration: `supabase/migrations/0059_resort_self_listing.sql` (the number pre-assigned to P10). Tasks 1–4 each edit it. It is applied after whatever of `0051`–`0058` (P1–P9) has landed; nothing here needs them. After every edit, rebuild with `supabase db reset` (re-runs every migration and `supabase/seed.sql`), then run pgTAP.
- New pgTAP file: `supabase/tests/49_resort_self_listing_test.sql`. Tasks 1–4 build it up section by section; each section relies on the state the earlier ones leave. Run one file with `supabase test db supabase/tests/49_resort_self_listing_test.sql`, the whole suite with `supabase test db`.
- One new error code, **P0040** (`listing_blocked`), raised with a message written for the reader, shown verbatim by the app as `ListingBlocked`. Exact messages:
  - `You already have a resort waiting for review.` (apply)
  - `This resort is not waiting for review.` (submit)
  - `Finish the setup checklist before submitting.` (submit)
  - `This application has already been decided.` (approve, reject)
  - `This resort has not been submitted for review yet.` (approve)
  - `The setup checklist is no longer complete.` (approve)
  - `Approve or reject this resort instead.` (`set_resort_status` on a pending resort)
- Other codes: **P0005** bad input with these exact messages (the form mirrors them): `Enter the resort name (2 to 80 characters).`, `Enter the city (2 to 60 characters).`, `Enter the full address (5 to 300 characters).`, `Enter a contact phone number, e.g. +91 98765 43210.`, `Describe the resort in 20 to 500 characters.`, `Choose a plan.`, `Give the owner a reason (5 to 500 characters).`; **P0008** not permitted; **P0002** unknown application; **P0020** from `assert_resort_role`.
- Every new `security definer` function has `set search_path = public, pg_temp`, is revoked from `public` and `anon`, granted to `authenticated`, and added to the definer allow-list in `supabase/tests/37_tenancy_isolation_test.sql`. The three internal helpers (`resort_slug_for`, `listing_setup_flags`, `enqueue_listing_message`) are plain functions (not definers, so not on the allow-list), revoked from `public`, `anon` and `authenticated`; they run with the privileges of the definer that calls them.
- Existing functions changed here are copied from their **latest** definition. Before editing one, run `grep -ln "function public\.<name>(" supabase/migrations/*.sql` and copy from the highest-numbered file. On `feat/gaps` when this plan was written: `has_resort_role` and `assert_resort_role` → `0043_resort_tenancy.sql` lines 46–91; `set_resort_status` → `0045_resort_functions.sql` lines 2670–2703; `platform_summary` → `0049_subscriptions.sql` lines 197–229. If a later migration (for example P8's `0057`) redefines one of them, copy that body and make the same one-line change this plan makes.
- "Today" is the Asia/Kolkata date: `(now() at time zone 'Asia/Kolkata')::date`. A trial started by `apply_for_listing` or restarted by `approve_listing` ends today + 30.
- The checklist rules (spec decision 10): photos = `cardinality(images) > 0`; units = an active unit; rates = at least one active unit and every active unit has a `base` or `weekend` rate rule; payment settings = `cardinality(payment_display_methods) > 0`; cancellation policy = a `refund_rules` row; GSTIN and tax = `upper(btrim(gstin)) ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'`.
- pgTAP conventions (from `37_tenancy_isolation_test.sql`): switch users with `set local role authenticated; set local request.jwt.claims to '{"sub":"<uuid>","role":"authenticated"}';`, anon with `set local role anon; set local request.jwt.claims to '';`. `reset role` does not clear the claims, so run `set local request.jwt.claims to '';` after it. Capture a returned id with `set_config('app.<name>', <id>::text, true)` and read it back with `current_setting('app.<name>')::uuid`.
- Dart: repositories wrap every call in `_guard`, which maps errors through `mapPostgrestError` (`lib/core/errors.dart`). Widget tests use fakes from `test/support/` and never a real `SupabaseClient`. A widget test that expects an error state passes `retry: (_, _) => null` to its `ProviderScope`.
- UI copy, exact:
  - Entry: welcome button and account-sheet tile `List your resort`; account-sheet subtitle `Apply to list a resort on ResortHub`.
  - `/list-your-resort`: title `List your resort`; intro `Tell us about your resort. It stays hidden from guests until ResortHub approves it.`; fields `Resort name`, `City`, `Address`, `Contact phone`, `Short description`, `Plan`; plan item `<Tier> — <₹price>/month` (just `<Tier>` while prices load or if they fail); trial line `30-day free trial. No payment needed now.`; button `Apply`; open application card button `Continue setup`; history heading `Earlier applications`.
  - Application status lines: `Setting up`, `Waiting for review since <d MMM yyyy>`, `Approved`, `Not approved: <reason>`.
  - Checklist card: heading `Finish setting up <resort name>`; sub `Your resort is hidden from guests until ResortHub approves it.`; progress `<n> of 6 done`; steps `Add photos` / `Add at least one unit` / `Set rates for every unit` / `Payment settings` / `Cancellation policy` / `GSTIN and tax` with hints `Guests see these on your listing` / `The rooms, cottages or villas guests book` / `A base or weekend price for each active unit` / `Advance % and the payment methods you accept` / `How much guests get back when they cancel` / `Your 15-character GSTIN`; button `Submit for review`; hint `Complete every step to submit.`; after submit `Submitted for review on <d MMM yyyy>. We will email you when it is decided.`; snackbar `Submitted for review.`; live state `Your resort is live` with button `Refresh`; error `Could not load your setup checklist`.
  - Photos screen: title `Photos`; empty `No photos yet`; button `Add photo`; limit hint `You can add up to 10 photos.`; remove tooltip `Remove photo`. Settings tile `Photos` / `Pictures guests see on your listing`.
  - Console: count card `Waiting for review` with `<n> setting up`; filter chip `Pending review`; empty `No resorts are waiting for review.`; card lines `Submitted <d MMM yyyy>` or `Setting up — not submitted yet`; buttons `Approve`, `Reject`; approve dialog `Approve <name>?` / `It goes live for guests now.` / `Cancel` / `Approve`; reject dialog `Reject <name>?`, field `Reason (the owner sees this)`, buttons `Cancel` / `Reject`; resort card chip `Pending review` and note `Waiting for review: see Pending review above.`
- Done / not done is never shown by colour alone: each checklist row has an icon with a semantic label (`Done` / `Not done`) and the console's checklist chips carry a check or cross icon plus the step title.
- Commands: `flutter test <path>`, `flutter test`, `flutter analyze` (baseline: 2 infos in `lib/features/stay/service_request_screen.dart`; no new issues). Never run `dart format` over directories or pre-existing files; format only lines you write. Revert SDK-only `pubspec.lock` bumps.
- Known pgTAP failures that appear only between 00:00 and 05:30 IST: `25` test 9, `26` test 3, `34` test 2. Everything else must pass.
- No secrets anywhere; this project needs none.
- Every commit message ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

## Review Focus

1. **Two taps on Apply (or two tabs) must not create two pending resorts.** People expect one resort and a clear message, not a duplicate and not a raw "value already in use". Owning tests: Task 2 (a second `apply_for_listing` gives P0040 with the message; the partial unique index backs it in Task 1), Task 5 (the Apply button is disabled while the call runs, so a double tap sends one call).
2. **An owner who removes a checklist item after submitting must not go live half set up.** People expect approval to mean "ready to book". Owning tests: Task 4 (approve refuses with `The setup checklist is no longer complete.`), Task 7 (the card refetches after returning from a step's screen, so the owner sees the untick).
3. **A rejected applicant must still see why, and be able to apply again**, even though the resort is archived and their membership no longer opens it. Owning tests: Task 4 (`my_listing_applications` shows `archived|rejected|<reason>`; a new application succeeds), Task 5 (the screen shows `Not approved: <reason>` above a fresh form).
4. **A guest must never see or book a pending resort**, even by pasting its id. Owning tests: Task 2 (anon and a signed-in guest read no row; `get_quote` and `create_hold` give P0022). The owner's own Browse list is filtered to active resorts in Task 5 and checked by hand in Task 9.
5. **"List your resort" tapped while signed out must survive sign-up or sign-in**, not drop the person on Browse. Owning tests: Task 5 (`redirectFor` sends a signed-out visit to `/login?next=%2Flist-your-resort` and honours `next` after sign-in; the login screen goes to `next` after signing in; the welcome button and the login/sign-up links keep `next`; a `next` outside the allow-list is ignored).

## Plan decisions (where the spec leaves a choice)

- Task 1 fixes the contract without changing behaviour: the seven new functions are stubs that raise `0A000`; `has_resort_role`, `assert_resort_role`, `set_resort_status` and `platform_summary` are untouched until Task 2. The status check already accepts `pending`, so the fixtures can insert a pending resort.
- `49_resort_self_listing_test.sql` starts with `delete from public.resort_subscriptions;` inside its transaction (as `41` does), so `platform_summary` numbers are exact.
- The three helpers are plain functions so that they are not RPCs at all (PostgREST exposes them, but `authenticated` cannot execute them) and the allow-list stays the list of callable definers.
- One Dart class, `ListingRepository`, implements both seams; tests override `listingSourceProvider` and `listingReviewSourceProvider` separately.
- `SetupChecklistCard` takes an optional `onOpenStep` callback and `PropertyPhotosScreen` an optional `pickPhoto` callback, so widget tests never pump the real settings screens (which read Supabase) or the platform image picker.
- `postSignInPath(Uri)` in `router.dart` is the single allow-list for `?next=`; `redirectFor` gains an optional `next` argument so the router's pre-auth redirect honours it and stays unit-testable.
- The console's pending filter is per-visit UI state in the screen's `State`, like the search and tier filter.
- Storage-policy tests insert into `storage.objects` as `authenticated`. If the local storage schema's own triggers refuse that insert for reasons unrelated to the policies (the error names a storage function, not `row-level security`), replace Task 2's four storage insert assertions with the policy checks shown in Task 2 Step 4, keeping the plan count.

## Execution tracks

After Task 1, the database track and the app track share no files and can run in parallel (for example in two worktrees branched from Task 1's commit, merged back before Task 9). App tasks never need a database: their tests use `FakeListingSource`, `FakeListingReviewSource` and `FakePropertyPhotosSource`.

| Task | Track | Depends on | Files it owns |
|---|---|---|---|
| 1 Interface contract | both | none | `0059` (schema + stubs), `49` (fixtures + contract), `37` (allow-list), `listing.dart`, `listing_repository.dart`, `property_photos_repository.dart`, `errors.dart`, `outbox_message.dart`, both fakes, their tests |
| 2 Pending resorts and applying | DB | 1 | `0059`, `49`, `supabase/config.toml` |
| 3 Checklist and submit | DB | 2 | `0059`, `49` |
| 4 Review decisions | DB | 3 | `0059`, `49` |
| 5 List your resort | App | 1 | `router.dart`, `welcome_screen.dart`, `login_screen.dart`, `signup_screen.dart`, `app_shell.dart`, `catalog_repository.dart`, `list_your_resort_screen.dart`, their tests |
| 6 Photos screen | App | 1 | `property_photos_screen.dart`, `owner_settings_screen.dart`, their tests |
| 7 Setup checklist | App | 6 | `setup_checklist_card.dart`, `owner_home_screen.dart`, their tests |
| 8 Console review queue | App | 1 | `pending_listings.dart`, `platform_screen.dart`, `resort_card.dart`, their tests |
| 9 Integration | both | 2–8 | none (verification) |

- The database track is strictly sequential: Tasks 2–4 share one migration, one test file and one local Postgres.
- In the app track, Tasks 5, 6 and 8 can run alongside each other after Task 1; Task 7 waits for Task 6 (the checklist opens the Photos screen).

---

## File Structure

**Database**
- Create `supabase/migrations/0059_resort_self_listing.sql`: status check, `city` / `contact_phone`, `listing_applications` with RLS, nullable `outbox.reservation_id`, the photo bucket and its policies, the changed helpers and functions, the seven new definers, three internal helpers and three email templates.
- Create `supabase/tests/49_resort_self_listing_test.sql`: fixtures, contract, pending semantics, applying, storage, checklist, submit, review, notifications.
- Modify `supabase/tests/37_tenancy_isolation_test.sql`: the definer allow-list.
- Modify `supabase/config.toml`: declare the `property-photos` bucket for local stacks.

**App**
- Create `lib/data/models/listing.dart`: `SetupStep`, `ListingSetup`, `ListingDecision`, `ListingApplication`, `PendingListing`, `ListingInput`, validators.
- Create `lib/data/repositories/listing_repository.dart`: `ListingSource`, `ListingReviewSource`, `ListingRepository`, providers.
- Create `lib/data/repositories/property_photos_repository.dart`: `PropertyPhotosSource`, `PropertyPhotosRepository`, `propertyPhotosSourceProvider`, `maxPropertyPhotos`.
- Modify `lib/core/errors.dart` (P0040), `lib/data/models/outbox_message.dart` (nullable reservation).
- Modify `lib/core/router.dart` (route, redirect rules, `postSignInPath`), `lib/features/auth/welcome_screen.dart`, `lib/features/auth/login_screen.dart`, `lib/features/auth/signup_screen.dart`, `lib/features/shell/app_shell.dart` (account sheet tile), `lib/data/repositories/catalog_repository.dart` (Browse shows active resorts only).
- Create `lib/features/listing/list_your_resort_screen.dart`.
- Create `lib/features/owner/property_photos_screen.dart`; modify `lib/features/owner/owner_settings_screen.dart` (Photos tile).
- Create `lib/features/owner/setup_checklist_card.dart`; modify `lib/features/owner/owner_home_screen.dart`.
- Create `lib/features/platform/pending_listings.dart`; modify `lib/features/platform/platform_screen.dart` and `lib/features/platform/resort_card.dart`.
- Tests: create `test/support/fake_listing_source.dart`, `test/support/fake_property_photos_source.dart`, `test/data/listing_test.dart`, `test/data/listing_providers_test.dart`, `test/features/listing/list_your_resort_screen_test.dart`, `test/features/owner/property_photos_screen_test.dart`, `test/features/owner/setup_checklist_card_test.dart`, `test/features/platform/pending_listings_test.dart`; modify `test/core/errors_test.dart`, `test/data/outbox_message_test.dart`, `test/core/router_test.dart`, `test/features/auth/welcome_screen_test.dart`, `test/features/auth/login_screen_test.dart`, `test/features/auth/signup_screen_test.dart`, `test/features/shell/app_shell_test.dart`, `test/features/owner/owner_settings_screen_test.dart`, `test/features/owner/owner_home_screen_test.dart`, `test/features/platform/platform_screen_test.dart`, `test/features/platform/resort_card_test.dart`.

---

## Phase 0: Interface

### Task 1: Interface contract (schema, function signatures, Dart API)

**Track:** both. Every later task depends on it.

**Files:**
- Create: `supabase/migrations/0059_resort_self_listing.sql`
- Create: `supabase/tests/49_resort_self_listing_test.sql`
- Modify: `supabase/tests/37_tenancy_isolation_test.sql` (definer allow-list, the array that starts at line 412)
- Create: `lib/data/models/listing.dart`
- Create: `lib/data/repositories/listing_repository.dart`
- Create: `lib/data/repositories/property_photos_repository.dart`
- Modify: `lib/core/errors.dart` (a class after `AlreadyDispatched`, an arm after `'P0031'`)
- Modify: `lib/data/models/outbox_message.dart` (`reservationId`)
- Create: `test/support/fake_listing_source.dart`, `test/support/fake_property_photos_source.dart`
- Test: `test/data/listing_test.dart`, `test/data/listing_providers_test.dart`, `test/core/errors_test.dart`, `test/data/outbox_message_test.dart`

**Interfaces:**
- Consumes: `public.subscription_tier`, `public.subscription_plans`, `public.resort_subscriptions` (0049); `public.has_resort_role(uuid, boolean, variadic resort_role[])`, `public.is_platform_admin()`; `formatDate` (`lib/core/format.dart`); `SubscriptionTier`, `subscriptionTierFromDb`, `subscriptionTierToDb`, `SubscriptionTierLabel.label` (`lib/data/models/subscription.dart`); `mapPostgrestError`, `supabaseProvider`.
- Produces (SQL; later tasks replace only the bodies):
  - `properties.status` check `('pending','active','suspended','archived')`; `properties.city text`, `properties.contact_phone text`.
  - `public.listing_applications (property_id uuid pk, applicant_id uuid, tier subscription_tier, submitted_at timestamptz, decision text, decided_at timestamptz, decided_by uuid, rejection_reason text, created_at timestamptz)`; index `listing_applications_one_open_per_user`; policy `listing_applications_read`.
  - `outbox.reservation_id` nullable.
  - `public.apply_for_listing(p_name text, p_city text, p_address text, p_contact_phone text, p_description text, p_tier public.subscription_tier default 'starter') returns uuid`
  - `public.my_listing_applications() returns table (property_id uuid, name text, city text, tier public.subscription_tier, property_status text, created_at timestamptz, submitted_at timestamptz, decision text, decided_at timestamptz, rejection_reason text)`
  - `public.listing_setup_status(p_property uuid) returns table (property_status text, submitted_at timestamptz, has_photos boolean, has_unit boolean, has_rates boolean, has_payment_settings boolean, has_cancellation_policy boolean, has_tax_details boolean)`
  - `public.submit_listing_for_review(p_property uuid) returns void`
  - `public.platform_listing_applications() returns table (property_id uuid, name text, city text, address text, contact_phone text, description text, applicant_email text, applicant_name text, tier public.subscription_tier, created_at timestamptz, submitted_at timestamptz, has_photos boolean, has_unit boolean, has_rates boolean, has_payment_settings boolean, has_cancellation_policy boolean, has_tax_details boolean)`
  - `public.approve_listing(p_property uuid) returns void`
  - `public.reject_listing(p_property uuid, p_reason text) returns void`
- Produces (Dart):
  - `enum SetupStep { photos, units, rates, payments, cancellation, tax }` with `title` and `hint` (extension `SetupStepCopy`); `Map<SetupStep, bool> setupFlagsFromRow(Map<String, dynamic>)`.
  - `class ListingSetup { String propertyStatus; DateTime? submittedAt; Map<SetupStep, bool> done; bool isDone(SetupStep); int doneCount; bool complete; bool isPending }` with `fromJson`.
  - `enum ListingDecision { approved, rejected }`, `ListingDecision? listingDecisionFromDb(String?)`.
  - `class ListingApplication { propertyId, name, city, tier, propertyStatus, createdAt, submittedAt?, decision?, decidedAt?, rejectionReason?; bool isOpen; String statusLine }` with `fromJson`.
  - `class PendingListing { propertyId, name, city, address, contactPhone, description, applicantEmail, applicantName?, tier, createdAt, submittedAt?, setup; bool submitted; bool setupComplete; bool canApprove }` with `fromJson`.
  - `class ListingInput { name, city, address, contactPhone, description, tier }`.
  - Validators `validateListingName`, `validateListingCity`, `validateListingAddress`, `validateListingPhone`, `validateListingDescription`, `validateRejectionReason`, each `String? Function(String?)`.
  - `abstract class ListingSource { Future<String> apply(ListingInput); Future<List<ListingApplication>> myApplications(); Future<ListingSetup> setupStatus(String propertyId); Future<void> submitForReview(String propertyId); }`
  - `abstract class ListingReviewSource { Future<List<PendingListing>> pendingListings(); Future<void> approve(String propertyId); Future<void> reject(String propertyId, String reason); }`
  - Providers: `listingRepositoryProvider`, `listingSourceProvider`, `listingReviewSourceProvider`, `myListingApplicationsProvider` (`FutureProvider.autoDispose<List<ListingApplication>>`), `listingSetupProvider` (`FutureProvider.autoDispose.family<ListingSetup, String>`), `pendingListingsProvider` (`FutureProvider<List<PendingListing>>`).
  - `abstract class PropertyPhotosSource { Future<String> upload(String propertyId, {required String filename, required Uint8List bytes, required String contentType}); Future<void> setPhotos(String propertyId, List<String> urls); }`, `propertyPhotosSourceProvider`, `const propertyPhotosBucket = 'property-photos'`, `const maxPropertyPhotos = 10`.
  - `class ListingBlocked extends BookingFailure` (P0040, message verbatim).
  - `OutboxMessage.reservationId` is `String?`.
  - Test support: `FakeListingSource` (`applications`, `setup`, `appliedId`, `applyGate`, `applyError`, `applicationsError`, `setupError`, `submitError`; logs `applyCalls`, `setupCalls`, `submitCalls`, `applicationsCalls`), `FakeListingReviewSource` (`pending`, `pendingError`, `approveError`, `rejectError`; logs `approveCalls`, `rejectCalls` as `(String, String)`, `pendingCalls`), builders `listingSetup({...})`, `listingApplication({...})`, `pendingListing({...})`, `allSetupSteps`; `FakePropertyPhotosSource` (`nextUrl`, `uploadError`, `setError`; logs `uploads` as `(String, String, int)`, `setCalls` as `(String, List<String>)`).

- [ ] **Step 1: Record the baselines**

Run: `supabase db reset && supabase test db 2>&1 | tail -20`, then `flutter analyze 2>&1 | tail -5`, then `flutter test 2>&1 | tail -3`
Expected: write down the pgTAP failure count and names (only the three time-of-day failures listed in Global Constraints may fail, and only between 00:00 and 05:30 IST), the analyzer count (2 infos), and the Flutter pass count. Also run `ls supabase/migrations | tail -3` and check that nothing numbered `0059` exists yet, and run `psql "$(supabase status -o env | grep DB_URL | cut -d= -f2 | tr -d '"')" -At -c "select conname from pg_constraint where conrelid = 'public.properties'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%status%';"`.
Expected: the last command prints exactly `properties_status_check` (the name the migration drops). If it prints another name, use that name in Step 4.

- [ ] **Step 2: Write the failing pgTAP contract test**

Create `supabase/tests/49_resort_self_listing_test.sql`:

```sql
-- Resort self-listing (P10), added in 0059_resort_self_listing.sql. See
-- docs/superpowers/specs/2026-09-25-p10-resort-self-listing-design.md.
--
-- One file, built up by the plan's database tasks in order: each section
-- relies on the state the sections before it leave behind.
--
-- Fixtures:
--   P  platform admin                       49000000-...-0001
--   A  applicant, no membership             49000000-...-0002 (Asha Applicant)
--   B  applicant, no membership             49000000-...-0003
--   G  guest, no membership                 49000000-...-0004
--   O  owner of C and D                     49000000-...-0005 (Chetan Owner)
--   M  admin of C                           49000000-...-0006
--   C  "Listing C", pending, set up by hand: an unsubmitted Pro application
--      by O, a Pro trial ending in 10 days, one active unit (Cottage 1)
--   D  "Listing D", active, Starter, paid with no end date
begin;
select plan(17);

-- "Today" as the listing functions see it.
create function pg_temp.today() returns date
language sql stable as $f$ select (now() at time zone 'Asia/Kolkata')::date $f$;

-- Rows a statement changed, run as the current role (0 when RLS filters it).
create function pg_temp.rows_affected(p_sql text) returns int
language plpgsql as $f$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$f$;

-- platform_summary counts every resort in the database. Start from no
-- subscription rows so only this file's resorts count.
delete from public.resort_subscriptions;

insert into auth.users (id, email) values
  ('49000000-0000-0000-0000-000000000001','list-platform@example.com'),
  ('49000000-0000-0000-0000-000000000002','list-applicant-a@example.com'),
  ('49000000-0000-0000-0000-000000000003','list-applicant-b@example.com'),
  ('49000000-0000-0000-0000-000000000004','list-guest@example.com'),
  ('49000000-0000-0000-0000-000000000005','list-owner-c@example.com'),
  ('49000000-0000-0000-0000-000000000006','list-admin-c@example.com');
update public.profiles set role = 'platform_admin'
  where id = '49000000-0000-0000-0000-000000000001';
update public.profiles set full_name = 'Asha Applicant'
  where id = '49000000-0000-0000-0000-000000000002';
update public.profiles set full_name = 'Chetan Owner'
  where id = '49000000-0000-0000-0000-000000000005';

insert into public.properties (id, name, slug, status, city, address, contact_phone, description) values
  ('49100000-0000-4000-8000-00000000000c','Listing C','listing-c','pending','Pune',
   '1 Hill Road, Pune','+919876543210','A quiet farm stay near the hills.'),
  ('49100000-0000-4000-8000-00000000000d','Listing D','listing-d','active',null,null,null,null);

insert into public.resort_members (property_id, user_id, role) values
  ('49100000-0000-4000-8000-00000000000c','49000000-0000-0000-0000-000000000005','owner'),
  ('49100000-0000-4000-8000-00000000000c','49000000-0000-0000-0000-000000000006','admin'),
  ('49100000-0000-4000-8000-00000000000d','49000000-0000-0000-0000-000000000005','owner');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('49100000-0000-4000-8000-0000000000c1','49100000-0000-4000-8000-00000000000c','Cottage 1',2,4);

insert into public.resort_subscriptions (property_id, tier, status, trial_ends_on) values
  ('49100000-0000-4000-8000-00000000000c','pro','trial',pg_temp.today() + 10),
  ('49100000-0000-4000-8000-00000000000d','starter','active',null);

insert into public.listing_applications (property_id, applicant_id, tier) values
  ('49100000-0000-4000-8000-00000000000c','49000000-0000-0000-0000-000000000005','pro');

-- === Task 1: the contract ===================================================

select has_table('public', 'listing_applications', 'listing_applications exists');
select has_column('public', 'properties', 'city', 'properties.city exists');
select has_column('public', 'properties', 'contact_phone', 'properties.contact_phone exists');
select throws_ok($$insert into public.properties (name, slug, status) values ('Bad', 'bad-status', 'review')$$,
  '23514', null, 'status is still limited to the four known values');
select col_is_null('public', 'outbox', 'reservation_id',
  'an outbox row may have no reservation (listing messages)');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'my_listing_applications'
              and p.parameter_mode = 'OUT'),
  array['property_id','name','city','tier','property_status','created_at',
        'submitted_at','decision','decided_at','rejection_reason'],
  'my_listing_applications returns the columns ListingApplication.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'listing_setup_status'
              and p.parameter_mode = 'OUT'),
  array['property_status','submitted_at','has_photos','has_unit','has_rates',
        'has_payment_settings','has_cancellation_policy','has_tax_details'],
  'listing_setup_status returns the columns ListingSetup.fromJson reads');
select is((select array_agg(p.parameter_name::text order by p.ordinal_position)
             from information_schema.parameters p
             join information_schema.routines r
               on r.specific_schema = p.specific_schema and r.specific_name = p.specific_name
            where r.routine_schema = 'public' and r.routine_name = 'platform_listing_applications'
              and p.parameter_mode = 'OUT'),
  array['property_id','name','city','address','contact_phone','description',
        'applicant_email','applicant_name','tier','created_at','submitted_at',
        'has_photos','has_unit','has_rates','has_payment_settings',
        'has_cancellation_policy','has_tax_details'],
  'platform_listing_applications returns the columns PendingListing.fromJson reads');
select ok(to_regprocedure('public.apply_for_listing(text, text, text, text, text, public.subscription_tier)') is not null,
  'apply_for_listing takes the five fields and a tier');
select is((select array_agg(f::text order by f::text)
             from unnest(array[
               'public.apply_for_listing(text, text, text, text, text, public.subscription_tier)',
               'public.my_listing_applications()',
               'public.listing_setup_status(uuid)',
               'public.submit_listing_for_review(uuid)',
               'public.platform_listing_applications()',
               'public.approve_listing(uuid)',
               'public.reject_listing(uuid, text)']::regprocedure[]) f
            where has_function_privilege('anon', f, 'execute')),
  null, 'anon can execute none of the listing functions');
select is((select count(*)::int
             from unnest(array[
               'public.apply_for_listing(text, text, text, text, text, public.subscription_tier)',
               'public.my_listing_applications()',
               'public.listing_setup_status(uuid)',
               'public.submit_listing_for_review(uuid)',
               'public.platform_listing_applications()',
               'public.approve_listing(uuid)',
               'public.reject_listing(uuid, text)']::regprocedure[]) f
            where has_function_privilege('authenticated', f, 'execute')),
  7, 'authenticated can execute all seven');
select throws_ok($$insert into public.listing_applications (property_id, applicant_id, tier)
  values ('49100000-0000-4000-8000-00000000000d', '49000000-0000-0000-0000-000000000005', 'starter')$$,
  '23505', null, 'one undecided application per user, enforced by the table');

-- Direct reads and writes: the applicant reads their own row; nobody
-- writes directly. (The resort's admin reading it needs pending access,
-- which arrives in Task 2 and is tested there.)
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select array_agg(property_id::text) from public.listing_applications),
  array['49100000-0000-4000-8000-00000000000c'],
  'the owner reads their resort''s application');
select throws_ok($$update public.listing_applications set submitted_at = now()$$,
  '42501', null, 'the owner cannot mark their own application submitted');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int from public.listing_applications), 0, 'a guest reads none');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.listing_applications), 0,
  'the platform admin has no direct row access');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$insert into public.listing_applications (property_id, applicant_id, tier)
  values ('49100000-0000-4000-8000-00000000000d', '49000000-0000-0000-0000-000000000002', 'starter')$$,
  '42501', null, 'nobody inserts an application directly');
reset role;
set local request.jwt.claims to '';

select * from finish();
rollback;
```

- [ ] **Step 3: Run it to verify it fails**

Run: `supabase test db supabase/tests/49_resort_self_listing_test.sql`
Expected: FAIL at the fixture `insert into public.properties ... 'pending'` with `violates check constraint "properties_status_check"` (or `column "city" ... does not exist`).

- [ ] **Step 4: Write the migration's schema and function contract**

Create `supabase/migrations/0059_resort_self_listing.sql`:

```sql
-- Resort self-listing (P10): a signed-in user applies to list a resort,
-- which starts `pending` -- hidden from guests and unbookable, but set up
-- by its new owner like an active resort -- until the platform admin
-- approves it (-> active) or rejects it with a reason (-> archived). See
-- docs/superpowers/specs/2026-09-25-p10-resort-self-listing-design.md.
--
-- Errors: P0040 listing_blocked (a listing-state refusal; the message is
-- written for the reader and shown verbatim), P0005 bad input, P0008 not
-- permitted, P0002 unknown application, P0020 not an owner/admin of the
-- resort (assert_resort_role).

-- ---------------------------------------------------------------------
-- properties: the new status, and the two fields an application adds.
-- `add column if not exists`: P11 (guest search) also wants `city`.
alter table public.properties drop constraint properties_status_check;
alter table public.properties add constraint properties_status_check
  check (status in ('pending','active','suspended','archived'));

alter table public.properties
  add column if not exists city text,
  add column if not exists contact_phone text;

-- ---------------------------------------------------------------------
-- listing_applications: one row per applied resort. Platform-owned: the
-- owner reads it but cannot write it (properties_update would let them
-- forge a submission or a decision if these were properties columns).
-- Written only by the security definer functions below.
create table public.listing_applications (
  property_id      uuid primary key references public.properties(id) on delete cascade,
  applicant_id     uuid not null references public.profiles(id) on delete cascade,
  tier             public.subscription_tier not null references public.subscription_plans(tier),
  submitted_at     timestamptz,
  decision         text
    constraint listing_applications_decision_check check (decision in ('approved','rejected')),
  decided_at       timestamptz,
  decided_by       uuid references public.profiles(id) on delete set null,
  rejection_reason text,
  created_at       timestamptz not null default now(),
  constraint listing_applications_decided_together
    check ((decision is null) = (decided_at is null)),
  constraint listing_applications_rejection_has_reason
    check (decision is distinct from 'rejected'
           or length(btrim(coalesce(rejection_reason, ''))) > 0)
);

-- "One pending application per user" (spec decision 8): at most one
-- application without a decision.
create unique index listing_applications_one_open_per_user
  on public.listing_applications (applicant_id) where decision is null;

alter table public.listing_applications enable row level security;
revoke all on public.listing_applications from anon, authenticated;
grant select on public.listing_applications to authenticated;
create policy listing_applications_read on public.listing_applications
  for select to authenticated
  using (applicant_id = auth.uid()
         or public.has_resort_role(property_id, false, 'owner','admin'));

-- ---------------------------------------------------------------------
-- outbox: a listing message belongs to a resort but to no reservation.
-- outbox_fill_property (0044) already leaves a row with no reservation
-- alone, and outbox.property_id stays not null (0045).
alter table public.outbox alter column reservation_id drop not null;

-- ---------------------------------------------------------------------
-- Functions. The signatures are the contract the app is built against;
-- Tasks 2-4 of the plan replace the bodies.

create function public.apply_for_listing(
  p_name          text,
  p_city          text,
  p_address       text,
  p_contact_phone text,
  p_description   text,
  p_tier          public.subscription_tier default 'starter'
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'apply_for_listing is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.my_listing_applications()
returns table(
  property_id      uuid,
  name             text,
  city             text,
  tier             public.subscription_tier,
  property_status  text,
  created_at       timestamptz,
  submitted_at     timestamptz,
  decision         text,
  decided_at       timestamptz,
  rejection_reason text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'my_listing_applications is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.listing_setup_status(p_property uuid)
returns table(
  property_status         text,
  submitted_at            timestamptz,
  has_photos              boolean,
  has_unit                boolean,
  has_rates               boolean,
  has_payment_settings    boolean,
  has_cancellation_policy boolean,
  has_tax_details         boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'listing_setup_status is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.submit_listing_for_review(p_property uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'submit_listing_for_review is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.platform_listing_applications()
returns table(
  property_id             uuid,
  name                    text,
  city                    text,
  address                 text,
  contact_phone           text,
  description             text,
  applicant_email         text,
  applicant_name          text,
  tier                    public.subscription_tier,
  created_at              timestamptz,
  submitted_at            timestamptz,
  has_photos              boolean,
  has_unit                boolean,
  has_rates               boolean,
  has_payment_settings    boolean,
  has_cancellation_policy boolean,
  has_tax_details         boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'platform_listing_applications is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.approve_listing(p_property uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'approve_listing is not implemented yet' using errcode = '0A000';
end;
$$;

create function public.reject_listing(p_property uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'reject_listing is not implemented yet' using errcode = '0A000';
end;
$$;

revoke execute on function public.apply_for_listing(text, text, text, text, text, public.subscription_tier) from public, anon;
revoke execute on function public.my_listing_applications() from public, anon;
revoke execute on function public.listing_setup_status(uuid) from public, anon;
revoke execute on function public.submit_listing_for_review(uuid) from public, anon;
revoke execute on function public.platform_listing_applications() from public, anon;
revoke execute on function public.approve_listing(uuid) from public, anon;
revoke execute on function public.reject_listing(uuid, text) from public, anon;
grant execute on function public.apply_for_listing(text, text, text, text, text, public.subscription_tier) to authenticated;
grant execute on function public.my_listing_applications() to authenticated;
grant execute on function public.listing_setup_status(uuid) to authenticated;
grant execute on function public.submit_listing_for_review(uuid) to authenticated;
grant execute on function public.platform_listing_applications() to authenticated;
grant execute on function public.approve_listing(uuid) to authenticated;
grant execute on function public.reject_listing(uuid, text) to authenticated;
```

- [ ] **Step 5: Add the seven functions to the definer allow-list**

In `supabase/tests/37_tenancy_isolation_test.sql`, in the array passed to `p.proname <> all (array[ ... ])`, find:

```sql
        'report_collections','report_ledger','report_settlements','finance_summary',
```

and add directly below it:

```sql
        -- 0059: resort self-listing. apply_for_listing and
        -- my_listing_applications act only for auth.uid();
        -- listing_setup_status / submit_listing_for_review assert the role
        -- at the resort they are given; the other three check
        -- is_platform_admin().
        'apply_for_listing','my_listing_applications','listing_setup_status',
        'submit_listing_for_review','platform_listing_applications',
        'approve_listing','reject_listing',
```

(If another project added lines to this array meanwhile, keep theirs; only add these.)

- [ ] **Step 6: Run the database tests**

Run: `supabase db reset && supabase test db supabase/tests/49_resort_self_listing_test.sql supabase/tests/37_tenancy_isolation_test.sql supabase/tests/36_resort_tenancy_test.sql supabase/tests/13_outbox_test.sql`
Expected: PASS — 49 at 17/17, and 37, 36 and 13 at their baseline counts.

- [ ] **Step 7: Write the failing Dart tests**

Create `test/data/listing_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/listing.dart';
import 'package:pasala/data/models/subscription.dart';

Map<String, dynamic> _flags({
  bool photos = false,
  bool unit = false,
  bool rates = false,
  bool payments = false,
  bool cancellation = false,
  bool tax = false,
}) => {
  'has_photos': photos,
  'has_unit': unit,
  'has_rates': rates,
  'has_payment_settings': payments,
  'has_cancellation_policy': cancellation,
  'has_tax_details': tax,
};

void main() {
  group('ListingSetup.fromJson', () {
    test('reads the status, the submission and each flag', () {
      final setup = ListingSetup.fromJson({
        'property_status': 'pending',
        'submitted_at': null,
        ..._flags(unit: true, rates: true),
      });

      expect(setup.isPending, isTrue);
      expect(setup.submittedAt, isNull);
      expect(setup.isDone(SetupStep.units), isTrue);
      expect(setup.isDone(SetupStep.photos), isFalse);
      expect(setup.doneCount, 2);
      expect(setup.complete, isFalse);
    });

    test('is complete only when all six are done', () {
      final setup = ListingSetup.fromJson({
        'property_status': 'pending',
        'submitted_at': '2026-09-20T10:00:00+00:00',
        ..._flags(
          photos: true,
          unit: true,
          rates: true,
          payments: true,
          cancellation: true,
          tax: true,
        ),
      });

      expect(setup.complete, isTrue);
      expect(setup.doneCount, 6);
      expect(setup.submittedAt, DateTime.utc(2026, 9, 20, 10));
    });

    test('a missing flag counts as not done', () {
      final setup = ListingSetup.fromJson({
        'property_status': 'active',
        'submitted_at': null,
      });

      expect(setup.doneCount, 0);
      expect(setup.isPending, isFalse);
    });
  });

  group('ListingApplication', () {
    Map<String, dynamic> row({
      String? submittedAt,
      String? decision,
      String? reason,
      String status = 'pending',
    }) => {
      'property_id': 'r1',
      'name': 'Green Acres',
      'city': 'Nashik',
      'tier': 'pro',
      'property_status': status,
      'created_at': '2026-09-19T10:00:00+00:00',
      'submitted_at': submittedAt,
      'decision': decision,
      'decided_at': decision == null ? null : '2026-09-24T10:00:00+00:00',
      'rejection_reason': reason,
    };

    test('parses a row still being set up', () {
      final app = ListingApplication.fromJson(row());

      expect(app.propertyId, 'r1');
      expect(app.tier, SubscriptionTier.pro);
      expect(app.isOpen, isTrue);
      expect(app.statusLine, 'Setting up');
    });

    test('a submitted row says since when', () {
      final app = ListingApplication.fromJson(
        row(submittedAt: '2026-09-20T12:00:00+00:00'),
      );

      expect(app.statusLine, 'Waiting for review since 20 Sep 2026');
    });

    test('an approved row is closed', () {
      final app = ListingApplication.fromJson(
        row(decision: 'approved', status: 'active'),
      );

      expect(app.isOpen, isFalse);
      expect(app.decision, ListingDecision.approved);
      expect(app.statusLine, 'Approved');
    });

    test('a rejected row carries the reason', () {
      final app = ListingApplication.fromJson(
        row(
          decision: 'rejected',
          reason: 'Photos do not match the address.',
          status: 'archived',
        ),
      );

      expect(app.statusLine, 'Not approved: Photos do not match the address.');
      expect(app.propertyStatus, 'archived');
    });

    test('an unknown decision is rejected, not defaulted', () {
      expect(() => listingDecisionFromDb('maybe'), throwsArgumentError);
    });
  });

  group('PendingListing.fromJson', () {
    Map<String, dynamic> row({String? submittedAt, bool tax = true}) => {
      'property_id': 'r1',
      'name': 'Green Acres',
      'city': 'Nashik',
      'address': '12 Vineyard Road, Nashik',
      'contact_phone': '+919876543210',
      'description': 'Vineyard cottages with a pool and a view.',
      'applicant_email': 'asha@example.com',
      'applicant_name': null,
      'tier': 'starter',
      'created_at': '2026-09-19T10:00:00+00:00',
      'submitted_at': submittedAt,
      ..._flags(
        photos: true,
        unit: true,
        rates: true,
        payments: true,
        cancellation: true,
        tax: tax,
      ),
    };

    test('can be approved only when submitted and complete', () {
      final ready = PendingListing.fromJson(
        row(submittedAt: '2026-09-20T12:00:00+00:00'),
      );
      final notSubmitted = PendingListing.fromJson(row());
      final incomplete = PendingListing.fromJson(
        row(submittedAt: '2026-09-20T10:00:00+00:00', tax: false),
      );

      expect(ready.canApprove, isTrue);
      expect(ready.applicantName, isNull);
      expect(notSubmitted.submitted, isFalse);
      expect(notSubmitted.canApprove, isFalse);
      expect(incomplete.setupComplete, isFalse);
      expect(incomplete.canApprove, isFalse);
    });
  });

  group('validators mirror apply_for_listing', () {
    test('name: 2 to 80 characters after trimming', () {
      expect(validateListingName('  '), 'Enter the resort name (2 to 80 characters).');
      expect(validateListingName('A'), isNotNull);
      expect(validateListingName('A' * 81), isNotNull);
      expect(validateListingName(' Green Acres '), isNull);
    });

    test('city: 2 to 60 characters', () {
      expect(validateListingCity(''), 'Enter the city (2 to 60 characters).');
      expect(validateListingCity('Nashik'), isNull);
    });

    test('address: 5 to 300 characters', () {
      expect(validateListingAddress('Road'), 'Enter the full address (5 to 300 characters).');
      expect(validateListingAddress('12 Vineyard Road'), isNull);
    });

    test('phone: 10 to 13 digits, spaces and dashes ignored, optional +', () {
      const message = 'Enter a contact phone number, e.g. +91 98765 43210.';
      expect(validateListingPhone('+91 98765 43210'), isNull);
      expect(validateListingPhone('98765-43210'), isNull);
      expect(validateListingPhone('12345'), message);
      expect(validateListingPhone('phone me'), message);
      expect(validateListingPhone('+91 98765 43210 99'), message);
    });

    test('description: 20 to 500 characters', () {
      expect(
        validateListingDescription('Nice place'),
        'Describe the resort in 20 to 500 characters.',
      );
      expect(validateListingDescription('A' * 20), isNull);
      expect(validateListingDescription('A' * 501), isNotNull);
    });

    test('rejection reason: 5 to 500 characters', () {
      expect(
        validateRejectionReason(' no '),
        'Give the owner a reason (5 to 500 characters).',
      );
      expect(validateRejectionReason('Photos do not match.'), isNull);
    });
  });

  test('every step has a title and a hint', () {
    expect(SetupStep.values.map((s) => s.title).toList(), [
      'Add photos',
      'Add at least one unit',
      'Set rates for every unit',
      'Payment settings',
      'Cancellation policy',
      'GSTIN and tax',
    ]);
    expect(SetupStep.tax.hint, 'Your 15-character GSTIN');
  });
}
```

Create `test/data/listing_providers_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/listing.dart';
import 'package:pasala/data/repositories/listing_repository.dart';

import '../support/fake_listing_source.dart';

void main() {
  test('listingSetupProvider asks for the resort it is keyed by', () async {
    final source = FakeListingSource()
      ..setup = listingSetup(done: {SetupStep.units});
    final container = ProviderContainer(
      overrides: [listingSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    final a = container.listen(listingSetupProvider('p1'), (_, _) {});
    final b = container.listen(listingSetupProvider('p2'), (_, _) {});
    addTearDown(a.close);
    addTearDown(b.close);

    final setup = await container.read(listingSetupProvider('p1').future);
    await container.read(listingSetupProvider('p2').future);

    expect(setup.doneCount, 1);
    expect(source.setupCalls, ['p1', 'p2']);
  });

  test('myListingApplicationsProvider reads through the seam', () async {
    final source = FakeListingSource()
      ..applications = [listingApplication(name: 'Green Acres')];
    final container = ProviderContainer(
      overrides: [listingSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(myListingApplicationsProvider, (_, _) {});
    addTearDown(sub.close);

    final apps = await container.read(myListingApplicationsProvider.future);

    expect(apps.single.name, 'Green Acres');
    expect(source.applicationsCalls, 1);
  });

  test('pendingListingsProvider reads through the review seam', () async {
    final source = FakeListingReviewSource()
      ..pending = [pendingListing(propertyId: 'r9')];
    final container = ProviderContainer(
      overrides: [listingReviewSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    final pending = await container.read(pendingListingsProvider.future);

    expect(pending.single.propertyId, 'r9');
    expect(source.pendingCalls, 1);
  });
}
```

In `test/core/errors_test.dart`, after the `P0031` test, add:

```dart
  test('P0040 maps to ListingBlocked and keeps the server message', () {
    final failure = map('P0040', 'Finish the setup checklist before submitting.');
    expect(failure, isA<ListingBlocked>());
    expect(failure.message, 'Finish the setup checklist before submitting.');
  });
```

In `test/data/outbox_message_test.dart`, before the closing `}` of `main`, add:

```dart
  test('parses a listing message with no reservation', () {
    final message = OutboxMessage.fromJson(const {
      'id': 'm9',
      'reservation_id': null,
      'channel': 'email',
      'recipient': 'owner@example.com',
      'template': 'listing_approved',
      'subject': 'Green Acres is live on ResortHub',
      'body': 'Hi Asha, ...',
      'status': 'pending',
      'attempts': 0,
      'last_error': null,
      'created_at': '2026-09-25T10:00:00Z',
      'sent_at': null,
    });

    expect(message.reservationId, isNull);
    expect(message.template, 'listing_approved');
  });
```

- [ ] **Step 8: Run them to verify they fail**

Run: `flutter test test/data/listing_test.dart test/data/listing_providers_test.dart test/core/errors_test.dart test/data/outbox_message_test.dart`
Expected: FAIL to compile — `listing.dart`, `listing_repository.dart`, `fake_listing_source.dart` and `ListingBlocked` do not exist.

- [ ] **Step 9: Write the models**

Create `lib/data/models/listing.dart`:

```dart
import '../../core/format.dart';
import 'subscription.dart';

/// One item on a pending resort's setup checklist (spec decision 10). The
/// server decides whether each is done (`listing_setup_status`,
/// 0059_resort_self_listing.sql); the app only names them.
enum SetupStep { photos, units, rates, payments, cancellation, tax }

extension SetupStepCopy on SetupStep {
  String get title => switch (this) {
    SetupStep.photos => 'Add photos',
    SetupStep.units => 'Add at least one unit',
    SetupStep.rates => 'Set rates for every unit',
    SetupStep.payments => 'Payment settings',
    SetupStep.cancellation => 'Cancellation policy',
    SetupStep.tax => 'GSTIN and tax',
  };

  String get hint => switch (this) {
    SetupStep.photos => 'Guests see these on your listing',
    SetupStep.units => 'The rooms, cottages or villas guests book',
    SetupStep.rates => 'A base or weekend price for each active unit',
    SetupStep.payments => 'Advance % and the payment methods you accept',
    SetupStep.cancellation => 'How much guests get back when they cancel',
    SetupStep.tax => 'Your 15-character GSTIN',
  };
}

/// The six `has_*` columns `listing_setup_status` and
/// `platform_listing_applications` share. A missing column counts as not
/// done.
Map<SetupStep, bool> setupFlagsFromRow(Map<String, dynamic> row) => {
  SetupStep.photos: row['has_photos'] as bool? ?? false,
  SetupStep.units: row['has_unit'] as bool? ?? false,
  SetupStep.rates: row['has_rates'] as bool? ?? false,
  SetupStep.payments: row['has_payment_settings'] as bool? ?? false,
  SetupStep.cancellation: row['has_cancellation_policy'] as bool? ?? false,
  SetupStep.tax: row['has_tax_details'] as bool? ?? false,
};

DateTime? _timeOrNull(Object? raw) =>
    raw == null ? null : DateTime.parse(raw as String).toUtc();

/// `listing_setup_status(p_property)`: the resort's status, when it was
/// submitted, and which checklist items are done.
class ListingSetup {
  const ListingSetup({
    required this.propertyStatus,
    required this.done,
    this.submittedAt,
  });

  factory ListingSetup.fromJson(Map<String, dynamic> json) => ListingSetup(
    propertyStatus: json['property_status'] as String,
    submittedAt: _timeOrNull(json['submitted_at']),
    done: setupFlagsFromRow(json),
  );

  /// `properties.status`: `pending` while it waits, `active` once approved.
  final String propertyStatus;
  final DateTime? submittedAt;
  final Map<SetupStep, bool> done;

  bool isDone(SetupStep step) => done[step] ?? false;
  int get doneCount => SetupStep.values.where(isDone).length;
  bool get complete => doneCount == SetupStep.values.length;
  bool get isPending => propertyStatus == 'pending';
}

enum ListingDecision { approved, rejected }

/// Unknown text is rejected rather than defaulted, like the other enums.
ListingDecision? listingDecisionFromDb(String? raw) => switch (raw) {
  null => null,
  'approved' => ListingDecision.approved,
  'rejected' => ListingDecision.rejected,
  _ => throw ArgumentError('Unknown listing decision: $raw'),
};

/// One row of `my_listing_applications()`: an application the signed-in
/// user made, including decided ones (a rejected resort is archived and no
/// longer reachable through the membership, so this is where its reason
/// shows).
class ListingApplication {
  const ListingApplication({
    required this.propertyId,
    required this.name,
    required this.city,
    required this.tier,
    required this.propertyStatus,
    required this.createdAt,
    this.submittedAt,
    this.decision,
    this.decidedAt,
    this.rejectionReason,
  });

  factory ListingApplication.fromJson(Map<String, dynamic> json) =>
      ListingApplication(
        propertyId: json['property_id'] as String,
        name: json['name'] as String,
        city: json['city'] as String? ?? '',
        tier: subscriptionTierFromDb(json['tier'] as String),
        propertyStatus: json['property_status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        submittedAt: _timeOrNull(json['submitted_at']),
        decision: listingDecisionFromDb(json['decision'] as String?),
        decidedAt: _timeOrNull(json['decided_at']),
        rejectionReason: json['rejection_reason'] as String?,
      );

  final String propertyId;
  final String name;
  final String city;
  final SubscriptionTier tier;
  final String propertyStatus;
  final DateTime createdAt;
  final DateTime? submittedAt;
  final ListingDecision? decision;
  final DateTime? decidedAt;
  final String? rejectionReason;

  /// Still waiting for a decision (being set up, or submitted).
  bool get isOpen => decision == null;

  String get statusLine => switch (decision) {
    ListingDecision.approved => 'Approved',
    ListingDecision.rejected =>
      'Not approved: ${rejectionReason ?? 'no reason given'}',
    null => submittedAt == null
        ? 'Setting up'
        : 'Waiting for review since ${formatDate(submittedAt!.toLocal())}',
  };
}

/// One row of `platform_listing_applications()`: an undecided application
/// as the platform admin reviews it.
class PendingListing {
  const PendingListing({
    required this.propertyId,
    required this.name,
    required this.city,
    required this.address,
    required this.contactPhone,
    required this.description,
    required this.applicantEmail,
    required this.tier,
    required this.createdAt,
    required this.setup,
    this.applicantName,
    this.submittedAt,
  });

  factory PendingListing.fromJson(Map<String, dynamic> json) => PendingListing(
    propertyId: json['property_id'] as String,
    name: json['name'] as String,
    city: json['city'] as String? ?? '',
    address: json['address'] as String? ?? '',
    contactPhone: json['contact_phone'] as String? ?? '',
    description: json['description'] as String? ?? '',
    applicantEmail: json['applicant_email'] as String? ?? '',
    applicantName: json['applicant_name'] as String?,
    tier: subscriptionTierFromDb(json['tier'] as String),
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    submittedAt: _timeOrNull(json['submitted_at']),
    setup: setupFlagsFromRow(json),
  );

  final String propertyId;
  final String name;
  final String city;
  final String address;
  final String contactPhone;
  final String description;
  final String applicantEmail;
  final String? applicantName;
  final SubscriptionTier tier;
  final DateTime createdAt;
  final DateTime? submittedAt;
  final Map<SetupStep, bool> setup;

  bool get submitted => submittedAt != null;
  bool get setupComplete => SetupStep.values.every((s) => setup[s] ?? false);

  /// `approve_listing` refuses anything else (P0040).
  bool get canApprove => submitted && setupComplete;
}

/// What the "List your resort" form sends to `apply_for_listing`.
class ListingInput {
  const ListingInput({
    required this.name,
    required this.city,
    required this.address,
    required this.contactPhone,
    required this.description,
    required this.tier,
  });

  final String name;
  final String city;
  final String address;
  final String contactPhone;
  final String description;
  final SubscriptionTier tier;
}

// Validators: the same rules and messages as apply_for_listing and
// reject_listing (P0005), so the form catches them before the server does.

String? _length(String? value, int min, int max, String message) {
  final length = (value ?? '').trim().length;
  return length < min || length > max ? message : null;
}

String? validateListingName(String? value) =>
    _length(value, 2, 80, 'Enter the resort name (2 to 80 characters).');

String? validateListingCity(String? value) =>
    _length(value, 2, 60, 'Enter the city (2 to 60 characters).');

String? validateListingAddress(String? value) =>
    _length(value, 5, 300, 'Enter the full address (5 to 300 characters).');

String? validateListingPhone(String? value) {
  final compact = (value ?? '').trim().replaceAll(RegExp(r'[ -]'), '');
  return RegExp(r'^\+?[0-9]{10,13}$').hasMatch(compact)
      ? null
      : 'Enter a contact phone number, e.g. +91 98765 43210.';
}

String? validateListingDescription(String? value) =>
    _length(value, 20, 500, 'Describe the resort in 20 to 500 characters.');

String? validateRejectionReason(String? value) =>
    _length(value, 5, 500, 'Give the owner a reason (5 to 500 characters).');
```

- [ ] **Step 10: Write the repositories**

Create `lib/data/repositories/listing_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/listing.dart';
import '../models/subscription.dart';

/// What an applicant and a pending resort's owner need
/// (0059_resort_self_listing.sql). Tests override [listingSourceProvider]
/// with `FakeListingSource` (test/support/fake_listing_source.dart).
abstract class ListingSource {
  /// Creates the pending resort and returns its id. P0040
  /// ([ListingBlocked]) when the user already has an open application.
  Future<String> apply(ListingInput input);

  /// The signed-in user's applications, newest first, decided ones too.
  Future<List<ListingApplication>> myApplications();

  /// The checklist of [propertyId] (owner or admin; P0020 otherwise).
  Future<ListingSetup> setupStatus(String propertyId);

  /// Owner only. P0040 when the checklist is not complete.
  Future<void> submitForReview(String propertyId);
}

/// What the platform console needs. Tests override
/// [listingReviewSourceProvider] with `FakeListingReviewSource`.
abstract class ListingReviewSource {
  /// Undecided applications, submitted ones first.
  Future<List<PendingListing>> pendingListings();

  Future<void> approve(String propertyId);

  Future<void> reject(String propertyId, String reason);
}

class ListingRepository implements ListingSource, ListingReviewSource {
  ListingRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<String> apply(ListingInput input) => _guard(() async {
    final id = await _db.rpc(
      'apply_for_listing',
      params: {
        'p_name': input.name.trim(),
        'p_city': input.city.trim(),
        'p_address': input.address.trim(),
        'p_contact_phone': input.contactPhone.trim(),
        'p_description': input.description.trim(),
        'p_tier': subscriptionTierToDb(input.tier),
      },
    );
    return id as String;
  });

  @override
  Future<List<ListingApplication>> myApplications() => _guard(() async {
    final rows = await _db.rpc('my_listing_applications') as List<dynamic>;
    return rows
        .map((e) => ListingApplication.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  @override
  Future<ListingSetup> setupStatus(String propertyId) => _guard(() async {
    final rows =
        await _db.rpc(
              'listing_setup_status',
              params: {'p_property': propertyId},
            )
            as List<dynamic>;
    if (rows.isEmpty) throw const NotFound();
    return ListingSetup.fromJson(rows.first as Map<String, dynamic>);
  });

  @override
  Future<void> submitForReview(String propertyId) => _guard(() async {
    await _db.rpc(
      'submit_listing_for_review',
      params: {'p_property': propertyId},
    );
  });

  @override
  Future<List<PendingListing>> pendingListings() => _guard(() async {
    final rows =
        await _db.rpc('platform_listing_applications') as List<dynamic>;
    return rows
        .map((e) => PendingListing.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  @override
  Future<void> approve(String propertyId) => _guard(() async {
    await _db.rpc('approve_listing', params: {'p_property': propertyId});
  });

  @override
  Future<void> reject(String propertyId, String reason) => _guard(() async {
    await _db.rpc(
      'reject_listing',
      params: {'p_property': propertyId, 'p_reason': reason.trim()},
    );
  });
}

final listingRepositoryProvider = Provider<ListingRepository>(
  (ref) => ListingRepository(ref.watch(supabaseProvider)),
);

final listingSourceProvider = Provider<ListingSource>(
  (ref) => ref.watch(listingRepositoryProvider),
);

final listingReviewSourceProvider = Provider<ListingReviewSource>(
  (ref) => ref.watch(listingRepositoryProvider),
);

/// `autoDispose`: the "List your resort" page refetches on every visit, so
/// a decision made meanwhile shows up.
final myListingApplicationsProvider =
    FutureProvider.autoDispose<List<ListingApplication>>(
      (ref) => ref.watch(listingSourceProvider).myApplications(),
    );

/// Keyed by property id so switching resort never shows another resort's
/// checklist.
final listingSetupProvider = FutureProvider.autoDispose
    .family<ListingSetup, String>(
      (ref, propertyId) =>
          ref.watch(listingSourceProvider).setupStatus(propertyId),
    );

final pendingListingsProvider = FutureProvider<List<PendingListing>>(
  (ref) => ref.watch(listingReviewSourceProvider).pendingListings(),
);
```

Create `lib/data/repositories/property_photos_repository.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';

/// The public Storage bucket for listing photos (0059). Objects live at
/// `{property_id}/{file}`; only the resort's owners and admins may write.
const propertyPhotosBucket = 'property-photos';

/// The Photos screen stops offering "Add photo" at this many.
const maxPropertyPhotos = 10;

/// Tests override [propertyPhotosSourceProvider] with
/// `FakePropertyPhotosSource` (test/support/fake_property_photos_source.dart).
abstract class PropertyPhotosSource {
  /// Uploads one photo for [propertyId] and returns its public URL.
  Future<String> upload(
    String propertyId, {
    required String filename,
    required Uint8List bytes,
    required String contentType,
  });

  /// Replaces `properties.images` with [urls], in order.
  Future<void> setPhotos(String propertyId, List<String> urls);
}

class PropertyPhotosRepository implements PropertyPhotosSource {
  PropertyPhotosRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<String> upload(
    String propertyId, {
    required String filename,
    required Uint8List bytes,
    required String contentType,
  }) => _guard(() async {
    final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        '$propertyId/${DateTime.now().microsecondsSinceEpoch}_$safeName';
    final bucket = _db.storage.from(propertyPhotosBucket);
    await bucket.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: contentType),
    );
    return bucket.getPublicUrl(path);
  });

  @override
  Future<void> setPhotos(String propertyId, List<String> urls) =>
      _guard(() async {
        await _db
            .from('properties')
            .update({'images': urls})
            .eq('id', propertyId);
      });
}

final propertyPhotosSourceProvider = Provider<PropertyPhotosSource>(
  (ref) => PropertyPhotosRepository(ref.watch(supabaseProvider)),
);
```

- [ ] **Step 11: Map P0040 and make the outbox reservation optional**

In `lib/core/errors.dart`, directly after the `AlreadyDispatched` class, add:

```dart
/// P0040 -- a listing-state refusal (0059_resort_self_listing.sql): a
/// second open application, submitting an unfinished checklist, deciding
/// an application twice, approving one that was never submitted. The
/// server writes each message for the person reading it, so it is shown
/// verbatim.
class ListingBlocked extends BookingFailure {
  const ListingBlocked(super.message);
}
```

and in `mapPostgrestError`'s switch, directly after `'P0031' => const AlreadyDispatched(),`, add:

```dart
    // P0040: resort self-listing (0059). Messages are written for the
    // reader.
    'P0040' => ListingBlocked(message),
```

In `lib/data/models/outbox_message.dart`, replace

```dart
  final String id;
  final String reservationId;
```

with

```dart
  final String id;

  /// The reservation a guest message is about; null for a platform message
  /// to a resort owner (the listing emails of 0059_resort_self_listing.sql).
  final String? reservationId;
```

and replace

```dart
        reservationId: json['reservation_id'] as String,
```

with

```dart
        reservationId: json['reservation_id'] as String?,
```

Then run `grep -rn "reservationId" lib/features/outbox lib/data/repositories/outbox_repository.dart`.
Expected: no output (nothing else reads the field). If a line appears, make it handle null (show nothing for a null reservation).

- [ ] **Step 12: Write the fakes**

Create `test/support/fake_listing_source.dart`:

```dart
import 'dart:async';

import 'package:pasala/data/models/listing.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/listing_repository.dart';

final allSetupSteps = SetupStep.values.toSet();

/// A checklist for tests: [done] lists the finished steps.
ListingSetup listingSetup({
  String status = 'pending',
  DateTime? submittedAt,
  Set<SetupStep> done = const {},
}) => ListingSetup(
  propertyStatus: status,
  submittedAt: submittedAt,
  done: {for (final s in SetupStep.values) s: done.contains(s)},
);

/// An application for tests, still being set up unless told otherwise.
ListingApplication listingApplication({
  String propertyId = 'r1',
  String name = 'Green Acres',
  String city = 'Nashik',
  SubscriptionTier tier = SubscriptionTier.starter,
  String propertyStatus = 'pending',
  DateTime? submittedAt,
  ListingDecision? decision,
  String? rejectionReason,
}) => ListingApplication(
  propertyId: propertyId,
  name: name,
  city: city,
  tier: tier,
  propertyStatus: propertyStatus,
  createdAt: DateTime.utc(2026, 9, 19, 10),
  submittedAt: submittedAt,
  decision: decision,
  decidedAt: decision == null ? null : DateTime.utc(2026, 9, 24, 10),
  rejectionReason: rejectionReason,
);

/// A console row for tests: complete checklist unless [done] says
/// otherwise, not submitted unless [submittedAt] is given.
PendingListing pendingListing({
  String propertyId = 'r1',
  String name = 'Green Acres',
  String city = 'Nashik',
  String applicantEmail = 'asha@example.com',
  String? applicantName = 'Asha Applicant',
  SubscriptionTier tier = SubscriptionTier.pro,
  DateTime? submittedAt,
  Set<SetupStep>? done,
}) => PendingListing(
  propertyId: propertyId,
  name: name,
  city: city,
  address: '12 Vineyard Road, Nashik',
  contactPhone: '+919876543210',
  description: 'Vineyard cottages with a pool and a view.',
  applicantEmail: applicantEmail,
  applicantName: applicantName,
  tier: tier,
  createdAt: DateTime.utc(2026, 9, 19, 10),
  submittedAt: submittedAt,
  setup: {
    for (final s in SetupStep.values) s: (done ?? allSetupSteps).contains(s),
  },
);

/// In-memory [ListingSource]. Set [applications] / [setup] for what the
/// server would return, an `...Error` to make that call throw, and read
/// the call logs. While [applyGate] is set, `apply` waits for it, so a
/// test can tap twice during one call.
class FakeListingSource implements ListingSource {
  List<ListingApplication> applications = [];
  ListingSetup setup = listingSetup();
  String appliedId = 'new-resort';
  Completer<void>? applyGate;
  Object? applyError;
  Object? applicationsError;
  Object? setupError;
  Object? submitError;

  final List<ListingInput> applyCalls = [];
  final List<String> setupCalls = [];
  final List<String> submitCalls = [];
  int applicationsCalls = 0;

  @override
  Future<String> apply(ListingInput input) async {
    applyCalls.add(input);
    if (applyGate != null) await applyGate!.future;
    if (applyError != null) throw applyError!;
    return appliedId;
  }

  @override
  Future<List<ListingApplication>> myApplications() async {
    applicationsCalls++;
    if (applicationsError != null) throw applicationsError!;
    return applications;
  }

  @override
  Future<ListingSetup> setupStatus(String propertyId) async {
    setupCalls.add(propertyId);
    if (setupError != null) throw setupError!;
    return setup;
  }

  @override
  Future<void> submitForReview(String propertyId) async {
    submitCalls.add(propertyId);
    if (submitError != null) throw submitError!;
    setup = ListingSetup(
      propertyStatus: setup.propertyStatus,
      done: setup.done,
      submittedAt: DateTime.utc(2026, 9, 25, 12),
    );
  }
}

/// In-memory [ListingReviewSource]. A decision removes the row from
/// [pending], so a refetch shows it gone.
class FakeListingReviewSource implements ListingReviewSource {
  List<PendingListing> pending = [];
  Object? pendingError;
  Object? approveError;
  Object? rejectError;

  final List<String> approveCalls = [];
  final List<(String, String)> rejectCalls = [];
  int pendingCalls = 0;

  @override
  Future<List<PendingListing>> pendingListings() async {
    pendingCalls++;
    if (pendingError != null) throw pendingError!;
    return pending;
  }

  @override
  Future<void> approve(String propertyId) async {
    approveCalls.add(propertyId);
    if (approveError != null) throw approveError!;
    pending = [
      for (final p in pending)
        if (p.propertyId != propertyId) p,
    ];
  }

  @override
  Future<void> reject(String propertyId, String reason) async {
    rejectCalls.add((propertyId, reason));
    if (rejectError != null) throw rejectError!;
    pending = [
      for (final p in pending)
        if (p.propertyId != propertyId) p,
    ];
  }
}
```

Create `test/support/fake_property_photos_source.dart`:

```dart
import 'dart:typed_data';

import 'package:pasala/data/repositories/property_photos_repository.dart';

/// In-memory [PropertyPhotosSource]. `upload` returns [nextUrl] and logs
/// `(propertyId, filename, byte count)`; `setPhotos` logs the full list.
class FakePropertyPhotosSource implements PropertyPhotosSource {
  String nextUrl = 'https://cdn.example.com/p1/new.jpg';
  Object? uploadError;
  Object? setError;

  final List<(String, String, int)> uploads = [];
  final List<(String, List<String>)> setCalls = [];

  @override
  Future<String> upload(
    String propertyId, {
    required String filename,
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploads.add((propertyId, filename, bytes.length));
    if (uploadError != null) throw uploadError!;
    return nextUrl;
  }

  @override
  Future<void> setPhotos(String propertyId, List<String> urls) async {
    setCalls.add((propertyId, List.of(urls)));
    if (setError != null) throw setError!;
  }
}
```

- [ ] **Step 13: Run the Dart tests and the analyzer**

Run: `flutter test test/data/listing_test.dart test/data/listing_providers_test.dart test/core/errors_test.dart test/data/outbox_message_test.dart && flutter analyze 2>&1 | tail -5`
Expected: all PASS; the analyzer shows only the 2 baseline infos.

- [ ] **Step 14: Commit**

```bash
git add supabase/migrations/0059_resort_self_listing.sql supabase/tests/49_resort_self_listing_test.sql supabase/tests/37_tenancy_isolation_test.sql lib/data/models/listing.dart lib/data/repositories/listing_repository.dart lib/data/repositories/property_photos_repository.dart lib/core/errors.dart lib/data/models/outbox_message.dart test/support/fake_listing_source.dart test/support/fake_property_photos_source.dart test/data/listing_test.dart test/data/listing_providers_test.dart test/core/errors_test.dart test/data/outbox_message_test.dart
git commit -m "feat(listing): fix the self-listing contract (schema, stubs, Dart API)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
## Phase 1: Database track (Tasks 2 → 3 → 4, sequential)

### Task 2: Pending resorts and applying

**Track:** DB. **Depends on:** Task 1.

**Files:**
- Modify: `supabase/migrations/0059_resort_self_listing.sql`
- Modify: `supabase/tests/49_resort_self_listing_test.sql`
- Modify: `supabase/config.toml` (after the `[storage.buckets.maintenance-photos]` block)

**Interfaces:**
- Consumes: Task 1's table, columns and stubs; `has_resort_role` / `assert_resort_role` (0043), `set_resort_status` (0045), `platform_summary` (0049), `create_resort`'s slug rule (0049).
- Produces:
  - `has_resort_role` and `assert_resort_role` treat `pending` like `active` (same signatures).
  - `set_resort_status(uuid, text)` raises P0040 `Approve or reject this resort instead.` for a pending resort.
  - `platform_summary()` ignores pending resorts.
  - Internal `public.resort_slug_for(p_name text) returns text`.
  - Real bodies of `apply_for_listing(...) returns uuid` and `my_listing_applications()`.
  - Storage bucket `property-photos` and policies `property_photos_insert`, `property_photos_read`, `property_photos_delete` on `storage.objects`.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/49_resort_self_listing_test.sql`, change `select plan(17);` to `select plan(53);`, and insert this section directly above `select * from finish();`:

```sql
-- === Task 2: pending resorts and applying ==================================

-- A pending resort is set up by its members exactly like an active one.
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000005","role":"authenticated"}';
select ok(public.has_resort_role('49100000-0000-4000-8000-00000000000c', true, 'owner'),
  'an owner may write at their pending resort');
select lives_ok($$select public.assert_resort_role('49100000-0000-4000-8000-00000000000c', true, 'owner','admin')$$,
  'assert_resort_role lets the owner write at a pending resort');
select is(pg_temp.rows_affected($$update public.properties
    set description = 'A quiet farm stay near the hills, with a pool.'
  where id = '49100000-0000-4000-8000-00000000000c'$$), 1,
  'the owner edits their pending resort');
select lives_ok($$insert into public.units (id, property_id, name, capacity_base, capacity_max)
  values ('49100000-0000-4000-8000-0000000000c2','49100000-0000-4000-8000-00000000000c','Cottage 2',2,4)$$,
  'the owner adds a unit at a pending resort');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000006","role":"authenticated"}';
select is((select count(*)::int from public.listing_applications), 1,
  'the resort''s admin reads the application of their pending resort');
select ok(public.has_resort_role('49100000-0000-4000-8000-00000000000c', true, 'admin'),
  'an admin may write there too');

-- Guests and anon see nothing and book nothing.
reset role;
set local request.jwt.claims to '';
set local role anon;
select is((select count(*)::int from public.properties
            where id = '49100000-0000-4000-8000-00000000000c'), 0,
  'anon cannot see a pending resort');
select is((select count(*)::int from public.units
            where property_id = '49100000-0000-4000-8000-00000000000c'), 0,
  'anon cannot see its units');
reset role;
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000004","role":"authenticated"}';
select is((select count(*)::int from public.properties
            where id = '49100000-0000-4000-8000-00000000000c'), 0,
  'a signed-in guest cannot see it either');
select throws_ok($$select public.get_quote('49100000-0000-4000-8000-0000000000c1',
    tstzrange('2027-05-01 14:00+05:30','2027-05-02 11:00+05:30','[)'), 2)$$,
  'P0022', null, 'a pending resort gives no quote');
select throws_ok($$select public.create_hold('49100000-0000-4000-8000-0000000000c1',
    '2027-05-01', '2027-05-02', 2)$$,
  'P0022', null, 'a pending resort takes no booking');

-- Applying.
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.apply_for_listing('Platform Stay', 'Goa', '1 Beach Road, Goa',
    '+91 98765 43210', 'A platform admin should not be able to apply.', 'starter')$$,
  'P0008', null, 'the platform admin adds resorts from the console, not by applying');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$select public.apply_for_listing(' ', 'Nashik', '12 Vineyard Road, Nashik',
    '+91 98765 43210', 'Vineyard cottages with a pool and a view.', 'pro')$$,
  'P0005', 'Enter the resort name (2 to 80 characters).', 'a blank name is refused');
select throws_ok($$select public.apply_for_listing('Green Acres', 'Nashik', '12 Vineyard Road, Nashik',
    '12345', 'Vineyard cottages with a pool and a view.', 'pro')$$,
  'P0005', 'Enter a contact phone number, e.g. +91 98765 43210.', 'a short phone number is refused');
select throws_ok($$select public.apply_for_listing('Green Acres', 'Nashik', '12 Vineyard Road, Nashik',
    '+91 98765 43210', 'Nice place', 'pro')$$,
  'P0005', 'Describe the resort in 20 to 500 characters.', 'a too-short description is refused');
select throws_ok($$select public.apply_for_listing('Green Acres', 'Nashik', '12 Vineyard Road, Nashik',
    '+91 98765 43210', 'Vineyard cottages with a pool and a view.', null)$$,
  'P0005', 'Choose a plan.', 'a missing plan is refused');
select ok(set_config('app.list_a',
    public.apply_for_listing('  Green Acres ', 'Nashik', ' 12 Vineyard Road, Nashik ',
      '+91 98765-43210', 'Vineyard cottages with a pool and a view.', 'pro')::text,
    true) is not null,
  'applicant A applies');
select throws_ok($$select public.apply_for_listing('Second Stay', 'Nashik', '14 Vineyard Road, Nashik',
    '+91 98765 43210', 'A second resort while the first one is pending.', 'starter')$$,
  'P0040', 'You already have a resort waiting for review.',
  'one open application per user');
select is((select concat_ws('|', name, city, tier::text, property_status,
                            (submitted_at is null)::text, coalesce(decision, 'none'))
             from public.my_listing_applications()),
  'Green Acres|Nashik|pro|pending|true|none', 'A sees their application');
select ok(public.has_resort_role(current_setting('app.list_a')::uuid, true, 'owner'),
  'A owns the new resort and can set it up');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000003","role":"authenticated"}';
select ok(set_config('app.list_b',
    public.apply_for_listing('Green Acres', 'Lonavala', '5 Lake Road, Lonavala',
      '9876501234', 'Lakeside tents and a big lawn for events.')::text,
    true) is not null,
  'applicant B applies with the default plan');
select is((select count(*)::int from public.my_listing_applications()), 1,
  'B sees only their own application');
reset role;
set local request.jwt.claims to '';

select is((select concat_ws('|', status, slug, city, contact_phone, address)
             from public.properties where id = current_setting('app.list_a')::uuid),
  'pending|green-acres|Nashik|+919876543210|12 Vineyard Road, Nashik',
  'A''s resort is pending, trimmed, with the phone stored without spaces or dashes');
select is((select slug from public.properties where id = current_setting('app.list_b')::uuid),
  'green-acres-2', 'a taken name gets a numbered slug');
select is((select concat_ws('|', tier::text, status::text, trial_ends_on - pg_temp.today())
             from public.resort_subscriptions
            where property_id = current_setting('app.list_a')::uuid),
  'pro|trial|30', 'A starts a 30-day trial of the plan they chose');
select is((select tier::text from public.resort_subscriptions
            where property_id = current_setting('app.list_b')::uuid),
  'starter', 'the default plan is Starter');
select is((select array_agg(action order by action) from public.audit_log
            where property_id = current_setting('app.list_a')::uuid),
  array['listing:apply','subscription:create'], 'applying writes both audit rows');
select ok(not has_function_privilege('authenticated', 'public.resort_slug_for(text)', 'execute'),
  'resort_slug_for is internal');

-- Suspend / Reactivate cannot bypass review; pending counts for nothing.
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.set_resort_status('49100000-0000-4000-8000-00000000000c', 'active')$$,
  'P0040', 'Approve or reject this resort instead.', 'a pending resort cannot be activated by hand');
select throws_ok($$select public.set_resort_status('49100000-0000-4000-8000-00000000000c', 'suspended')$$,
  'P0040', 'Approve or reject this resort instead.', 'nor suspended');
select is((select concat_ws('|', subscribed_count, active_count, trial_count, mrr_inr::int)
             from public.platform_summary()),
  '1|1|0|2999', 'pending resorts count for nothing: only D is subscribed');
reset role;
set local request.jwt.claims to '';

-- Listing photos: the resort's owners and admins upload into its folder.
select is((select public from storage.buckets where id = 'property-photos'), true,
  'the photo bucket is public');
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000005","role":"authenticated"}';
select lives_ok($$insert into storage.objects (bucket_id, name)
  values ('property-photos', '49100000-0000-4000-8000-00000000000c/1.jpg')$$,
  'the owner uploads a photo for their pending resort');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000006","role":"authenticated"}';
select lives_ok($$insert into storage.objects (bucket_id, name)
  values ('property-photos', '49100000-0000-4000-8000-00000000000c/2.jpg')$$,
  'the admin uploads too');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000002","role":"authenticated"}';
select throws_ok($$insert into storage.objects (bucket_id, name)
  values ('property-photos', '49100000-0000-4000-8000-00000000000c/3.jpg')$$,
  '42501', null, 'someone else cannot upload into that resort''s folder');
select throws_ok($$insert into storage.objects (bucket_id, name)
  values ('property-photos', 'not-a-resort/1.jpg')$$,
  '42501', null, 'a path that names no resort is refused');
reset role;
set local request.jwt.claims to '';
```

- [ ] **Step 2: Run them to verify they fail**

Run: `supabase test db supabase/tests/49_resort_self_listing_test.sql`
Expected: FAIL — test 18 ("an owner may write at their pending resort") fails, and the `apply_for_listing` assertions die with `0A000 ... not implemented yet`.

- [ ] **Step 3: Implement pending access, applying, the console guards and photo storage**

Append to `supabase/migrations/0059_resort_self_listing.sql`, directly above the `revoke execute on function public.apply_for_listing` line:

```sql
-- ---------------------------------------------------------------------
-- A pending resort is set up by its members exactly like an active one.
-- Guests still see and book only `active` resorts: every guest policy
-- (0044) and booking function (0045) checks `status = 'active'` itself,
-- and none of them is touched here. Copied from 0043 with only the status
-- tests changed.
create or replace function public.has_resort_role(
  p_property uuid,
  p_write    boolean,
  variadic p_roles public.resort_role[]
) returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select m.role = any (p_roles)
       and (p.status in ('active','pending') or (p.status = 'suspended' and not p_write))
      from public.resort_members m
      join public.properties p on p.id = m.property_id
     where m.property_id = p_property and m.user_id = auth.uid()
  ), false);
$$;

create or replace function public.assert_resort_role(
  p_property uuid,
  p_write    boolean,
  variadic p_roles public.resort_role[]
) returns void
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_role   public.resort_role;
  v_status text;
begin
  select m.role, p.status into v_role, v_status
    from public.resort_members m
    join public.properties p on p.id = m.property_id
   where m.property_id = p_property and m.user_id = auth.uid();
  if v_role is null or not (v_role = any (p_roles)) then
    raise exception using errcode = 'P0020', message = 'not_a_member';
  end if;
  if p_write and v_status not in ('active','pending') then
    raise exception using errcode = 'P0022', message = 'resort_suspended';
  end if;
  if not p_write and v_status = 'archived' then
    raise exception using errcode = 'P0020', message = 'not_a_member';
  end if;
end;
$$;

-- 0045's set_resort_status, refusing a pending resort: Suspend or
-- Reactivate must not bypass the review (spec decision 13). Setting a
-- resort TO pending was already refused by the status list below.
create or replace function public.set_resort_status(p_property uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_old text;
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if p_status is null or p_status not in ('active','suspended','archived') then
    raise exception 'status must be active, suspended or archived' using errcode = 'P0005';
  end if;

  select status into v_old from public.properties where id = p_property for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;

  if v_old = 'pending' then
    raise exception 'Approve or reject this resort instead.' using errcode = 'P0040';
  end if;

  if v_old = p_status then
    return;
  end if;

  update public.properties set status = p_status where id = p_property;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'property', p_property, 'status:' || v_old || '->' || p_status,
          jsonb_build_object('status', v_old), jsonb_build_object('status', p_status),
          p_property);
end;
$$;

-- 0049's platform_summary, leaving pending resorts out like archived ones
-- (spec decision 14). Only the final `where` changed.
create or replace function public.platform_summary()
returns table(
  subscribed_count int,
  active_count     int,
  trial_count      int,
  mrr_inr          numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  return query
    select
      (count(*) filter (where s.status <> 'cancelled'))::int,
      (count(*) filter (where s.status <> 'cancelled' and not x.lapsed))::int,
      (count(*) filter (where s.status = 'trial' and not x.lapsed))::int,
      coalesce(sum(pl.monthly_price_inr)
                 filter (where s.status = 'active' and not x.lapsed), 0)
    from public.resort_subscriptions s
    join public.properties p on p.id = s.property_id
    join public.subscription_plans pl on pl.tier = s.tier
    cross join lateral (
      select public.subscription_lapsed(s.status, s.trial_ends_on, s.paid_through) as lapsed
    ) x
    where p.status not in ('archived', 'pending');
end;
$$;

-- Internal: create_resort's slug rule (0049) -- the name lower-cased with
-- non-alphanumerics collapsed to '-', plus '-2', '-3', ... when taken. A
-- plain function, called only from apply_for_listing.
create function public.resort_slug_for(p_name text)
returns text
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_base text;
  v_slug text;
  v_n    int := 1;
begin
  v_base := trim(both '-' from regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '-', 'g'));
  if v_base = '' then
    v_base := 'resort';
  end if;
  v_slug := v_base;
  while exists (select 1 from public.properties where slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;
  return v_slug;
end;
$$;

revoke execute on function public.resort_slug_for(text) from public, anon, authenticated;

-- A signed-in user applies (spec decisions 2, 8, 9, 18, 19, 21): a pending
-- resort with the caller as owner, a 30-day trial of the chosen tier, and
-- the application. The platform admin uses create_resort instead.
create or replace function public.apply_for_listing(
  p_name          text,
  p_city          text,
  p_address       text,
  p_contact_phone text,
  p_description   text,
  p_tier          public.subscription_tier default 'starter'
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_name  text := btrim(coalesce(p_name, ''));
  v_city  text := btrim(coalesce(p_city, ''));
  v_addr  text := btrim(coalesce(p_address, ''));
  v_phone text := regexp_replace(btrim(coalesce(p_contact_phone, '')), '[ -]', '', 'g');
  v_desc  text := btrim(coalesce(p_description, ''));
  v_id    uuid;
  v_sub   public.resort_subscriptions;
begin
  if v_uid is null or public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if length(v_name) not between 2 and 80 then
    raise exception 'Enter the resort name (2 to 80 characters).' using errcode = 'P0005';
  end if;
  if length(v_city) not between 2 and 60 then
    raise exception 'Enter the city (2 to 60 characters).' using errcode = 'P0005';
  end if;
  if length(v_addr) not between 5 and 300 then
    raise exception 'Enter the full address (5 to 300 characters).' using errcode = 'P0005';
  end if;
  if v_phone !~ '^\+?[0-9]{10,13}$' then
    raise exception 'Enter a contact phone number, e.g. +91 98765 43210.' using errcode = 'P0005';
  end if;
  if length(v_desc) not between 20 and 500 then
    raise exception 'Describe the resort in 20 to 500 characters.' using errcode = 'P0005';
  end if;
  if p_tier is null then
    raise exception 'Choose a plan.' using errcode = 'P0005';
  end if;

  -- Serialise this user's applications, so two taps at once give P0040
  -- here rather than a unique violation from the partial index.
  perform pg_advisory_xact_lock(hashtext('listing:' || v_uid::text));
  if exists (select 1 from public.listing_applications
              where applicant_id = v_uid and decision is null) then
    raise exception 'You already have a resort waiting for review.' using errcode = 'P0040';
  end if;

  insert into public.properties (name, slug, status, city, address, contact_phone, description)
  values (v_name, public.resort_slug_for(v_name), 'pending', v_city, v_addr, v_phone, v_desc)
  returning id into v_id;

  insert into public.resort_members (property_id, user_id, role)
  values (v_id, v_uid, 'owner');

  insert into public.resort_subscriptions (property_id, tier, status, trial_ends_on)
  values (v_id, p_tier, 'trial', (now() at time zone 'Asia/Kolkata')::date + 30)
  returning * into v_sub;

  insert into public.listing_applications (property_id, applicant_id, tier)
  values (v_id, v_uid, p_tier);

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values
    (v_uid, 'listing', v_id, 'listing:apply', null,
     jsonb_build_object('name', v_name, 'city', v_city, 'tier', p_tier), v_id),
    (v_uid, 'subscription', v_id, 'subscription:create', null, to_jsonb(v_sub), v_id);

  return v_id;
end;
$$;

-- The caller's own applications, decided ones too, newest first. Reads by
-- applicant, not by membership: a rejected resort is archived and no
-- longer opens through the membership, but its reason must still show
-- (spec decision 15).
create or replace function public.my_listing_applications()
returns table(
  property_id      uuid,
  name             text,
  city             text,
  tier             public.subscription_tier,
  property_status  text,
  created_at       timestamptz,
  submitted_at     timestamptz,
  decision         text,
  decided_at       timestamptz,
  rejection_reason text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  return query
    select a.property_id, p.name, p.city, a.tier, p.status, a.created_at,
           a.submitted_at, a.decision, a.decided_at, a.rejection_reason
      from public.listing_applications a
      join public.properties p on p.id = a.property_id
     where a.applicant_id = auth.uid()
     order by a.created_at desc, a.property_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Listing photos (spec decision 17): a public bucket, objects at
-- `{property_id}/{file}`. The resort's owners and admins write (at an
-- active or pending resort) and read; anyone may fetch a public URL.
-- supabase/config.toml declares the bucket for local stacks too.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('property-photos', 'property-photos', true, 10485760,
        array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do nothing;

create policy property_photos_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'property-photos'
              and exists (select 1 from public.properties p
                           where p.id::text = (storage.foldername(objects.name))[1]
                             and public.has_resort_role(p.id, true, 'owner','admin')));

create policy property_photos_read on storage.objects
  for select to authenticated
  using (bucket_id = 'property-photos'
         and exists (select 1 from public.properties p
                      where p.id::text = (storage.foldername(objects.name))[1]
                        and public.has_resort_role(p.id, false, 'owner','admin')));

create policy property_photos_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'property-photos'
         and exists (select 1 from public.properties p
                      where p.id::text = (storage.foldername(objects.name))[1]
                        and public.has_resort_role(p.id, true, 'owner','admin')));
```

Leave the Task 1 stubs of `apply_for_listing` and `my_listing_applications` where they are: the `create or replace` statements above come later in the same file and replace their bodies, and the grants given at the end of the file still apply. (The other five stubs stay until Tasks 3 and 4, which follow the same pattern.)

In `supabase/config.toml`, directly after the `[storage.buckets.maintenance-photos]` block (after its `allowed_mime_types` line), add:

```toml

[storage.buckets.property-photos]
public = true
file_size_limit = "10MiB"
allowed_mime_types = ["image/png", "image/jpeg", "image/webp"]
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/49_resort_self_listing_test.sql supabase/tests/36_resort_tenancy_test.sql supabase/tests/37_tenancy_isolation_test.sql supabase/tests/38_resort_members_test.sql supabase/tests/41_subscriptions_test.sql`
Expected: PASS — 49 at 53/53; 36, 37, 38 and 41 at their baseline counts (41's counts have no pending resort, and 38's `set_resort_status` cases never touch one).

If assertions 50–53 (the four storage inserts) fail with an error raised inside a `storage.` function rather than `new row violates row-level security policy`, the local storage schema refuses direct SQL inserts by `authenticated` for reasons of its own. Then replace everything in the Task 2 section from the `set local role authenticated;` line just after the bucket assertion down to the section's last `set local request.jwt.claims to '';` with these four assertions, which run as `postgres` and check the policies instead, and keep `plan(53)`:

```sql
select is((select count(*)::int from pg_policies
            where schemaname = 'storage' and tablename = 'objects'
              and policyname in ('property_photos_insert','property_photos_read','property_photos_delete')),
  3, 'the three photo policies exist');
select ok((select with_check from pg_policies where schemaname = 'storage' and tablename = 'objects'
             and policyname = 'property_photos_insert') like '%has_resort_role%true%owner%admin%',
  'uploads need owner or admin write access at the resort named by the path');
select ok((select qual from pg_policies where schemaname = 'storage' and tablename = 'objects'
             and policyname = 'property_photos_delete') like '%has_resort_role%true%owner%admin%',
  'deletes need the same write access');
select ok((select qual from pg_policies where schemaname = 'storage' and tablename = 'objects'
             and policyname = 'property_photos_read') like '%has_resort_role%false%owner%admin%',
  'owners and admins read their resort''s objects');
```

Then run a manual upload check in Task 9 Step 4 instead.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0059_resort_self_listing.sql supabase/tests/49_resort_self_listing_test.sql supabase/config.toml
git commit -m "feat(db): pending resorts, applying to list, listing photo storage

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The setup checklist and submitting for review

**Track:** DB. **Depends on:** Task 2.

**Files:**
- Modify: `supabase/migrations/0059_resort_self_listing.sql`
- Modify: `supabase/tests/49_resort_self_listing_test.sql`

**Interfaces:**
- Consumes: Task 2's pending access; `outbox`, `outbox_templates` (0017, 0043), `refund_rules` (0013), `rate_rules` (0004), `units`.
- Produces:
  - Internal `public.listing_setup_flags(p_property uuid) returns table (has_photos boolean, has_unit boolean, has_rates boolean, has_payment_settings boolean, has_cancellation_policy boolean, has_tax_details boolean)`.
  - Internal `public.enqueue_listing_message(p_property uuid, p_template text) returns void`.
  - Platform default templates `listing_submitted`, `listing_approved`, `listing_rejected` (email).
  - Real bodies of `listing_setup_status(uuid)` and `submit_listing_for_review(uuid)`.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/49_resort_self_listing_test.sql`, change `select plan(53);` to `select plan(79);`, and insert this section directly above `select * from finish();`:

```sql
-- === Task 3: the checklist and submitting ==================================

-- C so far: two active units (Cottage 1, Cottage 2), no rates, no photos,
-- no payment methods, no refund rules, no GSTIN.
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000005","role":"authenticated"}';
select is((select concat_ws('|', property_status, has_photos::text, has_unit::text, has_rates::text,
                            has_payment_settings::text, has_cancellation_policy::text,
                            has_tax_details::text, (submitted_at is null)::text)
             from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  'pending|false|true|false|false|false|false|true',
  'a fresh pending resort has only its units done');
select throws_ok($$select public.submit_listing_for_review('49100000-0000-4000-8000-00000000000c')$$,
  'P0040', 'Finish the setup checklist before submitting.', 'an unfinished checklist cannot be submitted');

-- The owner works through the checklist with the ordinary writes.
select lives_ok($$update public.properties
    set images = array['https://example.com/c1.jpg'],
        payment_display_methods = array['UPI'],
        gstin = '29abcde1234f1z5'
  where id = '49100000-0000-4000-8000-00000000000c'$$,
  'the owner adds a photo, a payment method and a GSTIN (lower case)');
select lives_ok($$insert into public.refund_rules (property_id, min_days_before, refund_pct)
  values ('49100000-0000-4000-8000-00000000000c', 7, 100)$$,
  'the owner adds a cancellation rule');
select lives_ok($$insert into public.rate_rules (unit_id, kind, price)
  values ('49100000-0000-4000-8000-0000000000c1', 'base', 3000)$$,
  'the owner prices Cottage 1');
select is((select has_rates::text from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  'false', 'every active unit needs a rate: Cottage 2 has none');
select lives_ok($$insert into public.rate_rules (unit_id, kind, price, valid_from, valid_to)
  values ('49100000-0000-4000-8000-0000000000c2', 'override', 3500, '2027-12-24', '2027-12-26')$$,
  'the owner gives Cottage 2 a holiday override');
select is((select has_rates::text from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  'false', 'an override alone is a date range, not a standing price');
select lives_ok($$update public.units set is_active = false
  where id = '49100000-0000-4000-8000-0000000000c2'$$,
  'the owner switches Cottage 2 off');
select is((select has_rates::text from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  'true', 'an inactive unit does not need a rate');
select lives_ok($$update public.properties set gstin = '29ABCDE1234F1Z'
  where id = '49100000-0000-4000-8000-00000000000c'$$,
  'the owner mistypes the GSTIN');
select is((select has_tax_details::text from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  'false', 'a malformed GSTIN does not count');
select lives_ok($$update public.properties set gstin = '29abcde1234f1z5'
  where id = '49100000-0000-4000-8000-00000000000c'$$,
  'the owner fixes it');
select is((select concat_ws('|', property_status, has_photos::text, has_unit::text, has_rates::text,
                            has_payment_settings::text, has_cancellation_policy::text,
                            has_tax_details::text, (submitted_at is null)::text)
             from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  'pending|true|true|true|true|true|true|true', 'the checklist is complete');

set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000006","role":"authenticated"}';
select is((select has_photos::text from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  'true', 'the resort''s admin reads the checklist');
select throws_ok($$select public.submit_listing_for_review('49100000-0000-4000-8000-00000000000c')$$,
  'P0020', null, 'only the owner submits');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000004","role":"authenticated"}';
select throws_ok($$select * from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')$$,
  'P0020', null, 'a stranger cannot read the checklist');

set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000005","role":"authenticated"}';
select lives_ok($$select public.submit_listing_for_review('49100000-0000-4000-8000-00000000000c')$$,
  'the owner submits a complete resort');
select lives_ok($$select public.submit_listing_for_review('49100000-0000-4000-8000-00000000000c')$$,
  'submitting twice is harmless');
select is((select submitted_at is not null
             from public.listing_setup_status('49100000-0000-4000-8000-00000000000c')),
  true, 'the checklist shows the submission');
select throws_ok($$select public.submit_listing_for_review('49100000-0000-4000-8000-00000000000d')$$,
  'P0040', 'This resort is not waiting for review.', 'an active resort cannot be submitted');
select is((select concat_ws('|', template, recipient, status::text, (reservation_id is null)::text)
             from public.outbox where property_id = '49100000-0000-4000-8000-00000000000c'),
  'listing_submitted|list-owner-c@example.com|pending|true',
  'one submission email to the owner, with no reservation, readable by the owner');
reset role;
set local request.jwt.claims to '';

select is((select count(*)::int from public.audit_log
            where property_id = '49100000-0000-4000-8000-00000000000c' and action = 'listing:submit'),
  1, 'one submit audit row');
select ok((select body from public.outbox
            where property_id = '49100000-0000-4000-8000-00000000000c'
              and template = 'listing_submitted')
          like 'Hi Chetan Owner, thank you for listing Listing C on ResortHub.%',
  'the email is rendered with the owner''s and the resort''s names');
select ok(not has_function_privilege('authenticated', 'public.listing_setup_flags(uuid)', 'execute'),
  'listing_setup_flags is internal');
select ok(not has_function_privilege('authenticated', 'public.enqueue_listing_message(uuid, text)', 'execute'),
  'enqueue_listing_message is internal');
```

- [ ] **Step 2: Run them to verify they fail**

Run: `supabase test db supabase/tests/49_resort_self_listing_test.sql`
Expected: FAIL — test 54 dies with `0A000 listing_setup_status is not implemented yet`.

- [ ] **Step 3: Implement the checklist, the templates and submitting**

Append to `supabase/migrations/0059_resort_self_listing.sql`, directly above the `revoke execute on function public.apply_for_listing` line:

```sql
-- ---------------------------------------------------------------------
-- Internal: the six checklist items (spec decision 10), computed on every
-- read and never stored. A plain function, called only from the definers
-- in this file.
create function public.listing_setup_flags(p_property uuid)
returns table(
  has_photos              boolean,
  has_unit                boolean,
  has_rates               boolean,
  has_payment_settings    boolean,
  has_cancellation_policy boolean,
  has_tax_details         boolean
)
language sql
stable
set search_path = public, pg_temp
as $$
  select
    cardinality(p.images) > 0,
    exists (select 1 from public.units u where u.property_id = p.id and u.is_active),
    exists (select 1 from public.units u where u.property_id = p.id and u.is_active)
      and not exists (
        select 1 from public.units u
         where u.property_id = p.id and u.is_active
           and not exists (select 1 from public.rate_rules r
                            where r.unit_id = u.id and r.kind in ('base','weekend'))),
    cardinality(p.payment_display_methods) > 0,
    exists (select 1 from public.refund_rules rr where rr.property_id = p.id),
    coalesce(upper(btrim(p.gstin)) ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$', false)
  from public.properties p
  where p.id = p_property;
$$;

revoke execute on function public.listing_setup_flags(uuid) from public, anon, authenticated;

-- Internal: queues one platform-to-owner listing message (spec decision
-- 16). The recipient is the applicant's sign-in email (or phone for a
-- non-email template); the resort's guest-notification toggles do not
-- apply. Silently does nothing without a platform template of that name.
create function public.enqueue_listing_message(p_property uuid, p_template text)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_tpl       public.outbox_templates;
  v_app       public.listing_applications;
  v_property  public.properties;
  v_profile   public.profiles;
  v_email     text;
  v_trial     date;
  v_recipient text;
  v_ctx       jsonb;
  v_subject   text;
  v_body      text;
  v_key       text;
begin
  select * into v_tpl from public.outbox_templates
   where name = p_template and property_id is null;
  if not found then
    return;
  end if;

  select * into v_app from public.listing_applications where property_id = p_property;
  if not found then
    return;
  end if;

  select * into v_property from public.properties where id = p_property;
  select * into v_profile from public.profiles where id = v_app.applicant_id;
  select email into v_email from auth.users where id = v_app.applicant_id;
  select trial_ends_on into v_trial from public.resort_subscriptions where property_id = p_property;

  v_recipient := case v_tpl.channel
    when 'email' then nullif(btrim(coalesce(v_email, '')), '')
    else nullif(btrim(coalesce(v_profile.phone, '')), '')
  end;

  if v_recipient is null then
    insert into public.outbox (property_id, channel, recipient, template, status, last_error)
    values (p_property, v_tpl.channel,
            case v_tpl.channel when 'email' then 'no email on file' else 'no phone on file' end,
            p_template, 'skipped',
            format('cannot deliver via %s: applicant %s has no %s on file',
                   v_tpl.channel, v_app.applicant_id,
                   case v_tpl.channel when 'email' then 'email address' else 'phone number' end));
    return;
  end if;

  -- Every value is coalesced: replace() returns NULL if any argument is
  -- NULL, which would blank the whole message (see 0017).
  v_ctx := jsonb_build_object(
    'owner_name',    coalesce(nullif(btrim(v_profile.full_name), ''), 'there'),
    'property_name', coalesce(v_property.name, 'your resort'),
    'trial_ends_on', coalesce(to_char(v_trial, 'DD Mon YYYY'), ''),
    'reason',        coalesce(v_app.rejection_reason, ''));

  v_subject := v_tpl.subject_template;
  v_body    := v_tpl.body_template;
  for v_key in select jsonb_object_keys(v_ctx) loop
    if v_subject is not null then
      v_subject := replace(v_subject, '{{' || v_key || '}}', v_ctx ->> v_key);
    end if;
    v_body := replace(v_body, '{{' || v_key || '}}', v_ctx ->> v_key);
  end loop;

  insert into public.outbox (property_id, channel, recipient, template, subject, body, status)
  values (p_property, v_tpl.channel, v_recipient, p_template, v_subject, v_body, 'pending');
end;
$$;

revoke execute on function public.enqueue_listing_message(uuid, text) from public, anon, authenticated;

-- Platform default templates (property_id null) for the three listing
-- events. Email only; P7's dispatcher delivers them.
insert into public.outbox_templates (name, event, channel, subject_template, body_template, property_id)
values
  ('listing_submitted', 'listing_submitted', 'email',
   'We are reviewing {{property_name}}',
   'Hi {{owner_name}}, thank you for listing {{property_name}} on ResortHub. '
   'Our team is reviewing it and will email you when it is decided. You can '
   'keep editing your setup in the meantime.',
   null),
  ('listing_approved', 'listing_approved', 'email',
   '{{property_name}} is live on ResortHub',
   'Hi {{owner_name}}, {{property_name}} has been approved. Guests can now '
   'find and book it. Your free trial runs until {{trial_ends_on}}.',
   null),
  ('listing_rejected', 'listing_rejected', 'email',
   'About your ResortHub listing for {{property_name}}',
   'Hi {{owner_name}}, we could not approve {{property_name}} for listing. '
   'Reason: {{reason}}. You can apply again from the ResortHub app.',
   null)
on conflict (name) do nothing;

-- The checklist of one resort, for its owners and admins (a read, so it
-- also answers at a suspended resort).
create or replace function public.listing_setup_status(p_property uuid)
returns table(
  property_status         text,
  submitted_at            timestamptz,
  has_photos              boolean,
  has_unit                boolean,
  has_rates               boolean,
  has_payment_settings    boolean,
  has_cancellation_policy boolean,
  has_tax_details         boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_resort_role(p_property, false, 'owner','admin');

  return query
    select p.status, a.submitted_at, f.has_photos, f.has_unit, f.has_rates,
           f.has_payment_settings, f.has_cancellation_policy, f.has_tax_details
      from public.properties p
      left join public.listing_applications a on a.property_id = p.id
      cross join lateral public.listing_setup_flags(p.id) f
     where p.id = p_property;
end;
$$;

-- The owner submits a complete checklist (spec decision 11). Submitting
-- again is a no-op; anything but an undecided application of a pending
-- resort is P0040.
create or replace function public.submit_listing_for_review(p_property uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_app    public.listing_applications;
  v_status text;
  v_flags  record;
begin
  perform public.assert_resort_role(p_property, true, 'owner');

  select * into v_app from public.listing_applications
   where property_id = p_property
   for update;
  select status into v_status from public.properties where id = p_property;
  if v_app.property_id is null or v_app.decision is not null or v_status <> 'pending' then
    raise exception 'This resort is not waiting for review.' using errcode = 'P0040';
  end if;

  if v_app.submitted_at is not null then
    return;
  end if;

  select * into v_flags from public.listing_setup_flags(p_property);
  if not (v_flags.has_photos and v_flags.has_unit and v_flags.has_rates
          and v_flags.has_payment_settings and v_flags.has_cancellation_policy
          and v_flags.has_tax_details) then
    raise exception 'Finish the setup checklist before submitting.' using errcode = 'P0040';
  end if;

  update public.listing_applications
     set submitted_at = now()
   where property_id = p_property;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values (auth.uid(), 'listing', p_property, 'listing:submit', null,
          jsonb_build_object('submitted_at', now()), p_property);

  perform public.enqueue_listing_message(p_property, 'listing_submitted');
end;
$$;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db supabase/tests/49_resort_self_listing_test.sql supabase/tests/13_outbox_test.sql supabase/tests/37_tenancy_isolation_test.sql`
Expected: PASS — 49 at 79/79, 13 and 37 at their baseline counts (37's "every policy checks the resort" and "every outbox row has a resort" guards still hold: listing rows carry `property_id`).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0059_resort_self_listing.sql supabase/tests/49_resort_self_listing_test.sql
git commit -m "feat(db): listing setup checklist, submit for review, listing emails

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Reviewing, approving and rejecting

**Track:** DB. **Depends on:** Task 3.

**Files:**
- Modify: `supabase/migrations/0059_resort_self_listing.sql`
- Modify: `supabase/tests/49_resort_self_listing_test.sql`

**Interfaces:**
- Consumes: `listing_setup_flags`, `enqueue_listing_message` (Task 3); `properties_guard_status` (0044), which lets the platform admin change `status`.
- Produces: real bodies of `platform_listing_applications()`, `approve_listing(uuid)` and `reject_listing(uuid, text)`.

- [ ] **Step 1: Write the failing tests**

In `supabase/tests/49_resort_self_listing_test.sql`, change `select plan(79);` to `select plan(109);`, and insert this section directly above `select * from finish();`:

```sql
-- === Task 4: review and decisions ==========================================

-- Undecided now: C (submitted, complete), A's Green Acres and B's Green
-- Acres (both still being set up).
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok($$select * from public.platform_listing_applications()$$,
  'P0008', null, 'an owner cannot list applications');
select throws_ok($$select public.approve_listing('49100000-0000-4000-8000-00000000000c')$$,
  'P0008', null, 'an owner cannot approve their own resort');

set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.platform_listing_applications()), 3,
  'three undecided applications');
select is((select name from public.platform_listing_applications() limit 1), 'Listing C',
  'submitted applications come first');
select is((select concat_ws('|', applicant_email, coalesce(applicant_name, ''), tier::text, city,
                            contact_phone, has_photos::text, has_unit::text, has_rates::text,
                            has_payment_settings::text, has_cancellation_policy::text,
                            has_tax_details::text)
             from public.platform_listing_applications()
            where property_id = '49100000-0000-4000-8000-00000000000c'),
  'list-owner-c@example.com|Chetan Owner|pro|Pune|+919876543210|true|true|true|true|true|true',
  'the console sees the applicant, the contact details and the checklist');
select throws_ok(format('select public.approve_listing(%L)', current_setting('app.list_a')),
  'P0040', 'This resort has not been submitted for review yet.',
  'an application still being set up cannot be approved');
select throws_ok($$select public.approve_listing('49100000-0000-4000-8000-0000000000ff')$$,
  'P0002', null, 'an unknown application');

-- The owner removes the photo after submitting: approval re-checks.
reset role;
set local request.jwt.claims to '';
update public.properties set images = '{}' where id = '49100000-0000-4000-8000-00000000000c';
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok($$select public.approve_listing('49100000-0000-4000-8000-00000000000c')$$,
  'P0040', 'The setup checklist is no longer complete.',
  'a resort that lost a checklist item is not approved');
reset role;
set local request.jwt.claims to '';
update public.properties set images = array['https://example.com/c1.jpg']
  where id = '49100000-0000-4000-8000-00000000000c';
set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok($$select public.approve_listing('49100000-0000-4000-8000-00000000000c')$$,
  'the platform admin approves Listing C');
select throws_ok($$select public.approve_listing('49100000-0000-4000-8000-00000000000c')$$,
  'P0040', 'This application has already been decided.', 'a decision is final');
reset role;
set local request.jwt.claims to '';

select is((select status from public.properties where id = '49100000-0000-4000-8000-00000000000c'),
  'active', 'Listing C is live');
select is((select concat_ws('|', decision, decided_by::text) from public.listing_applications
            where property_id = '49100000-0000-4000-8000-00000000000c'),
  'approved|49000000-0000-0000-0000-000000000001', 'the decision and who made it are stored');
select is((select trial_ends_on - pg_temp.today() from public.resort_subscriptions
            where property_id = '49100000-0000-4000-8000-00000000000c'),
  30, 'approval restarts the 30-day trial');
select is((select array_agg(action order by action) from public.audit_log
            where property_id = '49100000-0000-4000-8000-00000000000c'
              and action in ('status:pending->active','listing:approve','subscription:trial-restart')),
  array['listing:approve','status:pending->active','subscription:trial-restart'],
  'approval is audited');
select is((select concat_ws('|', recipient, status::text) from public.outbox
            where property_id = '49100000-0000-4000-8000-00000000000c'
              and template = 'listing_approved'),
  'list-owner-c@example.com|pending', 'the owner is told the resort is live');
select ok((select body from public.outbox
            where property_id = '49100000-0000-4000-8000-00000000000c'
              and template = 'listing_approved')
          like ('%runs until ' || to_char(pg_temp.today() + 30, 'DD Mon YYYY') || '.'),
  'the approval email carries the restarted trial''s end');
set local role anon;
select is((select count(*)::int from public.properties
            where id = '49100000-0000-4000-8000-00000000000c'), 1,
  'guests can now see Listing C');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select is((select count(*)::int from public.platform_listing_applications()), 2,
  'Listing C has left the queue');
select throws_ok(format('select public.reject_listing(%L, %L)', current_setting('app.list_b'), '  no '),
  'P0005', 'Give the owner a reason (5 to 500 characters).', 'a rejection needs a reason');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000005","role":"authenticated"}';
select throws_ok(format('select public.reject_listing(%L, %L)', current_setting('app.list_b'),
                        'Photos do not match.'),
  'P0008', null, 'only the platform admin rejects');
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000001","role":"authenticated"}';
select lives_ok(format('select public.reject_listing(%L, %L)', current_setting('app.list_b'),
                       'Photos do not match the address.'),
  'the platform admin rejects B''s resort');
select throws_ok($$select public.reject_listing('49100000-0000-4000-8000-00000000000c', 'Too late to change.')$$,
  'P0040', 'This application has already been decided.', 'an approved resort cannot be rejected');
select is((select concat_ws('|', subscribed_count, active_count, trial_count, mrr_inr::int)
             from public.platform_summary()),
  '2|2|1|2999', 'the approved trial now counts; the rejected and the pending ones do not');
reset role;
set local request.jwt.claims to '';

select is((select status from public.properties where id = current_setting('app.list_b')::uuid),
  'archived', 'a rejected resort is archived');
select is((select array_agg(action order by action) from public.audit_log
            where property_id = current_setting('app.list_b')::uuid
              and action in ('status:pending->archived','listing:reject')),
  array['listing:reject','status:pending->archived'], 'rejection is audited');
select ok((select body from public.outbox
            where property_id = current_setting('app.list_b')::uuid
              and template = 'listing_rejected')
          like '%Reason: Photos do not match the address.%',
  'the rejection email carries the reason');

set local role authenticated;
set local request.jwt.claims to '{"sub":"49000000-0000-0000-0000-000000000003","role":"authenticated"}';
select is((select concat_ws('|', property_status, decision, rejection_reason)
             from public.my_listing_applications()),
  'archived|rejected|Photos do not match the address.',
  'B still sees the decision and the reason');
select ok(not public.has_resort_role(current_setting('app.list_b')::uuid, false, 'owner'),
  'B keeps no access to the archived resort');
select ok(set_config('app.list_b2',
    public.apply_for_listing('Green Acres Lakeside', 'Lonavala', '5 Lake Road, Lonavala',
      '9876501234', 'Lakeside tents and a big lawn, now with photos.')::text,
    true) is not null,
  'B can apply again after a rejection');
select is((select count(*)::int from public.my_listing_applications()), 2,
  'B now has the old and the new application');
reset role;
set local request.jwt.claims to '';
```

- [ ] **Step 2: Run them to verify they fail**

Run: `supabase test db supabase/tests/49_resort_self_listing_test.sql`
Expected: FAIL — test 80 ("an owner cannot list applications") gets `0A000` instead of `P0008`, and the approve/reject assertions die with `not implemented yet`.

- [ ] **Step 3: Implement the review functions**

Append to `supabase/migrations/0059_resort_self_listing.sql`, directly above the `revoke execute on function public.apply_for_listing` line:

```sql
-- ---------------------------------------------------------------------
-- The console's queue (spec decision 25): undecided applications, the
-- submitted ones first (oldest submission first), then the rest by when
-- they applied. Platform admin only; no guest data.
create or replace function public.platform_listing_applications()
returns table(
  property_id             uuid,
  name                    text,
  city                    text,
  address                 text,
  contact_phone           text,
  description             text,
  applicant_email         text,
  applicant_name          text,
  tier                    public.subscription_tier,
  created_at              timestamptz,
  submitted_at            timestamptz,
  has_photos              boolean,
  has_unit                boolean,
  has_rates               boolean,
  has_payment_settings    boolean,
  has_cancellation_policy boolean,
  has_tax_details         boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  return query
    select a.property_id, p.name, p.city, p.address, p.contact_phone, p.description,
           u.email::text, pr.full_name, a.tier, a.created_at, a.submitted_at,
           f.has_photos, f.has_unit, f.has_rates, f.has_payment_settings,
           f.has_cancellation_policy, f.has_tax_details
      from public.listing_applications a
      join public.properties p on p.id = a.property_id
      left join auth.users u on u.id = a.applicant_id
      left join public.profiles pr on pr.id = a.applicant_id
      cross join lateral public.listing_setup_flags(a.property_id) f
     where a.decision is null
     order by a.submitted_at nulls last, a.created_at, p.name, a.property_id;
end;
$$;

-- Approve (spec decisions 4, 9, 12): only a submitted application whose
-- checklist is still complete. The resort goes live, a trial restarts
-- from today, and the owner is told.
create or replace function public.approve_listing(p_property uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_app   public.listing_applications;
  v_old   public.resort_subscriptions;
  v_new   public.resort_subscriptions;
  v_flags record;
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  select * into v_app from public.listing_applications
   where property_id = p_property
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;
  perform 1 from public.properties where id = p_property for update;

  if v_app.decision is not null then
    raise exception 'This application has already been decided.' using errcode = 'P0040';
  end if;
  if v_app.submitted_at is null then
    raise exception 'This resort has not been submitted for review yet.' using errcode = 'P0040';
  end if;

  select * into v_flags from public.listing_setup_flags(p_property);
  if not (v_flags.has_photos and v_flags.has_unit and v_flags.has_rates
          and v_flags.has_payment_settings and v_flags.has_cancellation_policy
          and v_flags.has_tax_details) then
    raise exception 'The setup checklist is no longer complete.' using errcode = 'P0040';
  end if;

  update public.properties set status = 'active' where id = p_property;
  update public.listing_applications
     set decision = 'approved', decided_at = now(), decided_by = auth.uid()
   where property_id = p_property;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values
    (auth.uid(), 'property', p_property, 'status:pending->active',
     jsonb_build_object('status', 'pending'), jsonb_build_object('status', 'active'), p_property),
    (auth.uid(), 'listing', p_property, 'listing:approve', null,
     jsonb_build_object('decision', 'approved'), p_property);

  -- Review time does not eat the trial.
  select * into v_old from public.resort_subscriptions
   where property_id = p_property
   for update;
  if v_old.status = 'trial' then
    update public.resort_subscriptions
       set trial_ends_on = (now() at time zone 'Asia/Kolkata')::date + 30,
           updated_at = now(),
           updated_by = auth.uid()
     where property_id = p_property
    returning * into v_new;

    insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
    values (auth.uid(), 'subscription', p_property, 'subscription:trial-restart',
            to_jsonb(v_old), to_jsonb(v_new), p_property);
  end if;

  perform public.enqueue_listing_message(p_property, 'listing_approved');
end;
$$;

-- Reject with a reason (spec decisions 4, 12, 15): any time before a
-- decision. The resort is archived; the applicant sees the reason through
-- my_listing_applications and the email.
create or replace function public.reject_listing(p_property uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reason text := btrim(coalesce(p_reason, ''));
  v_app    public.listing_applications;
begin
  if not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if length(v_reason) not between 5 and 500 then
    raise exception 'Give the owner a reason (5 to 500 characters).' using errcode = 'P0005';
  end if;

  select * into v_app from public.listing_applications
   where property_id = p_property
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;
  perform 1 from public.properties where id = p_property for update;

  if v_app.decision is not null then
    raise exception 'This application has already been decided.' using errcode = 'P0040';
  end if;

  update public.properties set status = 'archived' where id = p_property;
  update public.listing_applications
     set decision = 'rejected', decided_at = now(), decided_by = auth.uid(),
         rejection_reason = v_reason
   where property_id = p_property;

  insert into public.audit_log (actor_id, entity, entity_id, action, before, after, property_id)
  values
    (auth.uid(), 'property', p_property, 'status:pending->archived',
     jsonb_build_object('status', 'pending'), jsonb_build_object('status', 'archived'), p_property),
    (auth.uid(), 'listing', p_property, 'listing:reject', null,
     jsonb_build_object('decision', 'rejected', 'reason', v_reason), p_property);

  perform public.enqueue_listing_message(p_property, 'listing_rejected');
end;
$$;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db`
Expected: 49 at 109/109; every other file as in the Task 1 Step 1 baseline (37 passes with the seven allow-list names; 41 and 38 unchanged).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0059_resort_self_listing.sql supabase/tests/49_resort_self_listing_test.sql
git commit -m "feat(db): platform review queue, approve and reject listings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
## Phase 2: App track (after Task 1; 5, 6 and 8 in parallel, 7 after 6)

### Task 5: "List your resort": entry points, sign-in hand-off and the application screen

**Track:** App. **Depends on:** Task 1. Can run alongside Tasks 6 and 8.

**Files:**
- Create: `lib/features/listing/list_your_resort_screen.dart`
- Modify: `lib/core/router.dart` (imports; `postSignInPath`; `redirectFor`; the `/login`, `/signup` and new `/list-your-resort` routes; the `redirect` closure)
- Modify: `lib/features/auth/welcome_screen.dart`, `lib/features/auth/login_screen.dart`, `lib/features/auth/signup_screen.dart`
- Modify: `lib/features/shell/app_shell.dart` (`showAccountSheet`)
- Modify: `lib/data/repositories/catalog_repository.dart` (`properties()`)
- Test: `test/features/listing/list_your_resort_screen_test.dart` (create), `test/core/router_test.dart`, `test/features/auth/welcome_screen_test.dart`, `test/features/auth/login_screen_test.dart`, `test/features/auth/signup_screen_test.dart`, `test/features/shell/app_shell_test.dart`

**Interfaces:**
- Consumes: `ListingSource`, `listingSourceProvider`, `myListingApplicationsProvider`, `ListingInput`, `ListingApplication`, the validators, `ListingBlocked` (Task 1); `subscriptionPlansProvider`, `SubscriptionPlan` (`platform_repository.dart`, `subscription.dart`); `currentUserProvider`, `currentResortProvider` and `CurrentResort.select`; `formatInr`.
- Produces:
  - `const postSignInPaths = {'/list-your-resort'}` and `String? postSignInPath(Uri uri)` in `router.dart`.
  - `redirectFor({required AppUser? user, required ResortMembership? resort, required String path, required bool onPreAuthScreen, String? next})`.
  - `LoginScreen({Key? key, String? next})`, `SignupScreen({Key? key, String? next})`.
  - `ListYourResortScreen`, `ListingForm`, `Future<void> openListedResort(BuildContext context, String propertyId)`.
  - Widget keys: `welcome-list-resort`, `account-sheet-list-resort`, `listing-name`, `listing-city`, `listing-address`, `listing-phone`, `listing-description`, `listing-tier`, `listing-submit`, `listing-open`, `listing-continue`, `listing-history-<propertyId>`.

- [ ] **Step 1: Write the failing router tests**

In `test/core/router_test.dart`, directly before the `group('finance', () {` line, add:

```dart
  group('list your resort', () {
    const platformAdmin = AppUser(
        id: 'p', email: 'e', platformRole: PlatformRole.platformAdmin);

    test('a signed-out visit goes to sign-in and comes back afterwards', () {
      expect(_to(null, null, '/list-your-resort'),
          '/login?next=%2Flist-your-resort');
    });

    test('any signed-in user but the platform admin opens it', () {
      expect(_to(_customer, null, '/list-your-resort'), null);
      expect(_to(_superAdmin, _ownerM, '/list-your-resort'), null);
      expect(_to(_staff, _staffM, '/list-your-resort'), null);
      expect(_to(platformAdmin, null, '/list-your-resort'), '/404');
    });

    test('after sign-in an allowed next wins over the landing page', () {
      expect(
          redirectFor(
              user: _customer,
              resort: null,
              path: '/login',
              onPreAuthScreen: true,
              next: '/list-your-resort'),
          '/list-your-resort');
      expect(
          redirectFor(
              user: _superAdmin,
              resort: _ownerM,
              path: '/signup',
              onPreAuthScreen: true,
              next: '/list-your-resort'),
          '/list-your-resort');
    });

    test('a next outside the allow-list, or for the platform admin, is ignored',
        () {
      expect(
          redirectFor(
              user: _customer,
              resort: null,
              path: '/login',
              onPreAuthScreen: true,
              next: '/admin'),
          '/');
      expect(
          redirectFor(
              user: _customer,
              resort: null,
              path: '/login',
              onPreAuthScreen: true,
              next: 'https://evil.example/list-your-resort'),
          '/');
      expect(
          redirectFor(
              user: platformAdmin,
              resort: null,
              path: '/login',
              onPreAuthScreen: true,
              next: '/list-your-resort'),
          '/platform');
    });

    test('postSignInPath reads only allowed next values', () {
      expect(postSignInPath(Uri.parse('/login?next=%2Flist-your-resort')),
          '/list-your-resort');
      expect(postSignInPath(Uri.parse('/login?next=%2Fadmin')), isNull);
      expect(postSignInPath(Uri.parse('/login')), isNull);
    });

    test('the app router registers /list-your-resort', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(null)),
        currentResortProvider.overrideWith(_NoResort.new),
      ]);
      addTearDown(container.dispose);

      final router = container.read(routerProvider);

      expect(_paths(router.configuration.routes), contains('/list-your-resort'));
    });
  });

```

- [ ] **Step 2: Write the failing entry-point tests**

In `test/features/auth/welcome_screen_test.dart`, change the `/signup` route in `appFor()` from

```dart
        GoRoute(path: '/signup', builder: (_, _) => const Text('Signup screen')),
```

to

```dart
        GoRoute(
          path: '/signup',
          builder: (_, state) => Text(
            state.uri.queryParameters['next'] == null
                ? 'Signup screen'
                : 'Signup screen next=${state.uri.queryParameters['next']}',
          ),
        ),
```

and add this test after `'Sign Up navigates to /signup'`:

```dart
  testWidgets('List your resort opens sign-up and asks to come back', (
    tester,
  ) async {
    await tester.pumpWidget(appFor());

    await tester.tap(find.byKey(const Key('welcome-list-resort')));
    await tester.pumpAndSettle();

    expect(find.text('Signup screen next=/list-your-resort'), findsOneWidget);
  });
```

Replace `test/features/auth/login_screen_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/router.dart';
import 'package:pasala/core/widgets/brand_mark.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/features/auth/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signs anyone in as a customer with no memberships.
class _FakeAuth implements AuthRepository {
  @override
  Future<AppUser> signIn(String email, String password) async =>
      const AppUser(id: 'u1', email: 'asha@example.com');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _routed(String location) {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, state) => LoginScreen(next: postSignInPath(state.uri)),
      ),
      GoRoute(
        path: '/signup',
        builder: (_, state) =>
            Text('Signup next=${state.uri.queryParameters['next']}'),
      ),
      GoRoute(
        path: '/list-your-resort',
        builder: (_, _) => const Text('List page'),
      ),
      GoRoute(path: '/', builder: (_, _) => const Text('Browse')),
    ],
  );
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(_FakeAuth())],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows email, password, and a sign-in button', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.byKey(const Key('login-email')), findsOneWidget);
    expect(find.byKey(const Key('login-password')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('rejects an empty email', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Enter your email'), findsOneWidget);
  });

  testWidgets('shows the ResortHub name, not the Pasala logo or name',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('ResortHub'), findsOneWidget);
    expect(find.text('Pasala Resorts'), findsNothing);
    expect(find.byType(BrandMark), findsNothing);
  });

  testWidgets('after signing in, goes on to an allowed next page',
      (tester) async {
    await tester.pumpWidget(_routed('/login?next=%2Flist-your-resort'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('login-email')), 'asha@example.com');
    await tester.enterText(
        find.byKey(const Key('login-password')), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('List page'), findsOneWidget);
  });

  testWidgets('without next, signing in lands where the role lands',
      (tester) async {
    await tester.pumpWidget(_routed('/login'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('login-email')), 'asha@example.com');
    await tester.enterText(
        find.byKey(const Key('login-password')), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Browse'), findsOneWidget);
  });

  testWidgets('Create an account keeps next', (tester) async {
    await tester.pumpWidget(_routed('/login?next=%2Flist-your-resort'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create an account'));
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Signup next=/list-your-resort'), findsOneWidget);
  });
}
```

In `test/features/auth/signup_screen_test.dart`, add these imports if missing:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/router.dart';
```

and add this test at the end of `main`:

```dart
  testWidgets('Already have an account keeps next', (tester) async {
    final router = GoRouter(
      initialLocation: '/signup?next=%2Flist-your-resort',
      routes: [
        GoRoute(
          path: '/signup',
          builder: (_, state) => SignupScreen(next: postSignInPath(state.uri)),
        ),
        GoRoute(
          path: '/login',
          builder: (_, state) =>
              Text('Login next=${state.uri.queryParameters['next']}'),
        ),
      ],
    );
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Already have an account? Sign in'));
    await tester.tap(find.text('Already have an account? Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Login next=/list-your-resort'), findsOneWidget);
  });
```

In `test/features/shell/app_shell_test.dart`, add a route to `_appFor`'s shell routes, after the `/finance` route:

```dart
          GoRoute(
              path: '/list-your-resort',
              builder: (_, _) => const Text('List page')),
```

and add this test at the end of `main`:

```dart
  testWidgets("the customer's account sheet offers List your resort", (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(_customer));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();
    expect(find.text('Apply to list a resort on ResortHub'), findsOneWidget);

    await tester.tap(find.byKey(const Key('account-sheet-list-resort')));
    await tester.pumpAndSettle();

    expect(find.text('List page'), findsOneWidget);
  });
```

- [ ] **Step 3: Write the failing screen tests**

Create `test/features/listing/list_your_resort_screen_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/listing.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/listing_repository.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/features/listing/list_your_resort_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_listing_source.dart';
import '../../support/fake_platform_source.dart';

class _NoResort extends CurrentResort {
  @override
  ResortMembership? build() => null;
}

const _customer = AppUser(id: 'c1', email: 'asha@example.com');

Future<void> _pump(
  WidgetTester tester,
  FakeListingSource source, {
  Object? plansError,
}) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/list-your-resort',
    routes: [
      GoRoute(
        path: '/list-your-resort',
        builder: (_, _) => const ListYourResortScreen(),
      ),
      GoRoute(path: '/owner', builder: (_, _) => const Text('Owner hub')),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      listingSourceProvider.overrideWithValue(source),
      subscriptionPlansProvider.overrideWith((ref) async {
        if (plansError != null) throw plansError;
        return defaultPlans;
      }),
      currentUserProvider.overrideWith((ref) => Stream.value(_customer)),
      currentResortProvider.overrideWith(_NoResort.new),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('listing-name')), ' Green Acres ');
  await tester.enterText(find.byKey(const Key('listing-city')), 'Nashik');
  await tester.enterText(
      find.byKey(const Key('listing-address')), '12 Vineyard Road, Nashik');
  await tester.enterText(
      find.byKey(const Key('listing-phone')), '+91 98765 43210');
  await tester.enterText(find.byKey(const Key('listing-description')),
      'Vineyard cottages with a pool and a view.');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('with no application it shows the form and the plan price',
      (tester) async {
    await _pump(tester, FakeListingSource());

    expect(find.text('Resort name'), findsOneWidget);
    expect(find.text('Contact phone'), findsOneWidget);
    expect(find.text('Starter — ₹2,999/month'), findsOneWidget);
    expect(find.text('30-day free trial. No payment needed now.'),
        findsOneWidget);
    expect(find.text('Earlier applications'), findsNothing);
  });

  testWidgets('if the prices fail to load, the plan still shows its name',
      (tester) async {
    await _pump(tester, FakeListingSource(), plansError: const NetworkFailure());

    expect(find.text('Starter'), findsOneWidget);
  });

  testWidgets('an empty form shows every rule and sends nothing',
      (tester) async {
    final source = FakeListingSource();
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('listing-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Enter the resort name (2 to 80 characters).'),
        findsOneWidget);
    expect(find.text('Enter the city (2 to 60 characters).'), findsOneWidget);
    expect(find.text('Enter the full address (5 to 300 characters).'),
        findsOneWidget);
    expect(find.text('Enter a contact phone number, e.g. +91 98765 43210.'),
        findsOneWidget);
    expect(find.text('Describe the resort in 20 to 500 characters.'),
        findsOneWidget);
    expect(source.applyCalls, isEmpty);
  });

  testWidgets('a valid form applies with the chosen plan and opens the owner hub',
      (tester) async {
    final source = FakeListingSource();
    await _pump(tester, source);

    await _fillValidForm(tester);
    await tester.tap(find.byKey(const Key('listing-tier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pro — ₹7,999/month').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('listing-submit')));
    await tester.pumpAndSettle();

    final input = source.applyCalls.single;
    expect(input.name, ' Green Acres ');
    expect(input.contactPhone, '+91 98765 43210');
    expect(input.tier, SubscriptionTier.pro);
    expect(find.text('Owner hub'), findsOneWidget);
  });

  testWidgets('a double tap sends one application', (tester) async {
    final source = FakeListingSource()..applyGate = Completer<void>();
    await _pump(tester, source);

    await _fillValidForm(tester);
    await tester.tap(find.byKey(const Key('listing-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('listing-submit')));
    await tester.pump();

    expect(source.applyCalls, hasLength(1));
    source.applyGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Owner hub'), findsOneWidget);
  });

  testWidgets('a refusal from the server is shown as written', (tester) async {
    final source = FakeListingSource()
      ..applyError =
          const ListingBlocked('You already have a resort waiting for review.');
    await _pump(tester, source);

    await _fillValidForm(tester);
    await tester.tap(find.byKey(const Key('listing-submit')));
    await tester.pumpAndSettle();

    expect(find.text('You already have a resort waiting for review.'),
        findsOneWidget);
    expect(find.byKey(const Key('listing-name')), findsOneWidget);
  });

  testWidgets('an open application replaces the form with Continue setup',
      (tester) async {
    final source = FakeListingSource()
      ..applications = [
        listingApplication(submittedAt: DateTime.utc(2026, 9, 20, 12)),
      ];
    await _pump(tester, source);

    expect(find.byKey(const Key('listing-open')), findsOneWidget);
    expect(find.text('Waiting for review since 20 Sep 2026'), findsOneWidget);
    expect(find.byKey(const Key('listing-name')), findsNothing);

    await tester.tap(find.byKey(const Key('listing-continue')));
    await tester.pumpAndSettle();

    expect(find.text('Owner hub'), findsOneWidget);
  });

  testWidgets('a rejected application shows its reason above a fresh form',
      (tester) async {
    final source = FakeListingSource()
      ..applications = [
        listingApplication(
          propertyId: 'old',
          propertyStatus: 'archived',
          decision: ListingDecision.rejected,
          rejectionReason: 'Photos do not match the address.',
        ),
      ];
    await _pump(tester, source);

    expect(find.text('Earlier applications'), findsOneWidget);
    expect(find.text('Not approved: Photos do not match the address.'),
        findsOneWidget);
    expect(find.byKey(const Key('listing-name')), findsOneWidget);
  });

  testWidgets('a failed load offers Retry', (tester) async {
    final source = FakeListingSource()..applicationsError = const NetworkFailure();
    await _pump(tester, source);

    expect(find.text('Cannot reach the server. Check your connection.'),
        findsOneWidget);
    source.applicationsError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('listing-name')), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run them to verify they fail**

Run: `flutter test test/core/router_test.dart test/features/auth test/features/shell/app_shell_test.dart test/features/listing`
Expected: FAIL to compile — `postSignInPath`, `redirectFor`'s `next`, `LoginScreen(next:)`, `SignupScreen(next:)` and `list_your_resort_screen.dart` do not exist.

- [ ] **Step 5: Write the screen**

Create `lib/features/listing/list_your_resort_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/listing.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/listing_repository.dart';
import '../../data/repositories/platform_repository.dart';

/// Makes [propertyId] -- a resort the user has just applied for, or is
/// still setting up -- the current resort and opens `/owner`, where the
/// setup checklist is. The user is refetched first, because the owner
/// membership was created on the server a moment ago.
///
/// Uses the router and the container captured up front, not the calling
/// widget: selecting the resort rebuilds the shell's navigator, which can
/// dispose that widget before the navigation.
Future<void> openListedResort(BuildContext context, String propertyId) async {
  final router = GoRouter.of(context);
  final container = ProviderScope.containerOf(context);
  container.invalidate(currentUserProvider);
  await container.read(currentUserProvider.future);
  await container.read(currentResortProvider.notifier).select(propertyId);
  router.go('/owner');
}

/// `/list-your-resort` (P10): a signed-in user applies to list a resort.
/// With an open application (one per user) it shows that application and
/// "Continue setup" instead of the form; decided applications are listed
/// below, a rejection with its reason.
class ListYourResortScreen extends ConsumerWidget {
  const ListYourResortScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applications = ref.watch(myListingApplicationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('List your resort')),
      body: AsyncView(
        value: applications,
        onRetry: () => ref.invalidate(myListingApplicationsProvider),
        data: (apps) {
          final open = apps.where((a) => a.isOpen);
          final earlier = apps.where((a) => !a.isOpen).toList();
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  if (open.isNotEmpty)
                    _OpenApplicationCard(application: open.first)
                  else
                    const ListingForm(),
                  if (earlier.isNotEmpty) ...[
                    const SizedBox(height: Spacing.lg),
                    Text('Earlier applications',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: Spacing.sm),
                    for (final a in earlier)
                      Card(
                        key: Key('listing-history-${a.propertyId}'),
                        child: ListTile(
                          title: Text(a.name),
                          subtitle: Text(a.statusLine),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OpenApplicationCard extends StatelessWidget {
  const _OpenApplicationCard({required this.application});

  final ListingApplication application;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      key: const Key('listing-open'),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(application.name, style: textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            Text('${application.city} · ${application.tier.label} plan'),
            const SizedBox(height: Spacing.xs),
            Text(application.statusLine,
                style: textTheme.bodyMedium?.copyWith(color: scheme.primary)),
            const SizedBox(height: Spacing.md),
            FilledButton(
              key: const Key('listing-continue'),
              onPressed: () =>
                  openListedResort(context, application.propertyId),
              child: const Text('Continue setup'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The application form. It checks the same rules as `apply_for_listing`
/// before sending, and disables Apply while the call runs, so a double
/// tap sends one application.
class ListingForm extends ConsumerStatefulWidget {
  const ListingForm({super.key});

  @override
  ConsumerState<ListingForm> createState() => _ListingFormState();
}

class _ListingFormState extends ConsumerState<ListingForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _description = TextEditingController();
  SubscriptionTier _tier = SubscriptionTier.starter;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _address.dispose();
    _phone.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final id = await ref.read(listingSourceProvider).apply(ListingInput(
            name: _name.text,
            city: _city.text,
            address: _address.text,
            contactPhone: _phone.text,
            description: _description.text,
            tier: _tier,
          ));
      if (!mounted) return;
      await openListedResort(context, id);
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
    final plans =
        ref.watch(subscriptionPlansProvider).value ?? const <SubscriptionPlan>[];
    final prices = {for (final p in plans) p.tier: p.monthlyPriceInr};
    String tierLabel(SubscriptionTier t) => prices[t] == null
        ? t.label
        : '${t.label} — ${formatInr(prices[t]!)}/month';

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tell us about your resort. It stays hidden from guests until '
            'ResortHub approves it.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: Spacing.md),
          TextFormField(
            key: const Key('listing-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Resort name'),
            textInputAction: TextInputAction.next,
            validator: validateListingName,
          ),
          const SizedBox(height: Spacing.sm),
          TextFormField(
            key: const Key('listing-city'),
            controller: _city,
            decoration: const InputDecoration(labelText: 'City'),
            textInputAction: TextInputAction.next,
            validator: validateListingCity,
          ),
          const SizedBox(height: Spacing.sm),
          TextFormField(
            key: const Key('listing-address'),
            controller: _address,
            decoration: const InputDecoration(labelText: 'Address'),
            minLines: 1,
            maxLines: 3,
            validator: validateListingAddress,
          ),
          const SizedBox(height: Spacing.sm),
          TextFormField(
            key: const Key('listing-phone'),
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Contact phone'),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            validator: validateListingPhone,
          ),
          const SizedBox(height: Spacing.sm),
          TextFormField(
            key: const Key('listing-description'),
            controller: _description,
            decoration: const InputDecoration(labelText: 'Short description'),
            minLines: 2,
            maxLines: 5,
            maxLength: 500,
            validator: validateListingDescription,
          ),
          const SizedBox(height: Spacing.sm),
          DropdownButtonFormField<SubscriptionTier>(
            key: const Key('listing-tier'),
            initialValue: _tier,
            decoration: const InputDecoration(labelText: 'Plan'),
            items: [
              for (final t in SubscriptionTier.values)
                DropdownMenuItem(value: t, child: Text(tierLabel(t))),
            ],
            onChanged: (t) => setState(() => _tier = t ?? _tier),
          ),
          const SizedBox(height: Spacing.xs),
          const Text('30-day free trial. No payment needed now.'),
          const SizedBox(height: Spacing.lg),
          FilledButton(
            key: const Key('listing-submit'),
            onPressed: _busy ? null : _submit,
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Wire the router**

In `lib/core/router.dart`:

1. Add the import next to the other feature imports (alphabetical order puts it after `../features/finance/...`):

```dart
import '../features/listing/list_your_resort_screen.dart';
```

2. Directly above the `redirectFor` doc comment (`/// Decides where `path` should redirect to, ...`), add:

```dart
/// Pages a pre-auth screen may hand the user on to after they sign in or
/// sign up, through `?next=`. An allow-list, so a crafted link can never
/// send someone to an arbitrary page.
const postSignInPaths = {'/list-your-resort'};

/// The `next` query parameter of [uri] when it is on [postSignInPaths],
/// otherwise null.
String? postSignInPath(Uri uri) {
  final next = uri.queryParameters['next'];
  return postSignInPaths.contains(next) ? next : null;
}

```

3. Change the start of `redirectFor` from

```dart
String? redirectFor({
  required AppUser? user,
  required ResortMembership? resort,
  required String path,
  required bool onPreAuthScreen,
}) {
  if (user == null) return onPreAuthScreen ? null : '/login';
  if (onPreAuthScreen) return landingPathFor(user, resort);

  if (path == '/platform') return user.isPlatformAdmin ? null : '/404';
```

to

```dart
String? redirectFor({
  required AppUser? user,
  required ResortMembership? resort,
  required String path,
  required bool onPreAuthScreen,
  String? next,
}) {
  if (user == null) {
    if (onPreAuthScreen) return null;
    // "List your resort" tapped while signed out: come back after sign-in.
    if (path == '/list-your-resort') return '/login?next=%2Flist-your-resort';
    return '/login';
  }
  if (onPreAuthScreen) {
    // A pre-auth screen opened with an allowed `?next=` hands the user on
    // there (the platform admin has no use for it).
    if (next != null &&
        postSignInPaths.contains(next) &&
        !user.isPlatformAdmin) {
      return next;
    }
    return landingPathFor(user, resort);
  }

  if (path == '/platform') return user.isPlatformAdmin ? null : '/404';
  // Anyone signed in may apply to list a resort, except the platform
  // admin, who adds resorts from the console.
  if (path == '/list-your-resort') return user.isPlatformAdmin ? '/404' : null;
```

4. In `routerProvider`'s `redirect` closure, change

```dart
    return redirectFor(
      user: auth.value,
      resort: ref.read(currentResortProvider),
      path: path,
      onPreAuthScreen: onPreAuthScreen,
    );
```

to

```dart
    return redirectFor(
      user: auth.value,
      resort: ref.read(currentResortProvider),
      path: path,
      onPreAuthScreen: onPreAuthScreen,
      next: state.uri.queryParameters['next'],
    );
```

5. Change the `/login` and `/signup` routes to pass `next`:

```dart
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) => fadeSlidePage(
          LoginScreen(next: postSignInPath(state.uri)),
          state,
        ),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (_, state) => fadeSlidePage(
          SignupScreen(next: postSignInPath(state.uri)),
          state,
        ),
      ),
```

6. Inside the `ShellRoute`'s `routes`, directly after the `/booking-detail/:id` route, add:

```dart
          GoRoute(
            path: '/list-your-resort',
            pageBuilder: (_, state) =>
                fadeSlidePage(const ListYourResortScreen(), state),
          ),
```

- [ ] **Step 7: Pass `next` through sign-in and sign-up**

In `lib/features/auth/login_screen.dart`:

```dart
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.next});

  /// Where to go after signing in instead of the role's landing page. The
  /// router passes only values on `postSignInPaths`.
  final String? next;
```

replaces the old constructor (`const LoginScreen({super.key});`). In `_submit`, replace

```dart
      if (mounted) context.go(landingPathFor(user, resort));
```

with

```dart
      final next = widget.next;
      if (mounted) {
        context.go(next != null && !user.isPlatformAdmin
            ? next
            : landingPathFor(user, resort));
      }
```

and replace the sign-up link's `onPressed: () => context.go('/signup'),` with

```dart
                            onPressed: () => context.go(widget.next == null
                                ? '/signup'
                                : '/signup?next=${Uri.encodeQueryComponent(widget.next!)}'),
```

In `lib/features/auth/signup_screen.dart`, make the same three changes: the constructor becomes `const SignupScreen({super.key, this.next});` with the same `final String? next;` field and doc comment; `_submit`'s `context.go(landingPathFor(user, resort))` becomes the same `next`-aware block; and the sign-in link's `onPressed: () => context.go('/login'),` becomes

```dart
                            onPressed: () => context.go(widget.next == null
                                ? '/login'
                                : '/login?next=${Uri.encodeQueryComponent(widget.next!)}'),
```

- [ ] **Step 8: Add the two entry points and the Browse filter**

In `lib/features/auth/welcome_screen.dart`, directly after the `OutlinedButton` (Sign Up) and before the closing `],` of the `Column`'s children, add:

```dart
                  const SizedBox(height: Spacing.md),
                  // Resort owners apply to be listed (P10); most are new,
                  // so this starts at sign-up and comes back afterwards.
                  TextButton(
                    key: const Key('welcome-list-resort'),
                    onPressed: () =>
                        context.go('/signup?next=%2Flist-your-resort'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('List your resort'),
                  ),
```

In `lib/features/shell/app_shell.dart`, in `showAccountSheet`, directly before `const SizedBox(height: Spacing.lg),` that precedes the sign-out button, add:

```dart
            if (user != null && !user.isPlatformAdmin) ...[
              const SizedBox(height: Spacing.md),
              ListTile(
                key: const Key('account-sheet-list-resort'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_business_outlined),
                title: const Text('List your resort'),
                subtitle: const Text('Apply to list a resort on ResortHub'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.go('/list-your-resort');
                },
              ),
            ],
```

In `lib/data/repositories/catalog_repository.dart`, in `properties()`, change

```dart
        final rows = await _db
            .from('properties')
            .select()
            .order('name', ascending: true);
```

to

```dart
        // Browse lists bookable resorts only: a member also reads their
        // own pending or suspended resort through properties_read, and it
        // must not show up among the ones guests can book.
        final rows = await _db
            .from('properties')
            .select()
            .eq('status', 'active')
            .order('name', ascending: true);
```

- [ ] **Step 9: Run the tests and the analyzer**

Run: `flutter test test/core/router_test.dart test/features/auth test/features/shell/app_shell_test.dart test/features/listing test/features/browse && flutter analyze 2>&1 | tail -5`
Expected: all PASS; the analyzer shows only the 2 baseline infos.

- [ ] **Step 10: Commit**

```bash
git add lib/features/listing/list_your_resort_screen.dart lib/core/router.dart lib/features/auth/welcome_screen.dart lib/features/auth/login_screen.dart lib/features/auth/signup_screen.dart lib/features/shell/app_shell.dart lib/data/repositories/catalog_repository.dart test/features/listing/list_your_resort_screen_test.dart test/core/router_test.dart test/features/auth/welcome_screen_test.dart test/features/auth/login_screen_test.dart test/features/auth/signup_screen_test.dart test/features/shell/app_shell_test.dart
git commit -m "feat(listing): List your resort entry points and application screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The Photos screen

**Track:** App. **Depends on:** Task 1. Can run alongside Tasks 5 and 8.

**Files:**
- Create: `lib/features/owner/property_photos_screen.dart`
- Modify: `lib/features/owner/owner_settings_screen.dart` (a Photos tile after "Farmhouse information")
- Test: `test/features/owner/property_photos_screen_test.dart` (create), `test/features/owner/owner_settings_screen_test.dart`

**Interfaces:**
- Consumes: `PropertyPhotosSource`, `propertyPhotosSourceProvider`, `maxPropertyPhotos` (Task 1); `propertyProvider`, `propertiesProvider` (`lib/features/browse/providers.dart`); `Property`; `image_picker`.
- Produces:
  - `typedef PickedPhoto = ({String filename, Uint8List bytes, String contentType})`.
  - `Future<PickedPhoto?> pickPhotoFromGallery()`.
  - `PropertyPhotosScreen({Key? key, required String propertyId, Future<PickedPhoto?> Function()? pickPhoto})`.
  - Widget keys: `add-photo`, `photos-empty`, `photo-remove-<index>`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/owner/property_photos_screen_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/repositories/property_photos_repository.dart';
import 'package:pasala/features/browse/providers.dart';
import 'package:pasala/features/owner/property_photos_screen.dart';

import '../../support/fake_property_photos_source.dart';

const _a = 'https://cdn.example.com/p1/a.jpg';
const _b = 'https://cdn.example.com/p1/b.jpg';

Property _property(List<String> images) => Property(
      id: 'p1',
      name: 'Green Acres',
      slug: 'green-acres',
      description: null,
      address: null,
      images: images,
      amenities: const [],
      checkInTime: '14:00',
      checkOutTime: '11:00',
      isActive: true,
    );

class _Harness {
  _Harness(this.images);
  List<String> images;
  int fetches = 0;
  final source = FakePropertyPhotosSource();
  PickedPhoto? picked;
}

Future<void> _pump(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      propertyProvider.overrideWith((ref, id) async {
        h.fetches++;
        return _property(h.images);
      }),
      propertyPhotosSourceProvider.overrideWithValue(h.source),
    ],
    child: MaterialApp(
      home: PropertyPhotosScreen(
        propertyId: 'p1',
        pickPhoto: () async => h.picked,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows each photo with a remove button', (tester) async {
    await _pump(tester, _Harness([_a, _b]));

    expect(find.byKey(const Key('photo-remove-0')), findsOneWidget);
    expect(find.byKey(const Key('photo-remove-1')), findsOneWidget);
    expect(find.byTooltip('Remove photo'), findsNWidgets(2));
    expect(find.byKey(const Key('photos-empty')), findsNothing);
  });

  testWidgets('with no photos it says so', (tester) async {
    await _pump(tester, _Harness([]));

    expect(find.text('No photos yet'), findsOneWidget);
  });

  testWidgets('Add photo uploads, appends the URL and refetches',
      (tester) async {
    final h = _Harness([_a])
      ..picked = (
        filename: 'pool.jpg',
        bytes: Uint8List.fromList([1, 2, 3]),
        contentType: 'image/jpeg',
      );
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('add-photo')));
    await tester.pumpAndSettle();

    expect(h.source.uploads, [('p1', 'pool.jpg', 3)]);
    expect(h.source.setCalls.single.$1, 'p1');
    expect(h.source.setCalls.single.$2, [_a, h.source.nextUrl]);
    expect(h.fetches, 2);
  });

  testWidgets('a cancelled pick sends nothing', (tester) async {
    final h = _Harness([_a]);
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('add-photo')));
    await tester.pumpAndSettle();

    expect(h.source.uploads, isEmpty);
    expect(h.source.setCalls, isEmpty);
  });

  testWidgets('a failed upload is shown and changes nothing', (tester) async {
    final h = _Harness([_a])
      ..picked = (
        filename: 'pool.jpg',
        bytes: Uint8List.fromList([1]),
        contentType: 'image/jpeg',
      );
    h.source.uploadError = const NetworkFailure();
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('add-photo')));
    await tester.pumpAndSettle();

    expect(find.text('Cannot reach the server. Check your connection.'),
        findsOneWidget);
    expect(h.source.setCalls, isEmpty);
  });

  testWidgets('removing a photo saves the list without it', (tester) async {
    final h = _Harness([_a, _b]);
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('photo-remove-0')));
    await tester.pumpAndSettle();

    expect(h.source.setCalls.single.$2, [_b]);
  });

  testWidgets('at ten photos Add photo is switched off and says why',
      (tester) async {
    await _pump(
        tester,
        _Harness([
          for (var i = 0; i < maxPropertyPhotos; i++)
            'https://cdn.example.com/p1/$i.jpg',
        ]));

    await tester.scrollUntilVisible(
        find.byKey(const Key('add-photo')), 300,
        scrollable: find.byType(Scrollable).first);
    final button =
        tester.widget<ButtonStyleButton>(find.byKey(const Key('add-photo')));
    expect(button.onPressed, isNull);
    expect(find.text('You can add up to 10 photos.'), findsOneWidget);
  });
}
```

In `test/features/owner/owner_settings_screen_test.dart`, add this test at the end of `main`:

```dart
  testWidgets('Photos opens the photo screen', (tester) async {
    await _pump(tester, FakeResortPlanSource());

    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();

    expect(find.text('No photos yet'), findsOneWidget);
    expect(find.text('Add photo'), findsOneWidget);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/owner/property_photos_screen_test.dart test/features/owner/owner_settings_screen_test.dart`
Expected: FAIL to compile — `property_photos_screen.dart` does not exist.

- [ ] **Step 3: Write the screen**

Create `lib/features/owner/property_photos_screen.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/repositories/property_photos_repository.dart';
import '../browse/providers.dart';

/// A photo chosen on the device, ready to upload.
typedef PickedPhoto = ({String filename, Uint8List bytes, String contentType});

/// Opens the device gallery (a file picker on the web); null when the
/// owner cancels. Large photos are scaled down before upload.
Future<PickedPhoto?> pickPhotoFromGallery() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 2000,
    imageQuality: 85,
  );
  if (file == null) return null;
  return (
    filename: file.name,
    bytes: await file.readAsBytes(),
    contentType: file.mimeType ?? 'image/jpeg',
  );
}

/// Photos -- the pictures guests see on the listing (`properties.images`,
/// P10 spec decision 17). Reached from the setup checklist and from
/// Settings. Uploads go to the public `property-photos` bucket; removing a
/// photo only drops its URL.
class PropertyPhotosScreen extends ConsumerStatefulWidget {
  const PropertyPhotosScreen({
    super.key,
    required this.propertyId,
    this.pickPhoto,
  });

  final String propertyId;

  /// Tests pass a fake; the app uses [pickPhotoFromGallery].
  final Future<PickedPhoto?> Function()? pickPhoto;

  @override
  ConsumerState<PropertyPhotosScreen> createState() =>
      _PropertyPhotosScreenState();
}

class _PropertyPhotosScreenState extends ConsumerState<PropertyPhotosScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
      ref.invalidate(propertyProvider(widget.propertyId));
      ref.invalidate(propertiesProvider);
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(List<String> current) async {
    final photo = await (widget.pickPhoto ?? pickPhotoFromGallery)();
    if (photo == null || !mounted) return;
    await _run(() async {
      final source = ref.read(propertyPhotosSourceProvider);
      final url = await source.upload(
        widget.propertyId,
        filename: photo.filename,
        bytes: photo.bytes,
        contentType: photo.contentType,
      );
      await source.setPhotos(widget.propertyId, [...current, url]);
    });
  }

  Future<void> _remove(List<String> current, int index) => _run(
        () => ref
            .read(propertyPhotosSourceProvider)
            .setPhotos(widget.propertyId, [...current]..removeAt(index)),
      );

  @override
  Widget build(BuildContext context) {
    final property = ref.watch(propertyProvider(widget.propertyId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Photos')),
      body: AsyncView(
        value: property,
        onRetry: () => ref.invalidate(propertyProvider(widget.propertyId)),
        data: (p) {
          final images = p.images;
          final full = images.length >= maxPropertyPhotos;
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              if (images.isEmpty)
                const Padding(
                  key: Key('photos-empty'),
                  padding: EdgeInsets.all(Spacing.lg),
                  child: Text('No photos yet', textAlign: TextAlign.center),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: Spacing.sm,
                    crossAxisSpacing: Spacing.sm,
                    childAspectRatio: 4 / 3,
                  ),
                  itemCount: images.length,
                  itemBuilder: (context, i) => Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(PasalaTokens.radiusSm),
                        child: Image.network(
                          images[i],
                          fit: BoxFit.cover,
                          semanticLabel: 'Photo ${i + 1} of ${images.length}',
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                      Positioned(
                        top: Spacing.xs,
                        right: Spacing.xs,
                        child: IconButton.filledTonal(
                          key: Key('photo-remove-$i'),
                          tooltip: 'Remove photo',
                          icon: const Icon(Icons.delete_outline),
                          onPressed:
                              _busy ? null : () => _remove(images, i),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Spacing.md),
              FilledButton.icon(
                key: const Key('add-photo'),
                onPressed: _busy || full ? null : () => _add(images),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add photo'),
              ),
              if (full) ...[
                const SizedBox(height: Spacing.xs),
                const Text('You can add up to 10 photos.',
                    textAlign: TextAlign.center),
              ],
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Add the Settings tile**

In `lib/features/owner/owner_settings_screen.dart`, add the import:

```dart
import 'property_photos_screen.dart';
```

and directly after the "Farmhouse information" `_SettingsTile(...)`, add:

```dart
              _SettingsTile(
                icon: Icons.photo_library_outlined,
                title: 'Photos',
                subtitle: 'Pictures guests see on your listing',
                color: scheme.primary,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PropertyPhotosScreen(propertyId: property.id),
                )),
              ),
```

- [ ] **Step 5: Run the tests and the analyzer**

Run: `flutter test test/features/owner/property_photos_screen_test.dart test/features/owner/owner_settings_screen_test.dart && flutter analyze 2>&1 | tail -5`
Expected: all PASS; only the 2 baseline infos.

- [ ] **Step 6: Commit**

```bash
git add lib/features/owner/property_photos_screen.dart lib/features/owner/owner_settings_screen.dart test/features/owner/property_photos_screen_test.dart test/features/owner/owner_settings_screen_test.dart
git commit -m "feat(owner): Photos screen for listing photos

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 7: The setup checklist on `/owner`

**Track:** App. **Depends on:** Task 6 (the checklist opens `PropertyPhotosScreen`). Can run alongside Tasks 5 and 8.

**Files:**
- Create: `lib/features/owner/setup_checklist_card.dart`
- Modify: `lib/features/owner/owner_home_screen.dart` (`build`: the resort variable and the card)
- Test: `test/features/owner/setup_checklist_card_test.dart` (create), `test/features/owner/owner_home_screen_test.dart`

**Interfaces:**
- Consumes: `ListingSource`, `listingSourceProvider`, `listingSetupProvider`, `ListingSetup`, `SetupStep`, `ListingBlocked` (Task 1); `PropertyPhotosScreen` (Task 6); `UnitsScreen` (`lib/features/admin/units_screen.dart`), `PaymentSettingsScreen`, `CancellationPolicyScreen`, `TaxSettingsScreen` (each `({required Property property})`); `propertyProvider`; `currentUserProvider`; `ResortMembership.status`.
- Produces:
  - `typedef OpenSetupStep = Future<void> Function(SetupStep step)`.
  - `Future<void> openSetupStep(BuildContext context, WidgetRef ref, String propertyId, SetupStep step)`.
  - `SetupChecklistCard({Key? key, required String propertyId, required String resortName, OpenSetupStep? onOpenStep})`.
  - Widget keys: `setup-checklist`, `setup-progress`, `setup-step-<step.name>`, `setup-submit`, `setup-submitted`, `setup-live-refresh`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/owner/setup_checklist_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/listing.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/listing_repository.dart';
import 'package:pasala/features/owner/setup_checklist_card.dart';

import '../../support/fake_listing_source.dart';

const _owner = AppUser(id: 'o1', email: 'owner@example.com');

Future<List<SetupStep>> _pump(
  WidgetTester tester,
  FakeListingSource source,
) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final opened = <SetupStep>[];
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      listingSourceProvider.overrideWithValue(source),
      currentUserProvider.overrideWith((ref) => Stream.value(_owner)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SetupChecklistCard(
            propertyId: 'p1',
            resortName: 'Green Acres',
            onOpenStep: (step) async => opened.add(step),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return opened;
}

Icon _stepIcon(WidgetTester tester, SetupStep step) => tester.widget<Icon>(
    find
        .descendant(
            of: find.byKey(Key('setup-step-${step.name}')),
            matching: find.byType(Icon))
        .first);

void main() {
  testWidgets('shows progress and every step, in words as well as icons',
      (tester) async {
    final source = FakeListingSource()
      ..setup = listingSetup(done: {SetupStep.photos, SetupStep.units});
    await _pump(tester, source);

    expect(find.text('Finish setting up Green Acres'), findsOneWidget);
    expect(find.text('2 of 6 done'), findsOneWidget);
    for (final step in SetupStep.values) {
      expect(find.text(step.title), findsOneWidget);
    }
    expect(_stepIcon(tester, SetupStep.photos).semanticLabel, 'Done');
    expect(_stepIcon(tester, SetupStep.tax).semanticLabel, 'Not done');
    expect(source.setupCalls, ['p1']);
  });

  testWidgets('Submit for review stays off until every step is done',
      (tester) async {
    final source = FakeListingSource()
      ..setup = listingSetup(done: {SetupStep.photos});
    await _pump(tester, source);

    final button =
        tester.widget<ButtonStyleButton>(find.byKey(const Key('setup-submit')));
    expect(button.onPressed, isNull);
    expect(find.text('Complete every step to submit.'), findsOneWidget);
  });

  testWidgets('a complete checklist submits and then shows the submission',
      (tester) async {
    final source = FakeListingSource()..setup = listingSetup(done: allSetupSteps);
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('setup-submit')));
    await tester.pumpAndSettle();

    expect(source.submitCalls, ['p1']);
    expect(find.text('Submitted for review.'), findsOneWidget);
    expect(find.byKey(const Key('setup-submitted')), findsOneWidget);
    expect(
        find.text('Submitted for review on 25 Sep 2026. '
            'We will email you when it is decided.'),
        findsOneWidget);
    expect(find.byKey(const Key('setup-submit')), findsNothing);
    expect(source.setupCalls, ['p1', 'p1']);
  });

  testWidgets('a refusal from the server is shown as written', (tester) async {
    final source = FakeListingSource()
      ..setup = listingSetup(done: allSetupSteps)
      ..submitError =
          const ListingBlocked('Finish the setup checklist before submitting.');
    await _pump(tester, source);

    await tester.tap(find.byKey(const Key('setup-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Finish the setup checklist before submitting.'),
        findsOneWidget);
  });

  testWidgets('a step opens its screen and the checklist refreshes on return',
      (tester) async {
    final source = FakeListingSource()..setup = listingSetup();
    final opened = await _pump(tester, source);

    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();

    expect(opened, [SetupStep.photos]);
    expect(source.setupCalls, ['p1', 'p1']);
  });

  testWidgets('a resort approved meanwhile says it is live', (tester) async {
    final source = FakeListingSource()
      ..setup = listingSetup(status: 'active', done: allSetupSteps);
    await _pump(tester, source);

    expect(find.text('Your resort is live'), findsOneWidget);
    expect(find.byKey(const Key('setup-live-refresh')), findsOneWidget);
    expect(find.text('Add photos'), findsNothing);
  });

  testWidgets('a failed load says so and retries', (tester) async {
    final source = FakeListingSource()..setupError = const NetworkFailure();
    await _pump(tester, source);

    expect(find.text('Could not load your setup checklist'), findsOneWidget);
    source.setupError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('0 of 6 done'), findsOneWidget);
  });
}
```

In `test/features/owner/owner_home_screen_test.dart`:

1. Add imports:

```dart
import 'package:pasala/data/repositories/listing_repository.dart';

import '../../support/fake_listing_source.dart';
```

2. Change `_appFor`'s signature and overrides from

```dart
Widget _appFor({
  DashboardSummary summary = const DashboardSummary(
```

to

```dart
Widget _appFor({
  ResortMembership resort = _ownerM,
  FakeListingSource? listing,
  DashboardSummary summary = const DashboardSummary(
```

and

```dart
      currentResortProvider.overrideWith(() => _FixedResort(_ownerM)),
      dashboardSummaryProvider.overrideWith((ref, propertyId) async => summary),
```

to

```dart
      currentResortProvider.overrideWith(() => _FixedResort(resort)),
      dashboardSummaryProvider.overrideWith((ref, propertyId) async => summary),
      listingSourceProvider.overrideWithValue(listing ?? FakeListingSource()),
```

3. Add these tests at the end of `main`:

```dart
  testWidgets('a pending resort shows its setup checklist first',
      (tester) async {
    final listing = FakeListingSource()
      ..setup = listingSetup(done: {SetupStep.units});
    await tester.pumpWidget(_appFor(
      resort: const ResortMembership(
          propertyId: 'p1',
          resortName: 'Pasala',
          role: ResortRole.owner,
          status: 'pending'),
      listing: listing,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('setup-checklist')), findsOneWidget);
    expect(find.text('Finish setting up Pasala'), findsOneWidget);
    expect(listing.setupCalls, ['p1']);
  });

  testWidgets('an active resort shows no checklist and asks for none',
      (tester) async {
    final listing = FakeListingSource();
    await tester.pumpWidget(_appFor(listing: listing));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('setup-checklist')), findsNothing);
    expect(listing.setupCalls, isEmpty);
  });
```

(Add `import 'package:pasala/data/models/listing.dart';` too, for `SetupStep`.)

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/owner/setup_checklist_card_test.dart test/features/owner/owner_home_screen_test.dart`
Expected: FAIL to compile — `setup_checklist_card.dart` does not exist.

- [ ] **Step 3: Write the card**

Create `lib/features/owner/setup_checklist_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/listing.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/listing_repository.dart';
import '../admin/units_screen.dart';
import '../browse/providers.dart';
import 'cancellation_policy_screen.dart';
import 'payment_settings_screen.dart';
import 'property_photos_screen.dart';
import 'tax_settings_screen.dart';

/// Opens the screen that finishes one checklist step; completes when the
/// owner comes back.
typedef OpenSetupStep = Future<void> Function(SetupStep step);

/// Pushes the existing screen for [step] at [propertyId]. Units and rates
/// share `UnitsScreen`, whose menu leads to each unit's rates.
Future<void> openSetupStep(
  BuildContext context,
  WidgetRef ref,
  String propertyId,
  SetupStep step,
) async {
  final navigator = Navigator.of(context);
  final Widget screen = switch (step) {
    SetupStep.photos => PropertyPhotosScreen(propertyId: propertyId),
    SetupStep.units || SetupStep.rates => UnitsScreen(propertyId: propertyId),
    SetupStep.payments => PaymentSettingsScreen(
        property: await ref.read(propertyProvider(propertyId).future)),
    SetupStep.cancellation => CancellationPolicyScreen(
        property: await ref.read(propertyProvider(propertyId).future)),
    SetupStep.tax => TaxSettingsScreen(
        property: await ref.read(propertyProvider(propertyId).future)),
  };
  await navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
}

/// The setup checklist a pending resort's owner sees at the top of `/owner`
/// (P10 spec decisions 3, 10, 11): six steps worked out by the server,
/// each opening its screen and refetched on return, and "Submit for
/// review" once all are done. Done / not done is an icon with a label and
/// a word, never colour alone.
class SetupChecklistCard extends ConsumerStatefulWidget {
  const SetupChecklistCard({
    super.key,
    required this.propertyId,
    required this.resortName,
    this.onOpenStep,
  });

  final String propertyId;
  final String resortName;

  /// Tests pass a recorder; the app uses [openSetupStep].
  final OpenSetupStep? onOpenStep;

  @override
  ConsumerState<SetupChecklistCard> createState() =>
      _SetupChecklistCardState();
}

class _SetupChecklistCardState extends ConsumerState<SetupChecklistCard> {
  bool _submitting = false;

  void _refetch() => ref.invalidate(listingSetupProvider(widget.propertyId));

  Future<void> _open(SetupStep step) async {
    final open = widget.onOpenStep ??
        (s) => openSetupStep(context, ref, widget.propertyId, s);
    await open(step);
    if (mounted) _refetch();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ref.read(listingSourceProvider).submitForReview(widget.propertyId);
      _refetch();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Submitted for review.')));
      }
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(listingSetupProvider(widget.propertyId));
    final value = setup.value;
    final Widget body;
    if (value != null) {
      body = value.isPending ? _checklist(context, value) : _live(context);
    } else if (setup.hasError) {
      body = _error();
    } else {
      body = const Padding(
        padding: EdgeInsets.all(Spacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Card(
      key: const Key('setup-checklist'),
      child: Padding(padding: const EdgeInsets.all(Spacing.md), child: body),
    );
  }

  Widget _checklist(BuildContext context, ListingSetup setup) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final submitted = setup.submittedAt;
    final total = SetupStep.values.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Finish setting up ${widget.resortName}',
                  style: textTheme.titleMedium),
            ),
            IconButton(
              tooltip: 'Refresh checklist',
              icon: const Icon(Icons.refresh),
              onPressed: _refetch,
            ),
          ],
        ),
        Text(
          'Your resort is hidden from guests until ResortHub approves it.',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.sm),
        Text('${setup.doneCount} of $total done',
            key: const Key('setup-progress')),
        const SizedBox(height: Spacing.xs),
        LinearProgressIndicator(value: setup.doneCount / total),
        const SizedBox(height: Spacing.sm),
        for (final step in SetupStep.values)
          ListTile(
            key: Key('setup-step-${step.name}'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              setup.isDone(step)
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color:
                  setup.isDone(step) ? scheme.primary : scheme.onSurfaceVariant,
              semanticLabel: setup.isDone(step) ? 'Done' : 'Not done',
            ),
            title: Text(step.title),
            subtitle: Text(step.hint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(step),
          ),
        const SizedBox(height: Spacing.sm),
        if (submitted != null)
          Text(
            'Submitted for review on ${formatDate(submitted.toLocal())}. '
            'We will email you when it is decided.',
            key: const Key('setup-submitted'),
          )
        else ...[
          FilledButton(
            key: const Key('setup-submit'),
            onPressed: setup.complete && !_submitting ? _submit : null,
            child: const Text('Submit for review'),
          ),
          if (!setup.complete) ...[
            const SizedBox(height: Spacing.xs),
            Text('Complete every step to submit.', style: textTheme.bodySmall),
          ],
        ],
      ],
    );
  }

  Widget _live(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your resort is live',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          Text('ResortHub approved ${widget.resortName}. '
              'Guests can now find and book it.'),
          const SizedBox(height: Spacing.sm),
          TextButton(
            key: const Key('setup-live-refresh'),
            // Refetching the user updates the membership's status, so the
            // owner hub stops showing this card.
            onPressed: () => ref.invalidate(currentUserProvider),
            child: const Text('Refresh'),
          ),
        ],
      );

  Widget _error() => Row(
        children: [
          const Expanded(child: Text('Could not load your setup checklist')),
          TextButton(onPressed: _refetch, child: const Text('Retry')),
        ],
      );
}
```

- [ ] **Step 4: Show it on `/owner` for a pending resort**

In `lib/features/owner/owner_home_screen.dart`, add the import:

```dart
import 'setup_checklist_card.dart';
```

replace

```dart
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
```

with

```dart
    final resort = ref.watch(currentResortProvider)!;
    final propertyId = resort.propertyId;
```

and, in the `ListView`'s children, directly after the `fullDateFor(now)` `Text(...)` and its following `const SizedBox(height: Spacing.md),`, add:

```dart
          // A resort waiting for review (P10) leads with what is left to
          // do before it can go live.
          if (resort.status == 'pending') ...[
            SetupChecklistCard(
              propertyId: propertyId,
              resortName: resort.resortName,
            ),
            const SizedBox(height: Spacing.md),
          ],
```

Also update the class doc comment's last sentence to: `The destination tiles follow, including Rooms (the room status grid); a pending resort gets its setup checklist above the figures.`

- [ ] **Step 5: Run the tests and the analyzer**

Run: `flutter test test/features/owner && flutter analyze 2>&1 | tail -5`
Expected: all PASS; only the 2 baseline infos.

- [ ] **Step 6: Commit**

```bash
git add lib/features/owner/setup_checklist_card.dart lib/features/owner/owner_home_screen.dart test/features/owner/setup_checklist_card_test.dart test/features/owner/owner_home_screen_test.dart
git commit -m "feat(owner): setup checklist and Submit for review on a pending resort

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The console's review queue

**Track:** App. **Depends on:** Task 1. Can run alongside Tasks 5–7.

**Files:**
- Create: `lib/features/platform/pending_listings.dart`
- Modify: `lib/features/platform/platform_screen.dart` (state, `_refresh`, the list's children)
- Modify: `lib/features/platform/resort_card.dart` (pending resorts)
- Test: `test/features/platform/pending_listings_test.dart` (create), `test/features/platform/platform_screen_test.dart`, `test/features/platform/resort_card_test.dart`

**Interfaces:**
- Consumes: `ListingReviewSource`, `listingReviewSourceProvider`, `pendingListingsProvider`, `PendingListing`, `SetupStep`, `validateRejectionReason`, `ListingBlocked` (Task 1); `SubscriptionTier` and `label`; `formatDate`; `FailureView`.
- Produces:
  - `List<PendingListing> filterPendingListings(List<PendingListing> pending, {String query = '', SubscriptionTier? tier})`.
  - `PendingListingsCard({required bool selected, required VoidCallback onTap})`, `PendingListingsList({required String query, required SubscriptionTier? tier, required VoidCallback onChanged})`, `PendingListingCard({required PendingListing listing, required VoidCallback onChanged})`, `RejectListingDialog({required PendingListing listing})`.
  - Widget keys: `pending-listings-card`, `pending-count`, `pending-filter`, `no-pending-listings`, `pending-listing-<id>`, `pending-step-<id>-<step.name>`, `approve-<id>`, `approve-confirm`, `reject-<id>`, `reject-reason`, `reject-confirm`, `resort-pending-note-<id>`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/platform/pending_listings_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/listing.dart';
import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/listing_repository.dart';
import 'package:pasala/features/platform/pending_listings.dart';

import '../../support/fake_listing_source.dart';

Future<int Function()> _pump(
  WidgetTester tester,
  FakeListingReviewSource source,
  PendingListing listing,
) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  var changed = 0;
  await tester.pumpWidget(ProviderScope(
    overrides: [listingReviewSourceProvider.overrideWithValue(source)],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PendingListingCard(
            listing: listing,
            onChanged: () => changed++,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return () => changed;
}

final _submitted = DateTime.utc(2026, 9, 20, 12);

void main() {
  testWidgets('shows the applicant, the contact details and the checklist',
      (tester) async {
    await _pump(
        tester,
        FakeListingReviewSource(),
        pendingListing(
            submittedAt: _submitted,
            done: {SetupStep.photos, SetupStep.units}));

    expect(find.text('Green Acres'), findsOneWidget);
    expect(find.text('Asha Applicant · asha@example.com'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('Submitted 20 Sep 2026'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('pending-step-r1-photos')),
            matching: find.byIcon(Icons.check)),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('pending-step-r1-tax')),
            matching: find.byIcon(Icons.close)),
        findsOneWidget);
  });

  testWidgets('Approve is off until the application is submitted and complete',
      (tester) async {
    await _pump(tester, FakeListingReviewSource(), pendingListing());

    expect(find.text('Setting up — not submitted yet'), findsOneWidget);
    expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('approve-r1')))
            .onPressed,
        isNull);
  });

  testWidgets('an incomplete checklist cannot be approved either',
      (tester) async {
    await _pump(tester, FakeListingReviewSource(),
        pendingListing(submittedAt: _submitted, done: {SetupStep.photos}));

    expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('approve-r1')))
            .onPressed,
        isNull);
  });

  testWidgets('Approve asks first, then approves', (tester) async {
    final source = FakeListingReviewSource();
    final changed =
        await _pump(tester, source, pendingListing(submittedAt: _submitted));

    await tester.tap(find.byKey(const Key('approve-r1')));
    await tester.pumpAndSettle();
    expect(find.text('Approve Green Acres?'), findsOneWidget);
    expect(find.text('It goes live for guests now.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('approve-confirm')));
    await tester.pumpAndSettle();

    expect(source.approveCalls, ['r1']);
    expect(changed(), 1);
  });

  testWidgets('Cancel in the approve dialog does nothing', (tester) async {
    final source = FakeListingReviewSource();
    final changed =
        await _pump(tester, source, pendingListing(submittedAt: _submitted));

    await tester.tap(find.byKey(const Key('approve-r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(source.approveCalls, isEmpty);
    expect(changed(), 0);
  });

  testWidgets('a refused approval is shown as written', (tester) async {
    final source = FakeListingReviewSource()
      ..approveError =
          const ListingBlocked('The setup checklist is no longer complete.');
    final changed =
        await _pump(tester, source, pendingListing(submittedAt: _submitted));

    await tester.tap(find.byKey(const Key('approve-r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approve-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('The setup checklist is no longer complete.'),
        findsOneWidget);
    expect(changed(), 0);
  });

  testWidgets('Reject needs a reason and sends it trimmed', (tester) async {
    final source = FakeListingReviewSource();
    final changed = await _pump(tester, source, pendingListing());

    await tester.tap(find.byKey(const Key('reject-r1')));
    await tester.pumpAndSettle();
    expect(find.text('Reject Green Acres?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reject-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Give the owner a reason (5 to 500 characters).'),
        findsOneWidget);
    expect(source.rejectCalls, isEmpty);

    await tester.enterText(find.byKey(const Key('reject-reason')),
        '  Photos do not match the address.  ');
    await tester.tap(find.byKey(const Key('reject-confirm')));
    await tester.pumpAndSettle();

    expect(source.rejectCalls, [('r1', 'Photos do not match the address.')]);
    expect(changed(), 1);
    expect(find.text('Reject Green Acres?'), findsNothing);
  });

  test('filterPendingListings matches name, city and applicant email', () {
    final pending = [
      pendingListing(propertyId: 'r1'),
      pendingListing(
          propertyId: 'r2',
          name: 'Hill View',
          city: 'Pune',
          applicantEmail: 'ravi@example.com',
          tier: SubscriptionTier.starter),
    ];

    List<String> ids(List<PendingListing> l) =>
        l.map((p) => p.propertyId).toList();
    expect(ids(filterPendingListings(pending, query: '  PUNE ')), ['r2']);
    expect(ids(filterPendingListings(pending, query: 'asha@')), ['r1']);
    expect(ids(filterPendingListings(pending, query: 'green')), ['r1']);
    expect(ids(filterPendingListings(pending, tier: SubscriptionTier.starter)),
        ['r2']);
    expect(ids(filterPendingListings(pending)), ['r1', 'r2']);
  });
}
```

In `test/features/platform/platform_screen_test.dart`:

1. Add imports:

```dart
import 'package:pasala/data/repositories/listing_repository.dart';

import '../../support/fake_listing_source.dart';
```

2. Change `_appFor` to also take the review source:

```dart
Widget _appFor(
  FakePlatformSource repo, {
  ThemeMode themeMode = ThemeMode.light,
  FakeListingReviewSource? review,
}) =>
    ProviderScope(
      overrides: [
        platformSourceProvider.overrideWithValue(repo),
        listingReviewSourceProvider
            .overrideWithValue(review ?? FakeListingReviewSource()),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: themeMode,
        home: const PlatformScreen(),
      ),
    );
```

3. Add these tests at the end of `main`:

```dart
  group('pending review', () {
    FakeListingReviewSource review() => FakeListingReviewSource()
      ..pending = [
        pendingListing(propertyId: 'r1', submittedAt: DateTime.utc(2026, 9, 20, 12)),
        pendingListing(
            propertyId: 'r2',
            name: 'Hill View',
            city: 'Pune',
            applicantEmail: 'ravi@example.com'),
      ];

    testWidgets('the count card shows submitted and still-being-set-up counts',
        (tester) async {
      _tall(tester);
      await tester.pumpWidget(
          _appFor(FakePlatformSource()..store = [_resortA], review: review()));
      await tester.pumpAndSettle();

      final card = find.byKey(const Key('pending-listings-card'));
      expect(find.descendant(of: card, matching: find.text('Waiting for review')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('1 setting up')),
          findsOneWidget);
    });

    testWidgets('the Pending review filter shows applications, not resorts',
        (tester) async {
      _tall(tester);
      await tester.pumpWidget(
          _appFor(FakePlatformSource()..store = [_resortA], review: review()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pending-filter')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pending-listing-r1')), findsOneWidget);
      expect(find.byKey(const Key('pending-listing-r2')), findsOneWidget);
      expect(find.text('Resort A'), findsNothing);
    });

    testWidgets('tapping the count card switches the filter too',
        (tester) async {
      _tall(tester);
      await tester.pumpWidget(
          _appFor(FakePlatformSource()..store = [_resortA], review: review()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pending-listings-card')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pending-listing-r1')), findsOneWidget);
    });

    testWidgets('search narrows the applications by city', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
          _appFor(FakePlatformSource()..store = [_resortA], review: review()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pending-filter')));
      await tester.enterText(find.byKey(const Key('resort-search')), 'pune');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pending-listing-r2')), findsOneWidget);
      expect(find.byKey(const Key('pending-listing-r1')), findsNothing);
    });

    testWidgets('with nothing pending it says so', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_appFor(FakePlatformSource()..store = [_resortA]));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pending-filter')));
      await tester.pumpAndSettle();

      expect(find.text('No resorts are waiting for review.'), findsOneWidget);
    });

    testWidgets('after a decision the queue, the list and the cards refetch',
        (tester) async {
      _tall(tester);
      final repo = FakePlatformSource()..store = [_resortA];
      final source = review();
      await tester.pumpWidget(_appFor(repo, review: source));
      await tester.pumpAndSettle();
      final resortsBefore = repo.resortsCalls;
      final pendingBefore = source.pendingCalls;

      await tester.tap(find.byKey(const Key('pending-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approve-r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approve-confirm')));
      await tester.pumpAndSettle();

      expect(source.approveCalls, ['r1']);
      expect(repo.resortsCalls, greaterThan(resortsBefore));
      expect(source.pendingCalls, greaterThan(pendingBefore));
      expect(find.byKey(const Key('pending-listing-r1')), findsNothing);
    });
  });
```

In `test/features/platform/resort_card_test.dart`, add at the end of `main`:

```dart
  testWidgets('a pending resort waits for review: no status or plan actions',
      (tester) async {
    await _pump(
        tester,
        FakePlatformSource(),
        resortSummary(
            status: 'pending',
            plan: resortPlan(tier: SubscriptionTier.starter)));

    expect(find.text('Pending review'), findsOneWidget);
    expect(find.byKey(const Key('resort-status-btn-p1')), findsNothing);
    expect(find.byKey(const Key('resort-plan-btn-p1')), findsNothing);
    expect(find.text('Waiting for review: see Pending review above.'),
        findsOneWidget);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/platform`
Expected: FAIL to compile — `pending_listings.dart` does not exist.

- [ ] **Step 3: Write the review widgets**

Create `lib/features/platform/pending_listings.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/listing.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/listing_repository.dart';

/// The Pending review filter (P10), applied on the device like the resort
/// filter: [query] matches the resort name, the city or the applicant's
/// email, ignoring case and surrounding spaces; a [tier] keeps only that
/// tier. Order is kept.
List<PendingListing> filterPendingListings(
  List<PendingListing> pending, {
  String query = '',
  SubscriptionTier? tier,
}) {
  final q = query.trim().toLowerCase();
  bool matches(PendingListing p) =>
      q.isEmpty ||
      p.name.toLowerCase().contains(q) ||
      p.city.toLowerCase().contains(q) ||
      p.applicantEmail.toLowerCase().contains(q);
  return [
    for (final p in pending)
      if ((tier == null || p.tier == tier) && matches(p)) p,
  ];
}

/// The console's "Waiting for review" card: submitted applications
/// waiting for a decision, and how many are still being set up. Tapping it
/// switches the Pending review filter.
class PendingListingsCard extends ConsumerWidget {
  const PendingListingsCard({
    super.key,
    required this.selected,
    required this.onTap,
  });

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending =
        ref.watch(pendingListingsProvider).value ?? const <PendingListing>[];
    final submitted = pending.where((p) => p.submitted).length;
    final settingUp = pending.length - submitted;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      key: const Key('pending-listings-card'),
      color: selected ? scheme.secondaryContainer : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              Icon(Icons.pending_actions_outlined, color: scheme.primary),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Waiting for review', style: textTheme.labelLarge),
                    Text('$submitted',
                        key: const Key('pending-count'),
                        style: textTheme.headlineSmall),
                    Text('$settingUp setting up',
                        style: textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The list shown while the Pending review filter is on.
class PendingListingsList extends ConsumerWidget {
  const PendingListingsList({
    super.key,
    required this.query,
    required this.tier,
    required this.onChanged,
  });

  final String query;
  final SubscriptionTier? tier;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(pendingListingsProvider).when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => FailureView(
              error: e,
              onRetry: () => ref.invalidate(pendingListingsProvider),
            ),
            data: (pending) {
              final shown =
                  filterPendingListings(pending, query: query, tier: tier);
              if (shown.isEmpty) {
                return const Padding(
                  key: Key('no-pending-listings'),
                  padding: EdgeInsets.all(Spacing.lg),
                  child: Text('No resorts are waiting for review.',
                      textAlign: TextAlign.center),
                );
              }
              return Column(
                children: [
                  for (final l in shown) ...[
                    PendingListingCard(listing: l, onChanged: onChanged),
                    const SizedBox(height: Spacing.sm),
                  ],
                ],
              );
            },
          );
}

/// One undecided application: the resort, the applicant, the contact
/// details, the plan, whether it was submitted, the six checklist items
/// (a check or a cross beside each title), and Approve / Reject.
class PendingListingCard extends ConsumerWidget {
  const PendingListingCard({
    super.key,
    required this.listing,
    required this.onChanged,
  });

  final PendingListing listing;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final id = listing.propertyId;
    final submittedAt = listing.submittedAt;

    return Card(
      key: Key('pending-listing-$id'),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(listing.name, style: textTheme.titleMedium)),
                Chip(label: Text(listing.tier.label), side: BorderSide.none),
              ],
            ),
            Text('${listing.city} · ${listing.address}'),
            Text(listing.applicantName == null
                ? listing.applicantEmail
                : '${listing.applicantName} · ${listing.applicantEmail}'),
            Text(listing.contactPhone),
            const SizedBox(height: Spacing.xs),
            Text(listing.description,
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Spacing.sm),
            Text(
              submittedAt == null
                  ? 'Setting up — not submitted yet'
                  : 'Submitted ${formatDate(submittedAt.toLocal())}',
              style: textTheme.labelLarge?.copyWith(
                  color: submittedAt == null
                      ? scheme.onSurfaceVariant
                      : scheme.primary),
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                for (final step in SetupStep.values)
                  Chip(
                    key: Key('pending-step-$id-${step.name}'),
                    avatar: Icon(
                      (listing.setup[step] ?? false) ? Icons.check : Icons.close,
                      size: 16,
                    ),
                    label: Text(step.title),
                    side: BorderSide.none,
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: Spacing.sm,
                children: [
                  TextButton(
                    key: Key('reject-$id'),
                    onPressed: () => _reject(context),
                    child: const Text('Reject'),
                  ),
                  FilledButton(
                    key: Key('approve-$id'),
                    onPressed: listing.canApprove
                        ? () => _approve(context, ref)
                        : null,
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Approve ${listing.name}?'),
        content: const Text('It goes live for guests now.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('approve-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(listingReviewSourceProvider).approve(listing.propertyId);
      onChanged();
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }

  Future<void> _reject(BuildContext context) async {
    final rejected = await showDialog<bool>(
      context: context,
      builder: (_) => RejectListingDialog(listing: listing),
    );
    if (rejected == true) onChanged();
  }
}

/// Asks for the reason the owner will see (5 to 500 characters, as
/// `reject_listing` requires), then rejects. Pops `true` once rejected.
class RejectListingDialog extends ConsumerStatefulWidget {
  const RejectListingDialog({super.key, required this.listing});

  final PendingListing listing;

  @override
  ConsumerState<RejectListingDialog> createState() =>
      _RejectListingDialogState();
}

class _RejectListingDialogState extends ConsumerState<RejectListingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(listingReviewSourceProvider)
          .reject(widget.listing.propertyId, _reason.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } on BookingFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = FailureView.messageFor(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Reject ${widget.listing.name}?'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const Key('reject-reason'),
                controller: _reason,
                decoration: const InputDecoration(
                    labelText: 'Reason (the owner sees this)'),
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                validator: validateRejectionReason,
              ),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('reject-confirm'),
            onPressed: _busy ? null : _submit,
            child: const Text('Reject'),
          ),
        ],
      );
}
```

- [ ] **Step 4: Put the queue on the console**

In `lib/features/platform/platform_screen.dart`:

1. Add the imports:

```dart
import '../../data/repositories/listing_repository.dart';
import 'pending_listings.dart';
```

2. In `_PlatformScreenState`, below `SubscriptionTier? _tier;`, add:

```dart
  /// The Pending review filter (P10): per-visit UI state, like the search.
  bool _pendingOnly = false;
```

3. In `_refresh`, add a third line:

```dart
    ref.invalidate(pendingListingsProvider);
```

4. In the `ListView`'s children, directly after `const PlatformTotalsRow(),` and its `const SizedBox(height: Spacing.md),`, add:

```dart
              PendingListingsCard(
                selected: _pendingOnly,
                onTap: () => setState(() => _pendingOnly = !_pendingOnly),
              ),
              const SizedBox(height: Spacing.md),
```

5. Replace the block that starts at the `ResortFilterBar(`'s following `const SizedBox(height: Spacing.md),` and ends at the end of the `for (final resort in shown) ...[ ... ],` loop with:

```dart
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  key: const Key('pending-filter'),
                  label: const Text('Pending review'),
                  selected: _pendingOnly,
                  onSelected: (on) => setState(() => _pendingOnly = on),
                ),
              ),
              const SizedBox(height: Spacing.md),
              if (_pendingOnly)
                PendingListingsList(
                  query: _search.text,
                  tier: _tier,
                  onChanged: _refresh,
                )
              else if (shown.isEmpty)
                const Padding(
                  key: Key('no-matching-resorts'),
                  padding: EdgeInsets.all(Spacing.lg),
                  child: Text(
                    'No resorts match your search.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final resort in shown) ...[
                  ResortCard(resort: resort, onChanged: _refresh),
                  const SizedBox(height: Spacing.sm),
                ],
```

6. Add to the class doc comment, after "the plan prices.": ` A "Waiting for review" card and a Pending review filter show the resort applications waiting for Approve or Reject (P10).`

In `lib/features/platform/resort_card.dart`:

1. Directly after `final archived = resort.status == 'archived';`, add:

```dart
    // A pending resort waits for Approve / Reject in the Pending review
    // list (P10); Suspend or a plan change here would bypass the review.
    final pending = resort.status == 'pending';
```

2. Change the status chip to:

```dart
                Chip(
                  label: Text(
                      pending ? 'Pending review' : _statusLabel(resort.status)),
                  backgroundColor: pending
                      ? scheme.tertiaryContainer
                      : suspended
                          ? scheme.errorContainer
                          : archived
                              ? scheme.surfaceContainerHighest
                              : scheme.secondaryContainer,
                  side: BorderSide.none,
                ),
```

3. Change `if (!archived) ...[` to `if (!archived && !pending) ...[`, and directly after that block's closing `],` add:

```dart
            if (pending) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                'Waiting for review: see Pending review above.',
                key: Key('resort-pending-note-${resort.propertyId}'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
```

4. Update the class doc comment's last sentence to: `An archived resort gets no action at all, and a pending one (P10) waits for Approve or Reject in the Pending review list.`

- [ ] **Step 5: Run the tests and the analyzer**

Run: `flutter test test/features/platform && flutter analyze 2>&1 | tail -5`
Expected: all PASS (the existing console tests too: the review fake defaults to an empty queue); only the 2 baseline infos.

- [ ] **Step 6: Commit**

```bash
git add lib/features/platform/pending_listings.dart lib/features/platform/platform_screen.dart lib/features/platform/resort_card.dart test/features/platform/pending_listings_test.dart test/features/platform/platform_screen_test.dart test/features/platform/resort_card_test.dart
git commit -m "feat(platform): review queue with approve and reject for resort applications

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
## Phase 3: Integration

### Task 9: Merge the tracks and verify end to end

**Track:** both. **Depends on:** Tasks 2–8.

**Files:**
- None created. This task only verifies; a fix belongs to the task that owns the file, and gets its own commit.

**Interfaces:**
- Consumes: everything above.
- Produces: a branch where the database and the app agree on names and shapes, with both suites green.

- [ ] **Step 1: Merge**

If the tracks ran in separate worktrees, merge the database branch and the app branch into the feature branch. The tracks own disjoint files, so no conflicts are expected between them. Against other gap-round projects on `feat/gaps`, expect and resolve these by keeping both sides:
- `supabase/tests/37_tenancy_isolation_test.sql`: other projects add allow-list names in the same array.
- `lib/core/errors.dart`: other projects add codes (P0033–P0041) next to `'P0040'`; P5 adds a readable P0021 message.
- `lib/data/models/outbox_message.dart`: P7 adds a `dry_run` status; keep it and keep `reservationId` nullable.
- `lib/features/platform/platform_screen.dart`, `resort_card.dart`: P8 adds a last-payment line; keep both.
- `lib/data/repositories/catalog_repository.dart`, Browse: if P11 replaced `properties()` with `search_resorts`, drop this plan's `.eq('status', 'active')` line (`search_resorts` already lists active resorts only).

- [ ] **Step 2: Check the migrations this one builds on**

Run: `ls supabase/migrations | tail -12` and `grep -ln "function public\.\(has_resort_role\|assert_resort_role\|set_resort_status\|platform_summary\)(" supabase/migrations/*.sql`
Expected: `0059_resort_self_listing.sql` sorts after every `0051`–`0058` present. For each of the four functions, the highest-numbered file before `0059` must be the one this plan copied from (`0043`, `0043`, `0045`, `0049`). If one is newer (for example P8's `0057` redefining `platform_summary`), copy that body into `0059` and re-apply only this plan's change (`where p.status not in ('archived', 'pending')`), then re-run Step 4. Also run `grep -n "add column" supabase/migrations/0060_*.sql 2>/dev/null | grep -i city` — if P11 adds `city` with a plain `add column`, change its line to `add column if not exists` in P11's file (0059 runs first and has already added it).

- [ ] **Step 3: Check the contract by name**

Run: `grep -n "rpc('\|'p_[a-z_]*'" lib/data/repositories/listing_repository.dart`
Expected: the RPC names `apply_for_listing`, `my_listing_applications`, `listing_setup_status`, `submit_listing_for_review`, `platform_listing_applications`, `approve_listing`, `reject_listing`, and the parameter names `p_name`, `p_city`, `p_address`, `p_contact_phone`, `p_description`, `p_tier`, `p_property`, `p_reason`. Each must match a signature in `0059_resort_self_listing.sql` (`grep -n "create or replace function public\.\(apply_for_listing\|my_listing_applications\|listing_setup_status\|submit_listing_for_review\|platform_listing_applications\|approve_listing\|reject_listing\)" -A12 supabase/migrations/0059_resort_self_listing.sql`). The JSON keys read by `ListingApplication.fromJson`, `ListingSetup.fromJson` and `PendingListing.fromJson` must equal the OUT columns pinned in 49's contract section. Also run `grep -n "property-photos" lib/data/repositories/property_photos_repository.dart supabase/migrations/0059_resort_self_listing.sql supabase/config.toml` and check the bucket name matches in all three.

- [ ] **Step 4: Run the full suites**

Run: `supabase db reset && supabase test db`, then `flutter test`, then `flutter analyze`
Expected:
- pgTAP: 49 at 109/109; 37, 36, 38, 41 and every other file as in the Task 1 Step 1 baseline (the three time-of-day failures only between 00:00 and 05:30 IST).
- Flutter: all tests pass, with the count equal to the baseline plus the tests this plan added.
- Analyzer: no issues beyond the 2 baseline infos.

- [ ] **Step 5: Manual smoke test against the local stack**

Make Meera (a seeded customer with no membership) the platform admin for the test: `DB_URL="$(supabase status -o env | grep DB_URL | cut -d= -f2 | tr -d '"')"; psql "$DB_URL" -c "update public.profiles set role = 'platform_admin' where id = '10000000-0000-0000-0000-000000000006';"`. Then run `make run-web` and confirm:
1. Signed out, the welcome screen shows "List your resort"; tapping it opens sign-up. Sign up a new account `lina@example.com` / `password123` (name Lina Host): you land on `/list-your-resort`, not Browse.
2. Submit the empty form: every rule shows. Fill Resort name "Lina's Lakeside", City "Lonavala", Address "5 Lake Road, Lonavala", Contact phone "+91 98765 43210", a 20+ character description, Plan "Pro — ₹7,999/month", and tap Apply once: you land on `/owner` with "Finish setting up Lina's Lakeside" and "0 of 6 done".
3. Browse (the Browse tab) does not list Lina's Lakeside. In a private window (signed out), open `/property/<its id>` (the id is in the URL of `/admin/units/<id>` from Pricing): it shows not found / no data, and no booking is possible.
4. Work the checklist: Add photos → Add photo (upload any jpg; it appears in the grid and survives a reload); Add at least one unit → add "Tent 1"; Set rates → Tent 1 → Rates → add a base rate; Payment settings → tick UPI → Save; Cancellation policy → add 7 days / 100%; GSTIN and tax → `29ABCDE1234F1Z5` → Save. After each, the row ticks when you come back. "6 of 6 done"; tap Submit for review: "Submitted for review." and "Submitted for review on <today>…".
5. `psql "$DB_URL" -At -c "select template, recipient, status from public.outbox where reservation_id is null order by created_at;"` prints `listing_submitted|lina@example.com|pending` (or `dry_run` if P7 has landed and runs without keys).
6. Sign in as `meera@example.com` / `password123`: `/platform` shows "Waiting for review" 1 and Lina's Lakeside with a "Pending review" chip and no Suspend or Change plan buttons. Tap "Pending review": the application card shows Lina, the phone, the description and six checks. Approve → confirm: the queue empties, the resort's chip turns Active, and Active subscriptions counts it as a trial.
7. Sign out and browse as a guest: Lina's Lakeside is listed, with the uploaded photo on its card.
8. Sign up a second account `omar@example.com`, apply for "Omar's Orchard" (any valid details), then as Meera reject it with "Photos do not match the address.". As Omar, open the account sheet → List your resort: "Earlier applications" shows "Not approved: Photos do not match the address." above a fresh form, and a new application goes through.
Afterwards, `supabase db reset` restores the seed.

If Task 2 used the policy-check fallback for storage, step 4's upload through the app (which goes through the Storage API, not SQL) is the behavioural check of the owner's insert path; the stranger case stays covered by the policy-text assertions.

- [ ] **Step 6: Commit any fixes**

For each fix, run `git add <the fixed files>` and then `git commit -m "fix(listing): <what was wrong>"` with the blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` at the end of the message. If nothing needed fixing, there is nothing to commit.

---

## Self-Review

**1. Spec coverage**

| Spec requirement | Task |
|---|---|
| Status `pending`, hidden from guests, unbookable (decisions 1, 6) | 1 (check), 2 (helpers, anon/guest/quote/hold tests) |
| "List your resort" on welcome screen and account menu (decision 2) | 5 |
| `apply_for_listing`: fields, pending property, owner, 30-day trial of chosen tier, one open application (decisions 2, 8, 9, 18, 19, 21) | 1 (signature, index), 2 |
| `my_listing_applications`, rejection visible after archiving (decision 15) | 1 (signature), 2, 4 |
| Checklist on `/owner` with six items, links, ticks, Submit (decisions 3, 10, 11) | 3 (server), 6 (Photos), 7 (card) |
| Checklist rules incl. inactive units, override-only rates, GSTIN format (decision 10) | 3 |
| Submit owner-only, idempotent, audited, emailed (decisions 5, 11, 16) | 3 |
| Console Pending filter and count card (decision 4) | 8 |
| Approve → active, re-check, trial restart, audit, email (decisions 4, 9, 12) | 4 (server), 8 (UI) |
| Reject with reason → archived, reason stored and shown, audit, email (decisions 4, 12, 15) | 4 (server), 5 (shown), 8 (UI) |
| Suspend/Reactivate refuse pending; console hides buttons (decision 13) | 2, 8 |
| Pending counts for nothing in `platform_summary` (decision 14) | 2, 4 |
| Outbox rows without reservation; three templates; applicant email (decision 16) | 1 (nullable), 3, 4 |
| Photos bucket, policies, Photos screen, Settings tile, 10-photo limit (decision 17) | 2 (storage), 1 (repository), 6 |
| `city`, `contact_phone` columns (decision 18) | 1 |
| P0040 and exact messages; `ListingBlocked` (decision 20) | 1 (mapping), 2–4 (server), 5, 7, 8 (shown) |
| Platform admin cannot apply, `/list-your-resort` is `/404` for them (decision 21) | 2, 5 |
| `?next=` hand-off with allow-list (decision 22) | 5 |
| After applying, refetch, select, open `/owner` (decision 23) | 5 |
| Browse lists only active resorts (decision 24) | 5, 9 (manual) |
| Console lists undecided only, submitted first (decision 25) | 4, 8 |
| Allow-list in 37 | 1 |
| Outbox model reservation nullable | 1 |

**2. Placeholder scan:** no "TBD", "TODO" or "similar to Task N". Every code step shows its code; every SQL test uses literal ids or captured `app.*` settings. The only conditional instruction is Task 2 Step 4's storage fallback, which gives the exact replacement assertions.

**3. Type consistency:**
- `ListingSource.apply(ListingInput) → Future<String>`, `myApplications() → Future<List<ListingApplication>>`, `setupStatus(String) → Future<ListingSetup>`, `submitForReview(String) → Future<void>` are the same in the interface, `ListingRepository`, `FakeListingSource` and the callers in Tasks 5 and 7.
- `ListingReviewSource.pendingListings()`, `approve(String)`, `reject(String, String)` match `FakeListingReviewSource` (`rejectCalls` as `(String, String)`) and `PendingListingCard` / `RejectListingDialog`.
- `PropertyPhotosSource.upload(String, {filename, bytes, contentType}) → Future<String>` and `setPhotos(String, List<String>)` match `FakePropertyPhotosSource` (`uploads` as `(String, String, int)`, `setCalls` as `(String, List<String>)`) and `PropertyPhotosScreen`.
- `listingSetupProvider` is `FutureProvider.autoDispose.family<ListingSetup, String>` in the repository, its test, the card and the owner-hub test; `myListingApplicationsProvider` is `FutureProvider.autoDispose<List<ListingApplication>>`; `pendingListingsProvider` is `FutureProvider<List<PendingListing>>`.
- OUT columns pinned in 49 (`property_id … rejection_reason`, `property_status … has_tax_details`, `property_id … has_tax_details`) are the keys `ListingApplication.fromJson`, `ListingSetup.fromJson` / `setupFlagsFromRow` and `PendingListing.fromJson` read.
- `redirectFor(..., String? next)`, `postSignInPath(Uri)`, `LoginScreen({String? next})`, `SignupScreen({String? next})` agree between `router.dart`, the auth screens and their tests.
- `SetupChecklistCard({propertyId, resortName, onOpenStep})` and `OpenSetupStep` agree between the card, `owner_home_screen.dart` and the tests; `PropertyPhotosScreen({propertyId, pickPhoto})` and `PickedPhoto` agree between Tasks 6 and 7.
- The P0005 and P0040 messages in Global Constraints are the literal strings in the SQL, the validators, and the tests.
- Widget keys listed in each task's Produces block are each set in exactly one widget.

**4. Review Focus:** each line has a test in its owning task — 1 in Tasks 1 (index), 2 (second apply → P0040) and 5 (double tap → one call); 2 in Tasks 4 (approve re-checks) and 7 (refetch on return); 3 in Tasks 4 (archived application readable, re-apply) and 5 (reason above a fresh form); 4 in Task 2 (anon and guest see nothing, P0022 on quote and hold) plus Task 9's manual Browse check; 5 in Task 5 (router `next`, login `next`, welcome, links, allow-list). Inputs the spec implies that are covered elsewhere:
- Spaces and dashes in the phone, lower-case GSTIN, a name that needs trimming: Task 2 (stored normalised), Task 3 (lower-case GSTIN counts), Task 1 (validators).
- A taken resort name: Task 2 (numbered slug).
- An owner who is also an admin elsewhere, or a staff member, applying: allowed (Task 5 router test); the server treats every signed-in non-platform user the same (Task 2).
- A resort approved while its owner has the app open: Task 7 (live state with Refresh).
- A photo upload that fails: Task 6 (message shown, list unchanged).
