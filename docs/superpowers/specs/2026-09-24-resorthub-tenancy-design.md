# ResortHub Tenancy Foundation — Design

## Why

The product is now **ResortHub**: a multi-resort platform where
independent resort owners run their business, and guests book any resort
from one account. Pasala Resorts becomes one resort on it.

The database already models several properties (`properties`, and 15
tables carrying `property_id`), but everything above it assumes one
business:

- `profiles.role` is global. `is_admin()`, `is_staff_or_above()` and
  `current_role()` (`0002_profiles.sql`) grant a role across *every*
  property, so an admin of one resort can read and write another's
  bookings, guests and finances.
- 24 of the 32 tables have no `property_id` of their own, and 8 of them
  (coupons, outbox, outbox_templates, staff_shifts, leave_requests,
  attendance_records, tasks, audit_log) have no path to a property at all.
- The app routes by global role and sends guests straight to the single
  property (`browse_screen.dart:48`, per the 2026-08-13 single-property
  onboarding spec, which this supersedes).

Closed PR #12 (commit `806625d` on `bharath-vsp:feat/luxury-ui-redesign-and-requirements`)
prototyped ResortHub on a client-side mock store with no real isolation.
This spec builds the part that everything else depends on: real per-resort
isolation on the existing Supabase backend.

## Decomposition

ResortHub is split into sub-projects, each with its own spec, plan and
implementation. This spec covers **only #1**.

1. **Tenancy foundation (this spec):** per-resort memberships, per-resort
   data rules, Pasala migrated in as resort #1, app scoped to a current
   resort, minimal platform screen.
2. **Guest discovery:** multi-resort browse, search, filters, location.
3. **Platform console:** full resort onboarding and owner management.
4. **Subscriptions and platform billing.**
5. **Extras:** salary disbursement, promotional messaging, AI assistant.

## Scope decisions

- **Ownership model: independent owners (SaaS).** Each resort's data is
  walled off from every other resort.
- **Isolation approach: shared tables, row-level.** Every resort-owned row
  carries `property_id`; row-level security and every `security definer`
  function check the caller's role *at that row's resort*. Schema-per-resort
  and project-per-resort were rejected: both fight Supabase's tooling and
  break cross-resort guest accounts and discovery.
- **Platform admin sees summaries only.** Resort list, status, owner
  contact, booking counts and revenue totals. No guest details, bookings,
  expenses or staff records, and no row access to resort tables.
- **Guest accounts are global.** One login books any resort. A resort sees
  a guest's profile only through that guest's reservations at the resort.
- **Suspended resorts:** hidden from guest browse, read-only for their
  staff; guests keep seeing their existing bookings there and can cancel
  them under that resort's refund rules.
- **`properties` keeps its name.** Renaming to `resorts` would touch every
  migration, repository and test for no functional gain. The UI says
  "Resort".
- **"Incharge" is the existing `staff` role**, labelled "Staff / Incharge"
  in the UI. No new role.
- **No redesign of existing screens.** `/owner`, `/admin` and `/staff` gain
  resort scoping only.
- **No in-app account creation.** Creating `auth.users` rows needs the
  service-role key, which must never ship in the client (unchanged from
  `0019_user_admin.sql`). People sign up at `/signup`; owners and the
  platform admin then attach existing accounts by email.

## Data model

### Resorts

`properties` gains:

```sql
status text not null default 'active'
  check (status in ('active','suspended','archived'))
```

Pasala's existing row becomes resort #1 with `status = 'active'`.

### Roles

- `public.user_role` is replaced by `public.platform_role` with values
  `customer` and `platform_admin`; `profiles.role` uses it.
- New enum `public.resort_role`: `owner`, `admin`, `staff`, `accountant`.
- New table:

```sql
create table public.resort_members (
  property_id uuid not null references public.properties(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  role        public.resort_role not null,
  created_at  timestamptz not null default now(),
  primary key (property_id, user_id)
);
create index on public.resort_members (user_id);
```

- One person may hold memberships at several resorts, with one role per
  resort.
- Migration of existing roles, all attached to Pasala:
  `super_admin` → `owner`, `admin` → `admin`, `staff` → `staff`,
  `accountant` → `accountant`. Each of those profiles then gets
  `role = 'customer'`.
- Nobody becomes `platform_admin` by migration. It is granted with a
  one-off SQL statement, documented in the README.

### `property_id` on every resort-owned table

Every resort-owned table gets `property_id uuid not null references
public.properties(id)` with an index.

| Group | Tables | How `property_id` is filled |
|---|---|---|
| Already present | activities, expenses, food_activity_sales, food_categories, notification_settings, refund_rules, slot_types, units | unchanged |
| Derivable from a parent | reservations (from unit), payments, food_orders, activity_bookings, coupon_redemptions, reviews, service_requests, maintenance_issues, unit_calendar_events (from reservation); food_items (from food category); food_order_items (from order); rate_rules, ical_feeds, ical_export_tokens (from unit) | backfilled from the parent; a `before insert` trigger copies it from the parent on new rows |
| No link today | coupons, outbox, outbox_templates, staff_shifts, leave_requests, attendance_records, tasks, audit_log | backfilled to Pasala; supplied by the caller on new rows |

- For the derivable group, a `before insert or update` trigger rejects any
  row whose `property_id` differs from its parent's (new error `P0021
  resort_mismatch`), so a child can never be attached across resorts.
- `outbox_templates.property_id` is nullable: rows with no resort are the
  platform defaults, and a resort's own row with the same key overrides
  one.
- `audit_log.property_id` is nullable, for platform-level events such as
  `set_resort_status`.

### Global data

- `profiles` stays global. A resort member may read a guest's profile only
  when the guest has a reservation at that resort.
- Reviews remain publicly readable, now filtered by resort.

## Access rules

### Helper functions

All `stable`, `security definer`, `set search_path = public, pg_temp`:

- `is_platform_admin() returns boolean`
- `resort_role(p_property uuid) returns public.resort_role` — the caller's
  role at that resort, or null.
- `has_resort_role(p_property uuid, p_write boolean, variadic p_roles public.resort_role[]) returns boolean`
  — true when the caller holds one of `p_roles` at `p_property` and the
  resort is `active`, or is `suspended` and `p_write` is false.

`is_admin()`, `is_staff_or_above()` and `current_role()` are **dropped** in
the final migration of this project, so any caller that was missed fails
loudly instead of silently granting access to every resort.

### Policy pattern

For each resort-owned table:

- **Read:** `has_resort_role(property_id, false, <table's reader roles>)`,
  or the guest's own rows where the table has them (reservations,
  payments, food orders, activity bookings, service requests, reviews,
  maintenance issues they reported).
- **Write:** `has_resort_role(property_id, true, <table's writer roles>)`,
  keeping each table's existing role split. Example — expenses: owner,
  admin and accountant read; owner and admin write.
- **Guest-facing catalog** (properties, units, slot types, rate rules,
  activities, food categories and items, reviews): readable by anyone when
  the resort is `active`, and additionally by members of that resort.
- **Guest's own rows at a suspended resort** stay readable and
  cancellable.
- **Platform admin:** no policy grants it row access to any resort-owned
  table.

### `security definer` functions (72 today)

Every existing function is rewritten so that it:

1. derives the resort from its inputs (for example the reservation's
   `property_id`), or takes a required `p_property_id`;
2. checks the caller's role at that resort before doing anything, raising
   `P0020 not_a_member` when there is none, or `P0022 resort_suspended`
   when the function writes and the resort is suspended.

Reports and dashboard summaries (`report_*`, owner and stay dashboard
summaries, staff performance) take a required `p_property_id`.

`list_profiles` and `set_user_role` are replaced by:

- `list_resort_members(p_property uuid)` — owner and admin.
- `add_resort_member(p_property uuid, p_email text, p_role public.resort_role)`
  — owner only; the email must belong to an existing account.
- `set_member_role(p_property uuid, p_user uuid, p_role public.resort_role)`
  and `remove_resort_member(p_property uuid, p_user uuid)` — owner only.
  Both refuse to leave a resort with no owner, using the same race-safe
  locking as the last-super-admin guard in `ecd7182`.

### Platform functions (platform admin only)

- `platform_resorts()` — per resort: id, name, status, owner emails,
  created date, booking count and revenue for the last 30 and 365 days.
  No guest data.
- `set_resort_status(p_property uuid, p_status text)` — writes an
  `audit_log` row.
- `create_resort(p_name text, p_owner_email text)` — creates the property
  and an `owner` membership for an existing account.

### Error codes

| Code | Meaning |
|---|---|
| `P0020` | `not_a_member` — caller has no suitable role at that resort |
| `P0021` | `resort_mismatch` — child row's resort differs from its parent's |
| `P0022` | `resort_suspended` — write attempted at a suspended resort |
| `P0023` | `last_owner` — change would leave a resort with no owner |

All four are added to `mapPostgrestError` (`lib/core/errors.dart`).

## Migrations

- `0043_resort_tenancy.sql` — enums, `properties.status`, `resort_members`,
  `property_id` columns, backfill to Pasala, `not null`, parent-match
  triggers, role move into memberships, helper functions.
- `0044_resort_policies.sql` — drop and recreate every policy on
  resort-owned tables with the pattern above.
- `0045_resort_functions.sql` — rewrite the existing `security definer`
  functions; add the member-management and platform functions.
- `0046_drop_global_role_helpers.sql` — drop `is_admin()`,
  `is_staff_or_above()`, `current_role()` and the old `user_role` enum.

Each migration applies cleanly with `supabase migration up` on a database
at `0042`, and `supabase db reset` rebuilds from zero.

## App changes

### Signed-in user and current resort

- `AppUser` gains `isPlatformAdmin` and
  `memberships: List<ResortMembership>` (`propertyId`, `resortName`,
  `role`), loaded together with the profile.
- New `currentResortProvider`: the selected membership, remembered on the
  device (`shared_preferences`), falling back to the only membership when
  there is one. A remembered resort the user no longer belongs to is
  discarded.
- Every repository method that touches resort data takes the resort id as
  an explicit parameter, and its providers are families keyed by it, so
  switching resorts cannot show another resort's cached data.

### Routing (`lib/core/router.dart`)

`landingPathFor`:

| User | Lands on |
|---|---|
| Platform admin | `/platform` |
| 2+ memberships, no valid remembered resort | `/choose-resort` |
| Owner at current resort | `/owner` |
| Admin at current resort | `/admin` |
| Accountant at current resort | `/staff/dashboard` |
| Staff at current resort | `/staff` |
| Everyone else | `/` |

`redirectFor` checks the membership role at the current resort instead of
the global role. It remains UX only; the database enforces access.

A resort switcher appears in the staff app bars when the user has 2 or
more memberships.

### Screens

- `/owner`, `/admin`, `/staff` and their sub-screens: resort scoping only.
- `/admin/users` is replaced by **Team** at `/owner/team` (owner only):
  list members, add an existing account by email with a role, change a
  role, remove a member.
- `/choose-resort`: the user's memberships as a list; picking one sets
  `currentResortProvider` and continues to that role's landing path.
- `/platform` (platform admin only): resort list from `platform_resorts()`,
  Suspend / Reactivate actions, and a New resort form calling
  `create_resort`.
- **Guests:** `BrowseScreen` drops the single-property redirect and lists
  all active resorts, keeping the amenity chips. My Bookings and My Stay
  show the resort name on each booking.

### Branding

- App title and welcome screen become "ResortHub" with neutral copy.
  Pasala's photos move to Pasala's resort page.
- Fix the welcome screen rendering a strip of the hero image at the left
  edge.

### Errors

`P0020` shows "You no longer have access to this resort", clears the
remembered resort and re-runs `landingPathFor`. `P0022` shows "This resort
is suspended — changes are disabled".

## Testing

- **pgTAP leak suite** `supabase/tests/tenancy_isolation.sql`:
  - seeds resorts A and B, each with an owner, admin, staff member,
    accountant, and a guest with bookings, orders and requests;
  - as each of A's roles, asserts every resort-owned table returns no B
    rows and every write targeting B fails;
  - asserts every `security definer` function called with B's ids raises
    `P0020`;
  - asserts the platform admin reads no resort-owned rows and gets
    `platform_resorts()`;
  - asserts suspended-resort behaviour: hidden from anonymous browse,
    staff writes through functions raise `P0022`, direct table writes are
    rejected by row security, and the guest still reads and cancels.
- **Catalog guards** (same suite):
  - every table with a `property_id` column has row security enabled, and
    each of its policies references `has_resort_role` or the guest's
    ownership;
  - every `security definer` function in `public` appears on a reviewed
    allow-list in the test file, so a new function fails the suite until
    someone reviews it.
- **Existing pgTAP suites** updated for memberships and still passing.
- **Flutter:**
  - router role-matrix tests rewritten around memberships, including the
    multi-membership and platform-admin cases;
  - each screen reading resort data gets a test with a fake current
    resort;
  - repository tests assert the resort id reaches the RPC or query;
  - `BrowseScreen` test for listing several resorts.

## Out of scope

Guest search, filters and location (#2); owner self-signup, invitations
by email for people without an account, and a full platform console (#3);
subscriptions and billing (#4); salary disbursement, promotional
messaging, AI assistant (#5); visual redesign of existing staff screens.
