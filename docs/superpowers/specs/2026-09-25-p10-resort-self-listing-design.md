# Resort Self-Listing (P10) — Design

## Why

ResortHub is meant to host many independent resorts, but today a resort can
only come into existence one way: the platform admin types its name and an
owner's email into "Add resort" on `/platform` (`create_resort`,
`0049_subscriptions.sql`). A resort owner who finds the app has no way to
ask to be listed, and the platform admin has no queue of applications to
review.

Today:
- `properties.status` is `active`, `suspended` or `archived`
  (`0043_resort_tenancy.sql`). Guests see only `active` resorts
  (`properties_read`, `units_read`, `rate_rules_read` and friends in
  `0044_resort_policies.sql`), and every guest booking path refuses a
  resort that is not `active` with P0022 (`search_availability`,
  `get_quote`, `create_hold`, `confirm_booking`, `place_food_order`,
  `book_activity`, `create_service_request` in `0045_resort_functions.sql`).
- `has_resort_role(p, p_write, ...)` and `assert_resort_role(...)` (0043)
  let members write only at an `active` resort, and read at an `active` or
  `suspended` one.
- `properties.status` changes only through `set_resort_status` (0045),
  guarded by `properties_guard_status` (0044), and only the platform admin
  calls it.
- `resort_subscriptions` (0049) holds one plan per resort; trials exist.
- The owner hub `/owner` (`lib/features/owner/owner_home_screen.dart`) and
  Settings (`owner_settings_screen.dart`) already link to every screen a
  new resort needs: Farmhouse information (`PropertyFormScreen`), units and
  rates (`UnitsScreen` → `/admin/rates/:unitId`), Taxes
  (`TaxSettingsScreen`), Payment configuration (`PaymentSettingsScreen`)
  and Cancellation policy (`CancellationPolicyScreen`). Nothing uploads
  property photos: `properties.images` is only ever set by hand in SQL,
  although `PropertyCard` on Browse already shows the first image.
- The notification outbox (`0017_outbox.sql`) only carries guest messages
  about a reservation: `outbox.reservation_id` is `not null`.
- `properties` has no `city` and no contact phone.
- The welcome screen (`lib/features/auth/welcome_screen.dart`) offers only
  Sign In and Sign Up. The account sheet (`showAccountSheet` in
  `lib/features/shell/app_shell.dart`) offers only Sign out.

## Decisions (accepted by the product owner, 2026-09-25)

1. **Resort status gains `pending`.** A pending resort is hidden from guests
   exactly like a suspended one, and cannot take bookings. Its owner can set
   it up.
2. **Public "List your resort" entry** on the welcome screen and in the
   account menu. A signed-in user fills resort name, city, address, contact
   phone and a short description; the security definer function
   `apply_for_listing` creates a pending property with the caller as owner
   and a `resort_subscriptions` row on a **30-day trial of the chosen
   tier**. **One pending application per user.**
3. **Setup checklist on `/owner` while pending:** photos, at least one unit,
   rates, payment settings (advance %), cancellation policy, GSTIN/tax. Each
   item links to its screen and ticks when done. **"Submit for review"**
   when complete.
4. **Platform console:** a "Pending" filter and a count card; **Approve**
   (→ `active`) and **Reject with a reason** (→ `archived`, reason stored,
   the owner sees it).
5. **Audit rows** for every step. **Notifications to the owner through the
   outbox** (delivered by P7 once it lands).

Settled here where the decision was silent (recorded judgment calls):

6. **Pending is writable by members.** `has_resort_role` and
   `assert_resort_role` treat `pending` like `active` for writes and reads.
   Bookings stay impossible because every guest path already demands
   `status = 'active'`; no policy is widened for guests or anon.
7. **Application state lives in a new platform-owned table**,
   `listing_applications`, not in `properties` columns: `properties_update`
   lets an owner edit their own row, so a `submitted_at` or `decision`
   column there could be forged. The table has no write grant; only the
   definer functions write it.
8. **"One pending application per user"** means one application with no
   decision yet (set up or submitted). A partial unique index enforces it,
   and `apply_for_listing` takes a per-user advisory lock so two taps at
   once give P0040, not a raw unique violation. An approved or rejected
   application does not count, so a rejected applicant can apply again.
9. **The applicant chooses the tier** on the form (Starter / Pro /
   Enterprise, default Starter, monthly prices shown). The trial ends
   today + 30 days (Asia/Kolkata). **Approval restarts the trial** at
   approval day + 30 days if the subscription is still a trial, so review
   time does not eat the trial.
10. **Checklist "done" rules** (computed on the server, never stored):
    - Photos: `properties.images` has at least one URL.
    - Units: at least one active unit.
    - Rates: at least one active unit, and every active unit has a
      `base` or `weekend` rate rule (an `override` alone is a date range,
      not a standing price).
    - Payment settings: `payment_display_methods` is not empty (the
      Payment configuration screen saves the advance % and the methods
      together; `advance_pct` always has a value, so the methods are the
      signal that the owner saved it).
    - Cancellation policy: at least one `refund_rules` row.
    - GSTIN and tax: `gstin` is a well-formed 15-character GSTIN
      (`^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$`, case-insensitive).
      ResortHub requires a GSTIN to list; invoices (P2) print it.
11. **Only the owner submits**; owners and admins can read the checklist.
    Submitting twice is a no-op.
12. **Approve needs a submitted application whose checklist is still
    complete** (an owner could delete their photos after submitting).
    **Reject works any time before a decision**, including before
    submission (spam). A decided application cannot be decided again.
13. **Suspend/Reactivate cannot bypass review:** `set_resort_status`
    refuses a pending resort with P0040, and the console hides those
    buttons (and Change plan) on a pending resort's card.
14. **Pending resorts count for nothing** in `platform_summary`
    (Subscribed, Active, Trials, MRR), like archived ones. The "Pending"
    count card counts submitted applications waiting for a decision.
15. **Rejected means archived.** The rejected resort and its data stay
    archived (the platform admin can still reactivate it by hand later).
    The applicant keeps no membership access to an archived resort, so the
    reason is shown through `my_listing_applications()`, which reads by
    applicant, not by membership, on the "List your resort" page — and in
    the rejection email.
16. **Notifications** are email only, from three platform default
    templates (`property_id` null): `listing_submitted`,
    `listing_approved`, `listing_rejected`. The recipient is the
    applicant's sign-in email. `outbox.reservation_id` becomes nullable;
    listing rows carry `property_id` and no reservation. The resort's
    guest-notification toggles (`notification_settings`) do not apply to
    these platform-to-owner account messages. Applying sends nothing (the
    user is in the app at that moment).
17. **Photos:** a new public Storage bucket `property-photos`, objects at
    `{property_id}/{file}`. The resort's owners and admins may upload and
    delete there (writable at `active` and `pending` resorts). A new
    Photos screen (reachable from the checklist and from Settings) uploads
    with `image_picker` and appends the public URL to `properties.images`
    (at most 10). Removing a photo removes its URL; the object is left in
    the bucket.
18. **New columns** `properties.city` and `properties.contact_phone`
    (`add column if not exists`, so P11, which searches by city, reuses the
    same column). The phone is stored with spaces and dashes removed.
19. **Validation** (server P0005 messages, mirrored in the form):
    name 2–80 characters, city 2–60, address 5–300, phone 10–13 digits
    with an optional leading `+`, description 20–500, tier required,
    rejection reason 5–500.
20. **Errors:** P0040 (`listing_blocked`) for listing-state refusals, with a
    message written for the reader that the app shows verbatim; P0005 for
    bad input; P0008 when a signed-out user or the platform admin applies,
    or anyone but the platform admin reviews; P0002 for an unknown
    application; P0020 from `assert_resort_role`.
21. **The platform admin cannot apply** (P0008); `/list-your-resort` is
    `/404` for them. They keep "Add resort".
22. **Sign-in hand-off:** the welcome button opens
    `/signup?next=/list-your-resort`; login and sign-up (and the router's
    pre-auth redirect) go to `next` after sign-in only when it is on an
    allow-list containing `/list-your-resort`. A signed-out visit to
    `/list-your-resort` goes to `/login?next=/list-your-resort`.
23. **After applying** the app refetches the user, selects the new resort
    and opens `/owner`, where the checklist is.
24. **Browse lists only active resorts** (`CatalogRepository.properties()`
    filters `status = 'active'`), so an applicant does not see their own
    pending resort among bookable ones.
25. **The console lists undecided applications only**; decided history is
    in `audit_log`.

## Data model — `supabase/migrations/0059_resort_self_listing.sql`

- `properties_status_check` is replaced:
  `check (status in ('pending','active','suspended','archived'))`.
- `properties` gains `city text` and `contact_phone text`
  (`add column if not exists`).
- Table `public.listing_applications` (one row per applied resort):
  - `property_id uuid primary key references properties(id) on delete cascade`
  - `applicant_id uuid not null references profiles(id) on delete cascade`
  - `tier public.subscription_tier not null references subscription_plans(tier)`
  - `submitted_at timestamptz`
  - `decision text check (decision in ('approved','rejected'))`
  - `decided_at timestamptz`, `decided_by uuid references profiles(id) on delete set null`
  - `rejection_reason text`
  - `created_at timestamptz not null default now()`
  - `check ((decision is null) = (decided_at is null))`
  - `check (decision is distinct from 'rejected' or length(btrim(coalesce(rejection_reason,''))) > 0)`
  - unique index `listing_applications_one_open_per_user on (applicant_id) where decision is null`
  - RLS on; `select` granted to `authenticated` with policy
    `applicant_id = auth.uid() or has_resort_role(property_id, false, 'owner','admin')`;
    no write grant or policy.
- `outbox.reservation_id` drops `not null` (the existing
  `outbox_fill_property` trigger already leaves a row with no reservation
  alone; `outbox.property_id` stays `not null`).
- Three platform default `outbox_templates` rows (email): `listing_submitted`,
  `listing_approved`, `listing_rejected`, placeholders `{{owner_name}}`,
  `{{property_name}}`, `{{trial_ends_on}}`, `{{reason}}`.
- Storage bucket `property-photos` (public, 10 MiB, png/jpeg/webp), inserted
  by the migration (`on conflict do nothing`) and declared in
  `supabase/config.toml`; policies `property_photos_insert`,
  `property_photos_read`, `property_photos_delete` on `storage.objects` for
  `authenticated`: the first path segment is a property id where
  `has_resort_role(id, true, 'owner','admin')` (read uses `false`).

## Functions

Changed (copied from their latest definitions):
- `has_resort_role` / `assert_resort_role` (0043): `pending` counts as
  `active`.
- `set_resort_status` (0045): refuses a pending resort (P0040
  "Approve or reject this resort instead.").
- `platform_summary` (0049, or a later redefinition if one exists on the
  integration branch): `where p.status not in ('archived','pending')`.

New security definer functions (`search_path = public, pg_temp`, revoked
from `public` and `anon`, granted to `authenticated`, added to the allow-list
in `37_tenancy_isolation_test.sql`):
- `apply_for_listing(p_name text, p_city text, p_address text,
  p_contact_phone text, p_description text,
  p_tier public.subscription_tier default 'starter') returns uuid` — P0008
  for no user or the platform admin; P0005 validation; P0040 "You already
  have a resort waiting for review." Creates the pending property (slug as
  `create_resort` makes it), the owner membership, the trial subscription
  and the application; audit rows `listing:apply` (entity `listing`) and
  `subscription:create` (entity `subscription`).
- `my_listing_applications() returns table (property_id uuid, name text,
  city text, tier subscription_tier, property_status text, created_at
  timestamptz, submitted_at timestamptz, decision text, decided_at
  timestamptz, rejection_reason text)` — the caller's applications, newest
  first.
- `listing_setup_status(p_property uuid) returns table (property_status
  text, submitted_at timestamptz, has_photos boolean, has_unit boolean,
  has_rates boolean, has_payment_settings boolean, has_cancellation_policy
  boolean, has_tax_details boolean)` — owner or admin (read).
- `submit_listing_for_review(p_property uuid) returns void` — owner
  (write); P0040 "This resort is not waiting for review." / "Finish the
  setup checklist before submitting."; sets `submitted_at`, audit
  `listing:submit`, queues `listing_submitted`.
- `platform_listing_applications() returns table (property_id uuid, name
  text, city text, address text, contact_phone text, description text,
  applicant_email text, applicant_name text, tier subscription_tier,
  created_at timestamptz, submitted_at timestamptz, has_photos boolean,
  has_unit boolean, has_rates boolean, has_payment_settings boolean,
  has_cancellation_policy boolean, has_tax_details boolean)` — platform
  admin only (P0008); undecided applications, submitted first (oldest
  submission first), then the rest by `created_at`.
- `approve_listing(p_property uuid) returns void` — platform admin; P0002
  unknown; P0040 "This application has already been decided." / "This
  resort has not been submitted for review yet." / "The setup checklist is
  no longer complete."; status → `active`, decision `approved`, trial
  restarted; audit `status:pending->active` (entity `property`),
  `listing:approve`, and `subscription:trial-restart` when the trial moved;
  queues `listing_approved`.
- `reject_listing(p_property uuid, p_reason text) returns void` — platform
  admin; P0005 reason; P0002; P0040 decided; status → `archived`, decision
  `rejected` with the reason; audit `status:pending->archived` and
  `listing:reject`; queues `listing_rejected`.

Internal plain (not definer) helpers, revoked from `public`, `anon` and
`authenticated`, called only from the definers above:
`resort_slug_for(p_name text) returns text`,
`listing_setup_flags(p_property uuid) returns table (has_photos …
has_tax_details)`, `enqueue_listing_message(p_property uuid, p_template
text) returns void`.

## App

- `lib/data/models/listing.dart`: `SetupStep` (photos, units, rates,
  payments, cancellation, tax) with title and hint; `ListingSetup`
  (`fromJson`, `done`, `complete`, `doneCount`); `ListingDecision`;
  `ListingApplication` (`fromJson`, `isOpen`, `statusLine`);
  `PendingListing` (`fromJson`, `submitted`, `setupComplete`);
  `ListingInput`; validators mirroring the server rules.
- `lib/data/repositories/listing_repository.dart`: `ListingSource`
  (`apply`, `myApplications`, `setupStatus`, `submitForReview`) and
  `ListingReviewSource` (`pendingListings`, `approve`, `reject`), both
  implemented by `ListingRepository`; providers
  `myListingApplicationsProvider`, `listingSetupProvider` (autoDispose
  family by property id), `pendingListingsProvider`.
- `lib/data/repositories/property_photos_repository.dart`:
  `PropertyPhotosSource` (`upload`, `setPhotos`).
- `lib/core/errors.dart`: P0040 → `ListingBlocked(message)`.
- `lib/data/models/outbox_message.dart`: `reservationId` becomes nullable.
- `/list-your-resort` (`lib/features/listing/list_your_resort_screen.dart`):
  the form (name, city, address, contact phone, short description, plan
  with monthly price, "30-day free trial. No payment needed now."), or,
  when the user has an open application, its status and "Continue setup";
  earlier applications with "Not approved: <reason>".
- Welcome screen: "List your resort" text button. Account sheet: "List
  your resort" tile.
- `/owner` while the current resort is pending: `SetupChecklistCard`
  (`lib/features/owner/setup_checklist_card.dart`) at the top — progress
  "x of 6 done", six rows with a done/not-done icon and text (not colour
  alone), each opening its screen and refreshing on return, and "Submit for
  review" (enabled only when complete) or "Submitted for review on <date>".
  When the resort turns out to be live already it says so and offers
  Refresh.
- `lib/features/owner/property_photos_screen.dart`: grid of photos with
  remove buttons, "Add photo" (disabled at 10). Also a "Photos" tile in
  Owner Settings.
- Platform console: a "Waiting for review" count card and a "Pending
  review" filter chip; with the filter on, the list shows
  `PendingListingCard`s (applicant, contact, description, plan, submission
  state, the six checklist items, Approve with confirmation, Reject with a
  required reason). Search applies to name, city and applicant email.
  `ResortCard` shows no status or plan buttons on a pending resort.
- Router: `/list-your-resort` inside the shell for any signed-in user but
  the platform admin; `postSignInPath` allow-list for `?next=`.

## Rules

- Every listing write goes through a definer function that derives the
  resort from the id it is given and checks the caller there; nothing is
  ever written at a client-supplied resort the caller does not own.
- No guest-facing policy or function is widened: pending stays invisible
  and unbookable to guests and anon.
- The platform admin still gets no row access to any resort-owned table;
  the console reads applications only through
  `platform_listing_applications()`.
- Every apply, submit, approve and reject writes `audit_log`.

## Testing

- pgTAP `supabase/tests/49_resort_self_listing_test.sql`: contract (table,
  columns, status check, nullable outbox reservation, signatures, grants,
  RLS on `listing_applications`, the one-open index); pending semantics
  (owner writes, anon sees nothing, `get_quote` / `create_hold` P0022);
  `apply_for_listing` (validation, P0008, P0040, rows and audit, slug
  suffix); `set_resort_status` P0040; `platform_summary` ignores pending;
  photo storage policies; checklist rules one by one (incl. inactive units
  and bad GSTIN); submit (role, incomplete, idempotent, outbox row);
  platform list (P0008, order, flags); approve (not submitted, incomplete,
  unknown, twice, trial restart, audit, outbox, now public); reject
  (reason, archived, visible to the applicant, re-apply, outbox, audit);
  internal helpers not executable by `authenticated`. The allow-list in
  `37` gains the seven functions.
- Flutter: models and validators; error mapping; provider keys; the list
  screen (form validation, apply call and navigation, open application,
  rejected history, plan prices); router rules and `next`; welcome and
  account sheet entries; checklist card (states, links, submit, submitted,
  live); photos screen (add, remove, limit, errors); console count card,
  filter, approve and reject dialogs; resort card on a pending resort.
  The Browse filter (a one-line query change) and a real photo upload are
  checked by hand against the local stack.

## Out of scope

Collecting subscription payment at sign-up (P8); document or KYC uploads;
editing city and contact phone after applying (P11 may add city to
property settings); showing uploaded photos in the property page gallery
(it stays on the bundled photos); deleting orphaned photo objects; an
account sheet for owners (their app bar has only Sign out); reopening a
rejected application (apply again instead); reminders for stale pending
applications; delivering the emails (P7).
