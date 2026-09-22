# Pasala Booking Core (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a multi-property farmhouse booking core — availability, server-side pricing, timed holds, confirmed bookings, and admin date blocking — as a single role-gated Flutter app on a local Supabase stack, where overlapping reservations are impossible at the database layer.

**Architecture:** Postgres owns all business logic. Bookings, admin blocks, and future OTA holds share one `reservations` table protected by a GiST exclusion constraint on `(unit_id, period)`, so concurrent conflicting writes fail with SQLSTATE `23P01` rather than silently oversell. Six `SECURITY DEFINER` RPC functions form the entire write surface; RLS governs reads. Flutter is a thin client: repositories wrap the Supabase SDK, widgets never import it, and no pricing arithmetic exists outside `get_quote`.

**Tech Stack:** Flutter 3.38.9 / Dart 3.10.8, Riverpod, go_router, freezed, supabase_flutter, Supabase CLI (local, Docker), Postgres 17 with `btree_gist` and `pg_cron`, pgTAP for database tests.

**Spec:** `docs/superpowers/specs/2026-07-28-pasala-booking-core-design.md`

## Global Constraints

- Flutter 3.38.9, Dart 3.10.8. Xcode 26.6 available; Docker running.
- All timestamps stored UTC. Display timezone `Asia/Kolkata`. Currency INR.
- Every reservation period is a `tstzrange`, half-open `[start, end)`.
- All RPC functions are `SECURITY DEFINER` with `SET search_path = public, pg_temp`. Caller identity always from `auth.uid()`; never trust a client-supplied user id.
- Widgets must never import `package:supabase_flutter`. Only files under `lib/data/repositories/` and `lib/core/supabase_client.dart` may.
- No pricing arithmetic in Dart. Totals are only ever displayed from a server-returned quote.
- Table names, column names, enum values, and function signatures are exactly as written in this plan. Do not rename.
- Secrets are never committed. Local anon key may appear in `.env.example` only.
- RLS is not sufficient on its own. This Supabase config does not auto-expose new tables to the Data API roles, so every table needs an explicit `grant` to `anon` and/or `authenticated` alongside its policies — otherwise it fails closed at the privilege layer with 42501 and the policies never run.
- TDD is mandatory: write the failing test, run it, watch it fail, then implement.
- In pgTAP, setting `request.jwt.claims` does NOT change the effective Postgres role. Any assertion meant to exercise a policy must pair `set local role authenticated;` with the claims line. `postgres` is a superuser and bypasses RLS, so an assertion left running as `postgres` passes while proving nothing. After any `set local role postgres;` block used for out-of-band counts, switch back before the next policy assertion.
- RLS filters rows; it does not raise errors. A DELETE or UPDATE matching no policy affects zero rows and returns success. Assert survival with an out-of-band count, not `throws_ok('42501')`. 42501 comes from the grant layer or from a WITH CHECK violation on INSERT/UPDATE.
- Commit at the end of every task with the message given in the task.

## File Structure

**Database** (`supabase/`)
- `config.toml` — CLI config; enables `pg_cron`.
- `migrations/0001_extensions_and_enums.sql` — extensions, enum types.
- `migrations/0002_profiles.sql` — `profiles`, signup trigger, role helpers.
- `migrations/0003_properties_units.sql` — `properties`, `units`, `slot_types`.
- `migrations/0004_rate_rules.sql` — `rate_rules` + `get_quote`.
- `migrations/0005_reservations.sql` — `reservations`, exclusion constraint, `availability` view, `search_availability`.
- `migrations/0006_booking_rpc.sql` — `create_hold`, `confirm_booking`, `cancel_booking`, `release_expired_holds`, `pg_cron` job.
- `migrations/0007_payments_audit.sql` — `payments`, `audit_log`, transition trigger.
- `seed.sql` — two properties, five units, rate rules, one account per role.
- `tests/*.sql` — pgTAP, one file per concern.

**Flutter** (`lib/`)
- `core/env.dart` — per-platform Supabase URL/key resolution.
- `core/supabase_client.dart` — SDK init and singleton.
- `core/errors.dart` — sealed `BookingFailure` + `mapPostgrestError`.
- `core/router.dart` — go_router with role-aware redirect.
- `core/theme/app_theme.dart` — Material 3 theme.
- `data/models/*.dart` — freezed models, one per entity.
- `data/repositories/*.dart` — one per aggregate; the only SDK consumers.
- `features/<name>/` — screens plus feature-local Riverpod providers.

Each repository owns one aggregate and exposes plain Dart types. Each feature folder owns its screens and providers, so a feature can be read without opening another.

---

### Task 1: Project scaffold and local Supabase stack

**Files:**
- Create: `pubspec.yaml` (via `flutter create`), `analysis_options.yaml`, `.env.example`, `supabase/config.toml` (via `supabase init`), `Makefile`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: a running local Supabase at `http://127.0.0.1:54321`, a Flutter package named `pasala`, and `make db-reset` / `make db-test` shortcuts used by every later task.

- [ ] **Step 1: Install the Supabase CLI**

```bash
brew install supabase/tap/supabase
supabase --version
```

Expected: a version prints. If Homebrew is unavailable, use `npx supabase` and prefix every later `supabase` command with `npx`.

- [ ] **Step 2: Scaffold the Flutter app in place**

The repository root already contains `docs/` and `.git`, so scaffold into `.`:

```bash
cd /Users/wiljans/vsp/pasala_farm
flutter create --org com.pasala --project-name pasala --platforms=android,ios,web .
```

- [ ] **Step 3: Add dependencies**

```bash
flutter pub add supabase_flutter flutter_riverpod go_router freezed_annotation json_annotation intl
flutter pub add --dev build_runner freezed json_serializable flutter_lints
```

- [ ] **Step 4: Initialise Supabase and start it**

```bash
supabase init
supabase start
```

Expected: prints `API URL: http://127.0.0.1:54321`, `DB URL`, `anon key`, `service_role key`. Record the anon key for Step 6.

- [ ] **Step 5: Configure the database and enable pg_cron**

Find the `[db]` section of `supabase/config.toml` and ensure it contains:

```toml
[db]
port = 54322
major_version = 17

[db.pooler]
enabled = false
```

`[experimental] enable_pg_cron` is **not** a valid key in Supabase CLI 2.110.0
and breaks `supabase db reset`. Enable the extension from migration zero
instead — `supabase/migrations/0000_enable_pg_cron.sql`:

```sql
-- pg_cron is preloaded by the local Postgres image, but the extension must
-- still be created. The `[experimental] enable_pg_cron` config key does not
-- exist in CLI 2.110.0, so this migration owns it.
create extension if not exists pg_cron;
```

The `0000_` prefix matters: migrations apply in lexicographic filename order,
and `0000_` sorts before the `0001_` file added in Task 2.

- [ ] **Step 6: Write `.env.example`**

```bash
# Local Supabase only. Never put production keys in this file.
# Host values are resolved per-platform in lib/core/env.dart:
#   web + iOS simulator -> 127.0.0.1
#   Android emulator    -> 10.0.2.2
#   physical device     -> your machine's LAN IP
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=<paste the anon key printed by `supabase start`>
```

- [ ] **Step 7: Extend `.gitignore`**

Append:

```
.env
supabase/.branches/
supabase/.temp/
ios/Pods/
```

- [ ] **Step 8: Write the `Makefile`**

```makefile
# .PHONY is required: `test` collides with the test/ directory Flutter
# generates, and Make would treat the target as up to date and skip it.
.PHONY: db-reset db-test test run-web run-android run-ios

ANON_KEY ?= $(shell supabase status -o env 2>/dev/null | grep ANON_KEY | cut -d= -f2 | tr -d '"')

db-reset:
	supabase db reset

db-test:
	supabase test db

test:
	flutter test

run-web:
	flutter run -d chrome --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=$(ANON_KEY)

run-android:
	flutter run -d emulator --dart-define=SUPABASE_URL=http://10.0.2.2:54321 --dart-define=SUPABASE_ANON_KEY=$(ANON_KEY)

run-ios:
	flutter run -d iPhone --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=$(ANON_KEY)
```

- [ ] **Step 9: Verify the toolchain**

```bash
flutter analyze
supabase status
```

Expected: analyze reports no issues; status lists running containers.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "chore: scaffold Flutter app and local Supabase stack"
```

---

### Task 2: Extensions, enums, and the pgTAP harness

**Files:**
- Create: `supabase/migrations/0001_extensions_and_enums.sql`, `supabase/tests/00_setup_test.sql`

**Interfaces:**
- Consumes: Task 1's local stack.
- Produces: enum types `user_role`, `booking_mode`, `slot_code`, `rate_kind`, `reservation_kind`, `reservation_status`, `payment_kind`, `payment_status`; extensions `btree_gist`, `pgcrypto`, `pg_cron`. Every later migration depends on these names.

- [ ] **Step 1: Write the failing test**

`supabase/tests/00_setup_test.sql`:

```sql
begin;
select plan(3);

select has_extension('btree_gist');

select enum_has_labels(
  'public', 'reservation_status',
  array['hold','pending_payment','confirmed','cancelled']
);

select enum_has_labels(
  'public', 'user_role',
  array['customer','staff','admin','accountant','super_admin']
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `supabase test db`
Expected: FAIL — `type "public.reservation_status" does not exist`.

- [ ] **Step 3: Write the migration**

`supabase/migrations/0001_extensions_and_enums.sql`:

```sql
create extension if not exists btree_gist;
create extension if not exists pgcrypto;
create extension if not exists pg_cron;

create type public.user_role as enum
  ('customer','staff','admin','accountant','super_admin');

create type public.booking_mode as enum ('nightly','slot','both');

create type public.slot_code as enum ('day','night','full_day');

create type public.rate_kind as enum ('base','weekend','override');

create type public.reservation_kind as enum ('booking','block','ota');

create type public.reservation_status as enum
  ('hold','pending_payment','confirmed','cancelled');

create type public.payment_kind as enum ('advance','balance');

create type public.payment_status as enum
  ('pending','succeeded','failed','refunded');
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `supabase db reset && supabase test db`
Expected: PASS, 3 of 3.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0001_extensions_and_enums.sql supabase/tests/00_setup_test.sql
git commit -m "feat(db): add extensions and enum types"
```

---

### Task 3: Profiles, roles, and role helper functions

**Files:**
- Create: `supabase/migrations/0002_profiles.sql`, `supabase/tests/01_profiles_test.sql`

**Interfaces:**
- Consumes: `user_role` from Task 2.
- Produces: table `public.profiles(id uuid pk, full_name text, phone text, role user_role, created_at)`; functions `public.current_role() returns user_role` and `public.is_staff_or_above() returns boolean`, used by every RLS policy in Tasks 4–8.

- [ ] **Step 1: Write the failing test**

`supabase/tests/01_profiles_test.sql`:

```sql
begin;
select plan(10);

select has_table('public','profiles','profiles table exists');
select has_function('public','current_role','current_role() exists');

-- signup trigger creates a customer profile
insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-1111-1111-1111-111111111111', 'a@example.com',
        '{"full_name":"Aa"}'::jsonb);

select is(
  (select role from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  'customer'::public.user_role,
  'signup defaults to customer'
);

select is(
  (select full_name from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'),
  'Aa',
  'full_name copied from metadata'
);

-- a customer cannot escalate their own role
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select throws_ok(
  $$update public.profiles set role = 'admin'
      where id = '11111111-1111-1111-1111-111111111111'$$,
  '42501',
  null,
  'customer cannot escalate own role'
);

-- Role-change authority: an admin must not be able to promote anyone,
-- including itself. This is the assertion whose absence let an
-- admin-to-super_admin escalation path ship green in an earlier draft.
reset role;
insert into auth.users (id, email)
values ('22222222-2222-2222-2222-222222222222', 'admin@example.com'),
       ('33333333-3333-3333-3333-333333333333', 'super@example.com'),
       ('44444444-4444-4444-4444-444444444444', 'victim@example.com');

update public.profiles set role = 'admin'
  where id = '22222222-2222-2222-2222-222222222222';
update public.profiles set role = 'super_admin'
  where id = '33333333-3333-3333-3333-333333333333';

select has_function('public','is_admin','is_admin() exists');
select has_function('public','is_staff_or_above','is_staff_or_above() exists');
select has_function('public','is_super_admin','is_super_admin() exists');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

select throws_ok(
  $$update public.profiles set role = 'super_admin'
      where id = '22222222-2222-2222-2222-222222222222'$$,
  '42501', null, 'admin cannot promote itself to super_admin');

select throws_ok(
  $$update public.profiles set role = 'admin'
      where id = '44444444-4444-4444-4444-444444444444'$$,
  '42501', null, 'admin cannot change another profile role');

set local request.jwt.claims to
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

select lives_ok(
  $$update public.profiles set role = 'staff'
      where id = '44444444-4444-4444-4444-444444444444'$$,
  'super_admin can change a role');

select * from finish();
rollback;
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `supabase test db`
Expected: FAIL — `relation "public.profiles" does not exist`.

- [ ] **Step 3: Write the migration**

`supabase/migrations/0002_profiles.sql`:

```sql
create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  phone      text,
  role       public.user_role not null default 'customer',
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Role lookups run inside policies, so they must bypass RLS themselves.
create function public.current_role()
returns public.user_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select role from public.profiles where id = auth.uid();
$$;

create function public.is_staff_or_above()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    public.current_role() in ('staff','admin','accountant','super_admin'),
    false);
$$;

create function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.current_role() in ('admin','super_admin'), false);
$$;

create function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.current_role() = 'super_admin', false);
$$;

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (new.id,
          new.raw_user_meta_data ->> 'full_name',
          new.raw_user_meta_data ->> 'phone');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create policy profiles_select_self on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_staff_or_above());

-- Role is deliberately excluded: the WITH CHECK clause pins it to the
-- stored value, so self-service escalation is rejected with 42501.
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and role = (select p.role from public.profiles p where p.id = auth.uid())
  );

-- Admin access is split rather than FOR ALL. Postgres ORs permissive
-- policies together, so a blanket `FOR ALL USING (is_admin())` would OR
-- away the role pin above and let any admin write role = 'super_admin'.
create policy profiles_admin_select on public.profiles
  for select to authenticated
  using (public.is_admin());

create policy profiles_admin_insert on public.profiles
  for insert to authenticated
  with check (public.is_admin() and (role = 'customer' or public.is_super_admin()));

-- Role changes are super-admin only: for any other admin the new row's role
-- must equal the role already stored for that row.
create policy profiles_admin_update on public.profiles
  for update to authenticated
  using (public.is_admin())
  with check (
    public.is_super_admin()
    or role = (select p.role from public.profiles p where p.id = profiles.id)
  );

create policy profiles_admin_delete on public.profiles
  for delete to authenticated
  using (public.is_admin());
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `supabase db reset && supabase test db`
Expected: PASS, 5 of 5.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0002_profiles.sql supabase/tests/01_profiles_test.sql
git commit -m "feat(db): add profiles, role helpers, and signup trigger"
```

---

### Task 4: Properties, units, and slot types

**Files:**
- Create: `supabase/migrations/0003_properties_units.sql`, `supabase/tests/02_properties_test.sql`

**Interfaces:**
- Consumes: `booking_mode`, `slot_code` (Task 2); `is_admin()`, `is_staff_or_above()` (Task 3).
- Produces: tables `public.properties`, `public.units`, `public.slot_types`. Later tasks reference `units.id`, `units.booking_mode`, `units.capacity_base`, `units.capacity_max`, `slot_types.id`, `slot_types.start_time`, `slot_types.end_time`, `properties.check_in_time`, `properties.check_out_time`.

- [ ] **Step 1: Write the failing test**

`supabase/tests/02_properties_test.sql`:

```sql
begin;
select plan(4);

select has_table('public','properties','properties exists');
select has_table('public','units','units exists');
select has_table('public','slot_types','slot_types exists');

insert into public.properties (id, name, slug, check_in_time, check_out_time)
values ('aaaaaaaa-0000-0000-0000-000000000001','P1','p1','14:00','11:00');

-- anonymous browsing must work before signup
set local role anon;
select is(
  (select count(*)::int from public.properties),
  1,
  'anon can read active properties'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `supabase test db`
Expected: FAIL — `relation "public.properties" does not exist`.

- [ ] **Step 3: Write the migration**

`supabase/migrations/0003_properties_units.sql`:

```sql
create table public.properties (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  slug           text not null unique,
  description    text,
  address        text,
  lat            double precision,
  lng            double precision,
  images         text[] not null default '{}',
  amenities      text[] not null default '{}',
  check_in_time  time not null default '14:00',
  check_out_time time not null default '11:00',
  timezone       text not null default 'Asia/Kolkata',
  is_active      boolean not null default true,
  created_at     timestamptz not null default now()
);

create table public.units (
  id             uuid primary key default gen_random_uuid(),
  property_id    uuid not null references public.properties(id) on delete cascade,
  name           text not null,
  description    text,
  images         text[] not null default '{}',
  capacity_base  int not null check (capacity_base > 0),
  capacity_max   int not null check (capacity_max > 0),
  booking_mode   public.booking_mode not null default 'nightly',
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  constraint units_capacity_order check (capacity_max >= capacity_base),
  unique (property_id, name)
);

create index units_property_idx on public.units(property_id);

create table public.slot_types (
  id          uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  code        public.slot_code not null,
  start_time  time not null,
  end_time    time not null,
  unique (property_id, code)
);

-- Table grants are required in addition to RLS. This project's Supabase
-- config does not auto-expose new tables to the Data API roles, so a table
-- with policies but no grant fails closed at the privilege layer with 42501
-- before RLS is ever evaluated. Every table in this plan needs its grant.
grant select on public.properties, public.units, public.slot_types
  to anon, authenticated;
grant insert, update, delete on public.properties, public.units,
  public.slot_types to authenticated;

alter table public.properties enable row level security;
alter table public.units      enable row level security;
alter table public.slot_types enable row level security;

create policy properties_read on public.properties
  for select to anon, authenticated
  using (is_active or public.is_staff_or_above());

create policy properties_write on public.properties
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy units_read on public.units
  for select to anon, authenticated
  using (is_active or public.is_staff_or_above());

create policy units_write on public.units
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy slot_types_read on public.slot_types
  for select to anon, authenticated using (true);

create policy slot_types_write on public.slot_types
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
```

Note on `end_time`: a `night` slot legitimately ends before it starts in clock
terms (18:00 to 09:00). No ordering check is applied here; Task 6 resolves the
wrap by adding a day when `end_time <= start_time`.

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `supabase db reset && supabase test db`
Expected: PASS, 4 of 4.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0003_properties_units.sql supabase/tests/02_properties_test.sql
git commit -m "feat(db): add properties, units, and slot types"
```

---

### Task 5: Rate rules and the quote engine

**Files:**
- Create: `supabase/migrations/0004_rate_rules.sql`, `supabase/tests/03_quote_test.sql`

**Interfaces:**
- Consumes: `units`, `slot_types` (Task 4); `rate_kind` (Task 2).
- Produces: table `public.rate_rules`; function
  `public.get_quote(p_unit_id uuid, p_period tstzrange, p_guests int, p_slot_type_id uuid default null) returns jsonb`.
  The returned object has this exact shape, relied on by Tasks 7, 8, and 14:

```json
{
  "unit_id": "...",
  "currency": "INR",
  "guests": 4,
  "lines": [
    {"date": "2026-08-03", "label": "Weekend rate", "amount": 12000,
     "rate_rule_id": "...", "extra_guests": 1, "extra_guest_amount": 1500}
  ],
  "subtotal": 13500,
  "cleaning_fee": 1500,
  "total": 15000
}
```

Amounts are integer rupees. `lines[].date` is a calendar date in the property's
timezone.

- [ ] **Step 1: Write the failing test**

`supabase/tests/03_quote_test.sql`:

```sql
begin;
select plan(4);

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000001','P1','p1');

insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001','U1', 4, 6);

-- base 10000/night, +1500 per extra guest, 1500 cleaning
insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority)
values ('bbbbbbbb-0000-0000-0000-000000000001','base',10000,1500,1500,0);

-- weekend 12000, Sat+Sun (ISO dow 6,7)
insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority, weekdays)
values ('bbbbbbbb-0000-0000-0000-000000000001','weekend',12000,1500,1500,10,
        array[6,7]);

-- Mon 2026-08-03 to Tue 2026-08-04: one weekday night
select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
     tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
     4) ->> 'total')::numeric,
  11500::numeric,
  'weekday night = 10000 + 1500 cleaning'
);

-- Sat 2026-08-08 to Sun 2026-08-09: one weekend night
select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
     tstzrange('2026-08-08 14:00+05:30','2026-08-09 11:00+05:30','[)'),
     4) ->> 'total')::numeric,
  13500::numeric,
  'weekend rule outranks base by priority'
);

-- 6 guests on a weekday night: 2 extra guests
select is(
  (public.get_quote('bbbbbbbb-0000-0000-0000-000000000001',
     tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
     6) ->> 'total')::numeric,
  14500::numeric,
  'two extra guests add 3000'
);

-- a unit with no base rule cannot be quoted
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000002',
        'aaaaaaaa-0000-0000-0000-000000000001','U2', 2, 2);

select throws_ok(
  $$select public.get_quote('bbbbbbbb-0000-0000-0000-000000000002',
      tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'), 2)$$,
  'P0004',
  null,
  'missing base rate is rejected'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `supabase test db`
Expected: FAIL — `relation "public.rate_rules" does not exist`.

- [ ] **Step 3: Write the migration**

`supabase/migrations/0004_rate_rules.sql`:

```sql
create table public.rate_rules (
  id                uuid primary key default gen_random_uuid(),
  unit_id           uuid not null references public.units(id) on delete cascade,
  kind              public.rate_kind not null,
  slot_type_id      uuid references public.slot_types(id) on delete cascade,
  label             text,
  valid_from        date,
  valid_to          date,
  weekdays          int[],
  price             numeric(12,2) not null check (price >= 0),
  extra_guest_price numeric(12,2) not null default 0 check (extra_guest_price >= 0),
  cleaning_fee      numeric(12,2) not null default 0 check (cleaning_fee >= 0),
  priority          int not null default 0,
  created_at        timestamptz not null default now(),
  constraint rate_rules_override_dates check (
    kind <> 'override' or (valid_from is not null and valid_to is not null)
  ),
  constraint rate_rules_date_order check (
    valid_from is null or valid_to is null or valid_to >= valid_from
  )
);

create index rate_rules_unit_idx on public.rate_rules(unit_id, priority desc);

grant select on public.rate_rules to anon, authenticated;
grant insert, update, delete on public.rate_rules to authenticated;

alter table public.rate_rules enable row level security;

create policy rate_rules_read on public.rate_rules
  for select to anon, authenticated using (true);

create policy rate_rules_write on public.rate_rules
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Resolve the single winning rule for one date on one unit.
-- Ordering reads as specificity. `created_at` alone is NOT a sufficient
-- tie-break: the column default is `now()`, which is frozen for the whole
-- transaction, so rules inserted together (a seed script, an admin bulk add)
-- share a timestamp and resolve arbitrarily. Without the specificity terms a
-- generic rule silently shadows a slot-specific one at equal priority.
create function public.resolve_rate_rule(
  p_unit_id      uuid,
  p_date         date,
  p_slot_type_id uuid
) returns public.rate_rules
language sql
stable
set search_path = public, pg_temp
as $$
  select r.*
  from public.rate_rules r
  where r.unit_id = p_unit_id
    and (r.slot_type_id is null or r.slot_type_id = p_slot_type_id)
    and (r.valid_from is null or p_date >= r.valid_from)
    and (r.valid_to   is null or p_date <= r.valid_to)
    and (r.weekdays is null or extract(isodow from p_date)::int = any(r.weekdays))
  order by
    r.priority desc,
    (r.slot_type_id is not null) desc,
    (r.weekdays    is not null) desc,
    (r.valid_from  is not null) desc,
    r.created_at desc,
    r.id desc
  limit 1;
$$;

create function public.get_quote(
  p_unit_id      uuid,
  p_period       tstzrange,
  p_guests       int,
  p_slot_type_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_unit      public.units;
  v_tz        text;
  v_rule      public.rate_rules;
  v_date      date;
  v_end_date  date;
  v_lines     jsonb := '[]'::jsonb;
  v_subtotal  numeric(12,2) := 0;
  v_cleaning  numeric(12,2) := 0;
  v_extra     int;
  v_extra_amt numeric(12,2);
begin
  select * into v_unit from public.units where id = p_unit_id and is_active;
  if not found then
    raise exception 'unit not found or inactive' using errcode = 'P0002';
  end if;

  select p.timezone into v_tz
  from public.properties p where p.id = v_unit.property_id;

  if p_guests is null or p_guests < 1 or p_guests > v_unit.capacity_max then
    raise exception 'guest count out of range (max %)', v_unit.capacity_max
      using errcode = 'P0003';
  end if;

  v_extra := greatest(p_guests - v_unit.capacity_base, 0);

  -- One line per calendar night (nightly) or per slot day (slot bookings).
  v_date     := (lower(p_period) at time zone v_tz)::date;
  v_end_date := (upper(p_period) at time zone v_tz)::date;
  if p_slot_type_id is not null then
    v_end_date := v_date + 1;   -- a slot occupies exactly one dated line
  end if;

  while v_date < v_end_date loop
    v_rule := public.resolve_rate_rule(p_unit_id, v_date, p_slot_type_id);
    if v_rule.id is null then
      raise exception 'no rate rule for unit % on %', p_unit_id, v_date
        using errcode = 'P0004';
    end if;

    v_extra_amt := v_extra * v_rule.extra_guest_price;
    v_subtotal  := v_subtotal + v_rule.price + v_extra_amt;
    v_cleaning  := greatest(v_cleaning, v_rule.cleaning_fee);

    v_lines := v_lines || jsonb_build_object(
      'date',               to_char(v_date, 'YYYY-MM-DD'),
      'label',              coalesce(v_rule.label, initcap(v_rule.kind::text) || ' rate'),
      'amount',             v_rule.price,
      'rate_rule_id',       v_rule.id,
      'extra_guests',       v_extra,
      'extra_guest_amount', v_extra_amt
    );

    v_date := v_date + 1;
  end loop;

  if jsonb_array_length(v_lines) = 0 then
    raise exception 'period covers no nights' using errcode = 'P0005';
  end if;

  return jsonb_build_object(
    'unit_id',      p_unit_id,
    'currency',     'INR',
    'guests',       p_guests,
    'lines',        v_lines,
    'subtotal',     v_subtotal,
    'cleaning_fee', v_cleaning,
    'total',        v_subtotal + v_cleaning
  );
end;
$$;
```

Cleaning fee is charged once per booking, taking the highest fee among the
matched rules, rather than once per night.

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `supabase db reset && supabase test db`
Expected: PASS, 4 of 4.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0004_rate_rules.sql supabase/tests/03_quote_test.sql
git commit -m "feat(db): add rate rules and server-side quote engine"
```

---

### Task 6: Reservations, the exclusion constraint, and availability

**Files:**
- Create: `supabase/migrations/0005_reservations.sql`, `supabase/tests/04_reservations_test.sql`

**Interfaces:**
- Consumes: `units`, `slot_types`, `properties` (Task 4); `reservation_kind`, `reservation_status` (Task 2); `is_admin()`, `is_staff_or_above()` (Task 3).
- Produces: table `public.reservations`; view `public.availability(unit_id, period, kind)`; functions
  `public.build_period(p_unit_id uuid, p_from date, p_to date, p_slot_type_id uuid default null) returns tstzrange` and
  `public.search_availability(p_property_id uuid, p_from date, p_to date, p_guests int, p_slot_type_id uuid default null) returns table(unit_id uuid, property_id uuid, unit_name text, booking_mode public.booking_mode, is_available boolean, busy_periods tstzrange[])`.

- [ ] **Step 1: Write the failing test**

`supabase/tests/04_reservations_test.sql`:

```sql
begin;
select plan(7);

insert into public.properties (id, name, slug, check_in_time, check_out_time)
values ('aaaaaaaa-0000-0000-0000-000000000001','P1','p1','14:00','11:00');

insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001','U1',4,6);

-- Bookings require a customer (reservations_booking_has_customer). The
-- signup trigger creates the matching profiles row automatically.
insert into auth.users (id, email)
values ('dddddddd-0000-0000-0000-000000000001','guest@example.com');

insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2026-08-03 14:00+05:30','2026-08-05 11:00+05:30','[)'),
        'booking','confirmed','dddddddd-0000-0000-0000-000000000001',2);

-- overlapping insert is rejected by the constraint
select throws_ok(
  $$insert into public.reservations
      (unit_id, period, kind, status, customer_id, guests)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-04 14:00+05:30','2026-08-06 11:00+05:30','[)'),
      'booking','confirmed','dddddddd-0000-0000-0000-000000000001',2)$$,
  '23P01', null, 'overlapping reservation is rejected');

-- an admin block over a confirmed booking hits the same constraint
select throws_ok(
  $$insert into public.reservations (unit_id, period, kind, status, block_reason)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-04 00:00+05:30','2026-08-04 23:59+05:30','[)'),
      'block','confirmed','maintenance')$$,
  '23P01', null, 'block cannot overlap a confirmed booking');

-- back-to-back checkout 11:00 / checkin 14:00 does not conflict
select lives_ok(
  $$insert into public.reservations
      (unit_id, period, kind, status, customer_id, guests)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-05 14:00+05:30','2026-08-06 11:00+05:30','[)'),
      'booking','confirmed','dddddddd-0000-0000-0000-000000000001',2)$$,
  'back-to-back stays do not conflict');

-- cancelling frees the range immediately
update public.reservations set status = 'cancelled'
where period && tstzrange('2026-08-03 14:00+05:30','2026-08-05 11:00+05:30','[)');

select lives_ok(
  $$insert into public.reservations
      (unit_id, period, kind, status, customer_id, guests)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2026-08-03 14:00+05:30','2026-08-05 11:00+05:30','[)'),
      'booking','confirmed','dddddddd-0000-0000-0000-000000000001',2)$$,
  'cancelled reservation frees its range');

-- build_period applies the property check-in and check-out times
select is(
  public.build_period('bbbbbbbb-0000-0000-0000-000000000001',
                      '2026-09-01'::date, '2026-09-03'::date),
  tstzrange('2026-09-01 14:00+05:30','2026-09-03 11:00+05:30','[)'),
  'nightly period uses property check-in/out times');

-- the restored integrity rule bites: a booking must name a customer
select throws_ok(
  $$insert into public.reservations (unit_id, period, kind, status)
    values ('bbbbbbbb-0000-0000-0000-000000000001',
      tstzrange('2027-01-03 14:00+05:30','2027-01-04 11:00+05:30','[)'),
      'booking','confirmed')$$,
  '23514', null, 'a booking without a customer is rejected');

-- search_availability reports the unit busy for an overlapping window
select is(
  (select is_available from public.search_availability(
     'aaaaaaaa-0000-0000-0000-000000000001',
     '2026-08-04'::date, '2026-08-05'::date, 4)),
  false,
  'busy unit reported unavailable');

select * from finish();
rollback;
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `supabase test db`
Expected: FAIL — `relation "public.reservations" does not exist`.

- [ ] **Step 3: Write the migration**

`supabase/migrations/0005_reservations.sql`:

```sql
create table public.reservations (
  id              uuid primary key default gen_random_uuid(),
  unit_id         uuid not null references public.units(id) on delete cascade,
  slot_type_id    uuid references public.slot_types(id),
  period          tstzrange not null,
  kind            public.reservation_kind not null default 'booking',
  status          public.reservation_status not null default 'hold',
  customer_id     uuid references public.profiles(id),
  guests          int,
  quote           jsonb,
  hold_expires_at timestamptz,
  block_reason    text,
  cancel_reason   text,
  cancelled_at    timestamptz,
  source          text not null default 'app',
  created_by      uuid references public.profiles(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint reservations_period_nonempty check (not isempty(period)),
  constraint reservations_booking_has_customer check (
    kind <> 'booking' or customer_id is not null),
  constraint reservations_block_has_reason check (
    kind <> 'block' or block_reason is not null),
  constraint reservations_no_overlap
    exclude using gist (unit_id with =, period with &&)
    where (status <> 'cancelled')
);

create index reservations_unit_period_idx
  on public.reservations using gist (unit_id, period);
create index reservations_customer_idx on public.reservations(customer_id);
create index reservations_hold_idx
  on public.reservations(hold_expires_at) where status = 'hold';

-- Customers never write here directly — every write goes through the
-- SECURITY DEFINER RPC in Task 8, which runs as the function owner. The
-- insert/update/delete grants exist for the admin policy below.
grant select on public.reservations to authenticated;
grant insert, update, delete on public.reservations to authenticated;

alter table public.reservations enable row level security;

create function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger reservations_touch
  before update on public.reservations
  for each row execute function public.touch_updated_at();

-- Reads. All writes go through the RPC functions in Task 7, so no
-- INSERT/UPDATE policy is granted to customers at all.
create policy reservations_select_own on public.reservations
  for select to authenticated
  using (customer_id = auth.uid() or public.is_staff_or_above());

create policy reservations_admin_write on public.reservations
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Public availability: busy ranges without customer identity.
create view public.availability
with (security_invoker = off) as
  select r.unit_id, r.period, r.kind
  from public.reservations r
  where r.status <> 'cancelled';

grant select on public.availability to anon, authenticated;

-- Turn dates into a concrete period using property or slot times.
create function public.build_period(
  p_unit_id      uuid,
  p_from         date,
  p_to           date,
  p_slot_type_id uuid default null
) returns tstzrange
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_tz    text;
  v_in    time;
  v_out   time;
  v_start timestamptz;
  v_end   timestamptz;
begin
  select p.timezone, p.check_in_time, p.check_out_time
    into v_tz, v_in, v_out
  from public.units u
  join public.properties p on p.id = u.property_id
  where u.id = p_unit_id;

  if v_tz is null then
    raise exception 'unit not found' using errcode = 'P0002';
  end if;

  if p_slot_type_id is not null then
    select s.start_time, s.end_time into v_in, v_out
    from public.slot_types s where s.id = p_slot_type_id;

    if v_in is null then
      raise exception 'slot type not found' using errcode = 'P0002';
    end if;

    v_start := ((p_from + v_in) at time zone v_tz);
    -- A night slot wraps past midnight; add a day when it does.
    v_end := ((p_from + v_out
               + case when v_out <= v_in then interval '1 day'
                      else interval '0' end) at time zone v_tz);
  else
    if p_to <= p_from then
      raise exception 'check-out must be after check-in'
        using errcode = 'P0005';
    end if;
    v_start := ((p_from + v_in) at time zone v_tz);
    v_end   := ((p_to   + v_out) at time zone v_tz);
  end if;

  return tstzrange(v_start, v_end, '[)');
end;
$$;

create function public.search_availability(
  p_property_id  uuid,
  p_from         date,
  p_to           date,
  p_guests       int default 1,
  p_slot_type_id uuid default null
) returns table (
  unit_id      uuid,
  property_id  uuid,
  unit_name    text,
  booking_mode public.booking_mode,
  is_available boolean,
  busy_periods tstzrange[]
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    u.id,
    u.property_id,
    u.name,
    u.booking_mode,
    not exists (
      select 1 from public.reservations r
      where r.unit_id = u.id
        and r.status <> 'cancelled'
        and r.period && public.build_period(u.id, p_from, p_to, p_slot_type_id)
    ),
    coalesce((
      select array_agg(r.period order by lower(r.period))
      from public.reservations r
      where r.unit_id = u.id
        and r.status <> 'cancelled'
        and r.period && tstzrange(
              (p_from - 1)::timestamptz, (p_to + 1)::timestamptz, '[)')
    ), '{}')
  from public.units u
  join public.properties p on p.id = u.property_id
  where u.is_active
    and p.is_active
    and (p_property_id is null or u.property_id = p_property_id)
    and u.capacity_max >= p_guests
  order by u.name;
$$;

grant execute on function public.search_availability to anon, authenticated;
grant execute on function public.build_period      to anon, authenticated;
grant execute on function public.get_quote         to anon, authenticated;
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `supabase db reset && supabase test db`
Expected: PASS, 6 of 6.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0005_reservations.sql supabase/tests/04_reservations_test.sql
git commit -m "feat(db): add reservations with overlap exclusion and availability search"
```

---

### Task 7: Payments, audit log, and status transition recording

**Files:**
- Create: `supabase/migrations/0006_payments_audit.sql`, `supabase/tests/05_audit_test.sql`

**Interfaces:**
- Consumes: `reservations` (Task 6); `payment_kind`, `payment_status` (Task 2).
- Produces: tables `public.payments`, `public.audit_log`; trigger `reservations_audit` that writes one `audit_log` row per status transition. Task 8's `confirm_booking` inserts into `payments`; phase 3 notification senders read `audit_log`.

This task precedes the booking RPC because `confirm_booking` writes to both
tables.

- [ ] **Step 1: Write the failing test**

`supabase/tests/05_audit_test.sql`:

```sql
begin;
select plan(3);

select has_table('public','payments','payments exists');
select has_table('public','audit_log','audit_log exists');

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000001','P1','p1');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001','U1',4,6);
insert into public.reservations (id, unit_id, period, kind, status, block_reason)
values ('cccccccc-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2026-08-03 14:00+05:30','2026-08-05 11:00+05:30','[)'),
        'block','confirmed','maintenance');

update public.reservations set status = 'cancelled'
where id = 'cccccccc-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.audit_log
    where entity = 'reservation'
      and entity_id = 'cccccccc-0000-0000-0000-000000000001'
      and action = 'status:confirmed->cancelled'),
  1,
  'status transition is recorded once');

select * from finish();
rollback;
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `supabase test db`
Expected: FAIL — `relation "public.payments" does not exist`.

- [ ] **Step 3: Write the migration**

`supabase/migrations/0006_payments_audit.sql`:

```sql
create table public.payments (
  id             uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.reservations(id) on delete cascade,
  amount         numeric(12,2) not null check (amount > 0),
  kind           public.payment_kind not null default 'advance',
  status         public.payment_status not null default 'pending',
  gateway        text not null default 'mock',
  gateway_ref    text,
  raw            jsonb,
  created_at     timestamptz not null default now(),
  unique (gateway, gateway_ref)
);

create index payments_reservation_idx on public.payments(reservation_id);

grant select on public.payments to authenticated;
grant insert, update on public.payments to authenticated;

alter table public.payments enable row level security;

create policy payments_select on public.payments
  for select to authenticated
  using (
    public.is_staff_or_above()
    or exists (
      select 1 from public.reservations r
      where r.id = payments.reservation_id and r.customer_id = auth.uid())
  );

create policy payments_admin_write on public.payments
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create table public.audit_log (
  id        bigserial primary key,
  actor_id  uuid,
  entity    text not null,
  entity_id uuid not null,
  action    text not null,
  before    jsonb,
  after     jsonb,
  at        timestamptz not null default now()
);

create index audit_log_entity_idx on public.audit_log(entity, entity_id, at desc);

-- Read-only for staff. Rows are written by the SECURITY DEFINER trigger
-- below, running as the function owner, so no insert grant is needed.
grant select on public.audit_log to authenticated;

alter table public.audit_log enable row level security;

create policy audit_log_read on public.audit_log
  for select to authenticated using (public.is_staff_or_above());

-- One row per status transition. Phase 3 notification senders subscribe here.
create function public.record_reservation_transition()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.audit_log (actor_id, entity, entity_id, action, after)
    values (auth.uid(), 'reservation', new.id,
            'created:' || new.status::text, to_jsonb(new));
  elsif new.status is distinct from old.status then
    insert into public.audit_log
      (actor_id, entity, entity_id, action, before, after)
    values (auth.uid(), 'reservation', new.id,
            'status:' || old.status::text || '->' || new.status::text,
            to_jsonb(old), to_jsonb(new));
  end if;
  return new;
end;
$$;

create trigger reservations_audit
  after insert or update on public.reservations
  for each row execute function public.record_reservation_transition();
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `supabase db reset && supabase test db`
Expected: PASS, 3 of 3.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0006_payments_audit.sql supabase/tests/05_audit_test.sql
git commit -m "feat(db): add payments, audit log, and transition recording"
```

---

### Task 8: Booking RPC — hold, confirm, cancel, expiry

**Files:**
- Create: `supabase/migrations/0007_booking_rpc.sql`, `supabase/tests/06_booking_flow_test.sql`

**Interfaces:**
- Consumes: `get_quote` (Task 5), `build_period`, `reservations` (Task 6), `payments`, `audit_log` (Task 7).
- Produces:
  - `public.create_hold(p_unit_id uuid, p_from date, p_to date, p_guests int, p_slot_type_id uuid default null, p_expected_total numeric default null) returns public.reservations`
  - `public.confirm_booking(p_reservation_id uuid, p_payment_ref text, p_amount numeric) returns public.reservations`
  - `public.cancel_booking(p_reservation_id uuid, p_reason text) returns public.reservations`
  - `public.block_dates(p_unit_id uuid, p_ranges daterange[], p_reason text) returns setof public.reservations`
  - `public.release_expired_holds() returns int`

  Error codes raised, consumed by Task 12's Dart mapping: `23P01` unavailable,
  `P0006` hold expired, `P0007` quote stale, `P0008` not permitted,
  `P0009` invalid state.

- [ ] **Step 1: Write the failing test**

`supabase/tests/06_booking_flow_test.sql`:

```sql
begin;
select plan(6);

insert into auth.users (id, email)
values ('11111111-1111-1111-1111-111111111111','cust@example.com');

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000001','P1','p1');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001','U1',4,6);
insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority)
values ('bbbbbbbb-0000-0000-0000-000000000001','base',10000,1500,1500,0);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- hold is created with a future expiry
select is(
  (select status from public.create_hold(
     'bbbbbbbb-0000-0000-0000-000000000001',
     '2026-08-03','2026-08-04', 4)),
  'hold'::public.reservation_status,
  'create_hold returns a hold');

-- a second hold on the same range is rejected
select throws_ok(
  $$select public.create_hold('bbbbbbbb-0000-0000-0000-000000000001',
      '2026-08-03','2026-08-04', 4)$$,
  '23P01', null, 'concurrent hold on same range is rejected');

-- a stale expected total is rejected
select throws_ok(
  $$select public.create_hold('bbbbbbbb-0000-0000-0000-000000000001',
      '2026-09-03','2026-09-04', 4, null, 999)$$,
  'P0007', null, 'stale quote is rejected');

-- confirm turns the hold into a confirmed booking and records the payment
select is(
  (select status from public.confirm_booking(
     (select id from public.reservations where status = 'hold' limit 1),
     'mock_ref_1', 11500)),
  'confirmed'::public.reservation_status,
  'confirm_booking confirms the hold');

select is(
  (select count(*)::int from public.payments where gateway_ref = 'mock_ref_1'),
  1,
  'payment row recorded');

-- expired holds are released
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, hold_expires_at)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2026-10-03 14:00+05:30','2026-10-04 11:00+05:30','[)'),
        'booking','hold','11111111-1111-1111-1111-111111111111',4,
        now() - interval '1 minute');

set local role postgres;
select is(public.release_expired_holds(), 1, 'expired hold released');

select * from finish();
rollback;
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `supabase test db`
Expected: FAIL — `function public.create_hold(...) does not exist`.

- [ ] **Step 3: Write the migration**

`supabase/migrations/0007_booking_rpc.sql`:

```sql
create function public.create_hold(
  p_unit_id        uuid,
  p_from           date,
  p_to             date,
  p_guests         int,
  p_slot_type_id   uuid default null,
  p_expected_total numeric default null
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_period tstzrange;
  v_quote  jsonb;
  v_row    public.reservations;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  v_period := public.build_period(p_unit_id, p_from, p_to, p_slot_type_id);
  v_quote  := public.get_quote(p_unit_id, v_period, p_guests, p_slot_type_id);

  -- The client displayed a total; refuse to hold at a price it never saw.
  if p_expected_total is not null
     and (v_quote ->> 'total')::numeric <> p_expected_total then
    raise exception 'price changed to %', (v_quote ->> 'total')
      using errcode = 'P0007';
  end if;

  insert into public.reservations
    (unit_id, slot_type_id, period, kind, status, customer_id, guests,
     quote, hold_expires_at, created_by)
  values
    (p_unit_id, p_slot_type_id, v_period, 'booking', 'hold', v_uid, p_guests,
     v_quote, now() + interval '15 minutes', v_uid)
  returning * into v_row;

  return v_row;
end;
$$;

create function public.confirm_booking(
  p_reservation_id uuid,
  p_payment_ref    text,
  p_amount         numeric
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.reservations;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  -- `is distinct from`, not `<>`: customer_id is NULL on block rows, and
  -- `NULL <> uuid` is NULL, which PL/pgSQL's IF treats as false -- that would
  -- let any authenticated caller cancel an admin's block.
  if v_row.customer_id is distinct from v_uid and not public.is_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if v_row.status = 'confirmed' then
    return v_row;   -- idempotent: a retried webhook must not double-charge
  end if;

  if v_row.status <> 'hold' then
    raise exception 'reservation is %', v_row.status using errcode = 'P0009';
  end if;

  if v_row.hold_expires_at < now() then
    raise exception 'hold expired' using errcode = 'P0006';
  end if;

  -- Never trust the client's amount. Phase 1 collects the full quoted
  -- total; when phase 2 adds the advance/balance split this becomes a range
  -- check against the advance policy.
  if p_amount is null
     or p_amount <> (v_row.quote ->> 'total')::numeric then
    raise exception 'payment amount % does not match quoted total %',
      p_amount, (v_row.quote ->> 'total')
      using errcode = 'P0009';
  end if;

  insert into public.payments
    (reservation_id, amount, kind, status, gateway, gateway_ref)
  values (p_reservation_id, p_amount, 'advance', 'succeeded', 'mock',
          p_payment_ref);

  update public.reservations
     set status = 'confirmed', hold_expires_at = null
   where id = p_reservation_id
  returning * into v_row;

  return v_row;
end;
$$;

create function public.cancel_booking(
  p_reservation_id uuid,
  p_reason         text
) returns public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.reservations;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_row from public.reservations
  where id = p_reservation_id for update;

  if not found then
    raise exception 'reservation not found' using errcode = 'P0002';
  end if;

  -- `is distinct from`, not `<>`: customer_id is NULL on block rows, and
  -- `NULL <> uuid` is NULL, which PL/pgSQL's IF treats as false -- that would
  -- let any authenticated caller cancel an admin's block.
  if v_row.customer_id is distinct from v_uid and not public.is_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if v_row.status = 'cancelled' then
    return v_row;
  end if;

  update public.reservations
     set status = 'cancelled',
         cancel_reason = p_reason,
         cancelled_at = now()
   where id = p_reservation_id
  returning * into v_row;

  return v_row;
end;
$$;

-- Admin blocking. All ranges land or none do: one transaction, one statement.
create function public.block_dates(
  p_unit_id uuid,
  p_ranges  daterange[],
  p_reason  text
) returns setof public.reservations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_range daterange;
begin
  if not public.is_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  foreach v_range in array p_ranges loop
    return query
      insert into public.reservations
        (unit_id, period, kind, status, block_reason, created_by, source)
      values (p_unit_id,
              public.build_period(p_unit_id, lower(v_range), upper(v_range)),
              'block', 'confirmed', p_reason, auth.uid(), 'admin')
      returning *;
  end loop;
end;
$$;

create function public.release_expired_holds()
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count int;
begin
  update public.reservations
     set status = 'cancelled',
         cancel_reason = 'hold expired',
         cancelled_at = now()
   where status = 'hold'
     and hold_expires_at < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Postgres grants EXECUTE to PUBLIC by default on new functions, so the
-- PUBLIC revoke is the one that actually closes this; the named revoke
-- documents intent.
revoke execute on function public.release_expired_holds() from public;
revoke execute on function public.release_expired_holds() from anon, authenticated;

grant execute on function public.create_hold      to authenticated;
grant execute on function public.confirm_booking  to authenticated;
grant execute on function public.cancel_booking   to authenticated;
grant execute on function public.block_dates      to authenticated;

select cron.schedule(
  'release-expired-holds', '* * * * *',
  $$select public.release_expired_holds()$$);
```

`daterange` bounds: Postgres normalises `daterange` to `[)`, so `lower` is the
first blocked date and `upper` is the day after the last. `build_period` then
maps that to check-in and check-out times.

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `supabase db reset && supabase test db`
Expected: PASS, 6 of 6.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0007_booking_rpc.sql supabase/tests/06_booking_flow_test.sql
git commit -m "feat(db): add hold, confirm, cancel, block, and expiry RPC"
```

---

### Task 9: RLS matrix test

**Files:**
- Create: `supabase/tests/07_rls_test.sql`

**Interfaces:**
- Consumes: every table and policy from Tasks 3–8.
- Produces: no schema. This task exists because the spec's success criteria
  require positive and negative coverage for every role, and a policy bug is
  invisible until someone tests for it explicitly.

- [ ] **Step 1: Write the failing test**

`supabase/tests/07_rls_test.sql`:

```sql
begin;
select plan(7);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111','cust1@example.com'),
  ('22222222-2222-2222-2222-222222222222','cust2@example.com'),
  ('33333333-3333-3333-3333-333333333333','staff@example.com'),
  ('44444444-4444-4444-4444-444444444444','admin@example.com'),
  ('55555555-5555-5555-5555-555555555555','acct@example.com');

update public.profiles set role = 'staff'
  where id = '33333333-3333-3333-3333-333333333333';
update public.profiles set role = 'admin'
  where id = '44444444-4444-4444-4444-444444444444';
update public.profiles set role = 'accountant'
  where id = '55555555-5555-5555-5555-555555555555';

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000001','P1','p1');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001','U1',4,6);
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests)
values ('cccccccc-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001',
        tstzrange('2026-08-03 14:00+05:30','2026-08-04 11:00+05:30','[)'),
        'booking','confirmed','11111111-1111-1111-1111-111111111111',4);

-- customer 1 sees own booking
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select is((select count(*)::int from public.reservations), 1,
          'customer sees own reservation');

-- customer 2 sees none
set local request.jwt.claims to
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select is((select count(*)::int from public.reservations), 0,
          'customer cannot see another customer reservation');

-- customer 2 cannot cancel customer 1's booking
select throws_ok(
  $$select public.cancel_booking(
      'cccccccc-0000-0000-0000-000000000001','nope')$$,
  'P0008', null, 'customer cannot cancel another customer booking');

-- customer cannot block dates
select throws_ok(
  $$select public.block_dates('bbbbbbbb-0000-0000-0000-000000000001',
      array[daterange('2026-12-01','2026-12-03')], 'nope')$$,
  'P0008', null, 'customer cannot block dates');

-- customer cannot write units directly
select throws_ok(
  $$insert into public.units (property_id, name, capacity_base, capacity_max)
    values ('aaaaaaaa-0000-0000-0000-000000000001','X',2,2)$$,
  '42501', null, 'customer cannot create units');

-- staff sees all reservations
set local request.jwt.claims to
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
select is((select count(*)::int from public.reservations), 1,
          'staff sees reservations');

-- anonymous cannot read reservations, only the availability view
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';
select is((select count(*)::int from public.reservations), 0,
          'anon cannot read reservations');

select * from finish();
rollback;
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `supabase test db`
Expected: at least one failure. Anything that already passes is fine — the
value here is the assertions that do not.

- [ ] **Step 3: Fix the policies the test exposes**

No new migration is expected. If an assertion fails, correct the policy in the
migration that defines it (Task 3 for `profiles`, Task 4 for `units`, Task 6
for `reservations`, Task 7 for `payments`) and re-run. Do not add a policy that
grants direct `insert` or `update` on `reservations` to customers — the RPC
functions are the only write path.

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `supabase db reset && supabase test db`
Expected: PASS, 7 of 7, and every earlier test file still green.

- [ ] **Step 5: Commit**

```bash
git add supabase/tests/07_rls_test.sql supabase/migrations
git commit -m "test(db): add RLS matrix coverage for every role"
```

---

### Task 10: Seed data

**Files:**
- Create: `supabase/seed.sql`

**Interfaces:**
- Consumes: every table from Tasks 3–8.
- Produces: two properties, five units covering all three booking modes, slot
  types, rate rules including a season override, and one account per role.
  Every later Flutter task develops against this data. Passwords are
  `password123` for all seeded accounts.

- [ ] **Step 1: Write the seed file**

`supabase/seed.sql`:

```sql
-- Local development data only. Never loaded in a deployed environment.

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data,
                        raw_user_meta_data, created_at, updated_at)
select
  u.id, '00000000-0000-0000-0000-000000000000', 'authenticated',
  'authenticated', u.email, crypt('password123', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('full_name', u.full_name),
  now(), now()
from (values
  ('11111111-1111-1111-1111-111111111111'::uuid,'super@pasala.test','Super Admin'),
  ('22222222-2222-2222-2222-222222222222'::uuid,'admin@pasala.test','Asha Admin'),
  ('33333333-3333-3333-3333-333333333333'::uuid,'staff@pasala.test','Sita Staff'),
  ('44444444-4444-4444-4444-444444444444'::uuid,'accounts@pasala.test','Anil Accounts'),
  ('55555555-5555-5555-5555-555555555555'::uuid,'ravi@example.com','Ravi Kumar'),
  ('66666666-6666-6666-6666-666666666666'::uuid,'meera@example.com','Meera Nair')
) as u(id, email, full_name);

-- The signup trigger created customer profiles; promote the staff accounts.
update public.profiles set role = 'super_admin'
  where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set role = 'admin'
  where id = '22222222-2222-2222-2222-222222222222';
update public.profiles set role = 'staff'
  where id = '33333333-3333-3333-3333-333333333333';
update public.profiles set role = 'accountant'
  where id = '44444444-4444-4444-4444-444444444444';

insert into public.properties
  (id, name, slug, description, address, check_in_time, check_out_time, amenities)
values
  ('a0000000-0000-0000-0000-000000000001','Pasala Riverside','riverside',
   'Riverside farmhouse with private pool.','Shamirpet, Hyderabad',
   '14:00','11:00', array['Pool','Wi-Fi','Barbecue','Parking']),
  ('a0000000-0000-0000-0000-000000000002','Pasala Hilltop','hilltop',
   'Hilltop farmhouse with open lawn.','Moinabad, Hyderabad',
   '15:00','10:00', array['Lawn','Bonfire','Wi-Fi']);

insert into public.slot_types (id, property_id, code, start_time, end_time)
values
  ('50000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
   'day','09:00','18:00'),
  ('50000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',
   'night','18:00','09:00'),
  ('50000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000002',
   'full_day','09:00','08:00');

insert into public.units
  (id, property_id, name, capacity_base, capacity_max, booking_mode)
values
  ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
   'Whole Villa', 10, 16, 'both'),
  ('b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',
   'Garden Room', 2, 4, 'nightly'),
  ('b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001',
   'Pool Deck', 20, 40, 'slot'),
  ('b0000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000002',
   'Main House', 8, 12, 'nightly'),
  ('b0000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000002',
   'Lawn', 30, 60, 'slot');

-- base rates for every unit
insert into public.rate_rules
  (unit_id, kind, label, price, extra_guest_price, cleaning_fee, priority)
values
  ('b0000000-0000-0000-0000-000000000001','base','Weekday',25000,1500,2500,0),
  ('b0000000-0000-0000-0000-000000000002','base','Weekday', 4500, 800, 600,0),
  ('b0000000-0000-0000-0000-000000000003','base','Weekday',12000, 400,1500,0),
  ('b0000000-0000-0000-0000-000000000004','base','Weekday',18000,1200,2000,0),
  ('b0000000-0000-0000-0000-000000000005','base','Weekday',15000, 300,2000,0);

-- weekend uplift, Saturday and Sunday (ISO dow 6 and 7)
insert into public.rate_rules
  (unit_id, kind, label, price, extra_guest_price, cleaning_fee, priority, weekdays)
select unit_id, 'weekend', 'Weekend', price * 1.4, extra_guest_price,
       cleaning_fee, 10, array[6,7]
from public.rate_rules where kind = 'base';

-- Diwali season override, outranks weekend
insert into public.rate_rules
  (unit_id, kind, label, price, extra_guest_price, cleaning_fee, priority,
   valid_from, valid_to)
select unit_id, 'override', 'Diwali season', price * 1.8, extra_guest_price,
       cleaning_fee, 50, date '2026-11-06', date '2026-11-12'
from public.rate_rules where kind = 'base';

-- one confirmed booking and one admin block, so the calendar is not empty
insert into public.reservations
  (unit_id, period, kind, status, customer_id, guests, source)
values
  ('b0000000-0000-0000-0000-000000000002',
   public.build_period('b0000000-0000-0000-0000-000000000002',
                       current_date + 7, current_date + 9),
   'booking','confirmed','55555555-5555-5555-5555-555555555555',2,'app');

insert into public.reservations
  (unit_id, period, kind, status, block_reason, source)
values
  ('b0000000-0000-0000-0000-000000000001',
   public.build_period('b0000000-0000-0000-0000-000000000001',
                       current_date + 14, current_date + 16),
   'block','confirmed','Deep cleaning','admin');
```

- [ ] **Step 2: Load it and verify**

Run: `supabase db reset`
Then verify from `psql`:

```bash
psql "$(supabase status -o env | grep DB_URL | cut -d= -f2 | tr -d '"')" \
  -c "select count(*) from public.units;" \
  -c "select role, count(*) from public.profiles group by role order by role;" \
  -c "select public.get_quote('b0000000-0000-0000-0000-000000000002',
        public.build_period('b0000000-0000-0000-0000-000000000002',
          date '2026-11-07', date '2026-11-08'), 2) -> 'total';"
```

Expected: 5 units; one profile per role plus two customers; the Diwali quote
returns `8700` (4500 × 1.8 = 8100, plus 600 cleaning), proving override
priority beats the weekend rule on a Saturday.

- [ ] **Step 3: Confirm the test suite still passes**

Run: `supabase test db`
Expected: every file green. Seed data must not break the tests — pgTAP tests
run inside a transaction that rolls back, but they insert fixed UUIDs, so a
collision with seed UUIDs would surface here.

- [ ] **Step 4: Commit**

```bash
git add supabase/seed.sql
git commit -m "feat(db): add local seed data covering all roles and booking modes"
```

---

### Task 11: Flutter core — env, client, error mapping, theme

**Files:**
- Create: `lib/core/env.dart`, `lib/core/supabase_client.dart`, `lib/core/errors.dart`, `lib/core/theme/app_theme.dart`, `lib/core/format.dart`
- Test: `test/core/errors_test.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: the error codes raised in Task 8.
- Produces:
  - `Env.supabaseUrl`, `Env.supabaseAnonKey` (both `String`)
  - sealed class `BookingFailure` with subtypes `UnitUnavailable`, `HoldExpired`, `QuoteStale`, `NotPermitted`, `NotFound`, `InvalidState`, `NetworkFailure`, `UnknownFailure`, each exposing `String get message`
  - `BookingFailure mapPostgrestError(Object error)`
  - `String formatInr(num amount)`, `String formatDay(DateTime d)`
  - `supabaseProvider` (Riverpod `Provider<SupabaseClient>`)

  Every repository in Task 12 throws `BookingFailure`, never a
  `PostgrestException`.

- [ ] **Step 1: Write the failing test**

`test/core/errors_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  BookingFailure map(String code, [String message = 'boom']) =>
      mapPostgrestError(PostgrestException(message: message, code: code));

  test('exclusion violation maps to UnitUnavailable', () {
    expect(map('23P01'), isA<UnitUnavailable>());
  });

  test('P0006 maps to HoldExpired', () {
    expect(map('P0006'), isA<HoldExpired>());
  });

  test('P0007 maps to QuoteStale and keeps the server message', () {
    final failure = map('P0007', 'price changed to 13500');
    expect(failure, isA<QuoteStale>());
    expect(failure.message, contains('13500'));
  });

  test('P0008 and 42501 both map to NotPermitted', () {
    expect(map('P0008'), isA<NotPermitted>());
    expect(map('42501'), isA<NotPermitted>());
  });

  test('NotPermitted never leaks the server message', () {
    expect(map('42501', 'permission denied for table reservations').message,
        isNot(contains('reservations')));
  });

  test('a socket error maps to NetworkFailure', () {
    expect(mapPostgrestError(const SocketException('no route')),
        isA<NetworkFailure>());
  });
}
```

Add `import 'dart:io';` at the top of the test for `SocketException`.

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/core/errors_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:pasala/core/errors.dart'`.

- [ ] **Step 3: Write the implementation**

`lib/core/errors.dart`:

```dart
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

sealed class BookingFailure implements Exception {
  const BookingFailure(this.message);
  final String message;
  @override
  String toString() => '$runtimeType: $message';
}

class UnitUnavailable extends BookingFailure {
  const UnitUnavailable()
      : super('Those dates were just taken. Pick another slot.');
}

class HoldExpired extends BookingFailure {
  const HoldExpired()
      : super('Your 15-minute hold expired. Start again — dates are kept.');
}

class QuoteStale extends BookingFailure {
  const QuoteStale(super.message);
}

class NotPermitted extends BookingFailure {
  const NotPermitted() : super('You do not have access to do that.');
}

class NotFound extends BookingFailure {
  const NotFound() : super('That item no longer exists.');
}

class InvalidState extends BookingFailure {
  const InvalidState(super.message);
}

class NetworkFailure extends BookingFailure {
  const NetworkFailure() : super('Cannot reach the server. Check your connection.');
}

class UnknownFailure extends BookingFailure {
  const UnknownFailure(super.message);
}

/// Translates a Supabase or transport error into a typed failure.
/// Widgets must never see a [PostgrestException].
BookingFailure mapPostgrestError(Object error) {
  if (error is BookingFailure) return error;
  if (error is SocketException) return const NetworkFailure();

  final code = switch (error) {
    PostgrestException(:final code) => code,
    AuthException() => '42501',
    _ => null,
  };
  final message = switch (error) {
    PostgrestException(:final message) => message,
    AuthException(:final message) => message,
    _ => error.toString(),
  };

  return switch (code) {
    '23P01' => const UnitUnavailable(),
    'P0006' => const HoldExpired(),
    'P0007' => QuoteStale(message),
    'P0008' || '42501' => const NotPermitted(),
    'P0002' => const NotFound(),
    'P0003' || 'P0004' || 'P0005' || 'P0009' => InvalidState(message),
    _ => UnknownFailure(message),
  };
}
```

`lib/core/env.dart`:

```dart
import 'package:flutter/foundation.dart';

/// Supabase connection details, supplied with --dart-define.
///
/// The default host differs per platform because a local Supabase bound to
/// 127.0.0.1 is not reachable at that address from an Android emulator.
class Env {
  const Env._();

  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get supabaseUrl {
    if (_url.isNotEmpty) return _url;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:54321';
    }
    return 'http://127.0.0.1:54321';
  }

  static String get supabaseAnonKey {
    assert(_anonKey.isNotEmpty,
        'Pass --dart-define=SUPABASE_ANON_KEY=... (see .env.example)');
    return _anonKey;
  }
}
```

`lib/core/supabase_client.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );
}

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);
```

`lib/core/format.dart`:

```dart
import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _day = DateFormat('EEE, d MMM');

String formatInr(num amount) => _inr.format(amount);
String formatDay(DateTime d) => _day.format(d);
```

`lib/core/theme/app_theme.dart`:

```dart
import 'package:flutter/material.dart';

ThemeData buildTheme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorSchemeSeed: const Color(0xFF2E6B4F),
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
```

`lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/supabase_client.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const ProviderScope(child: PasalaApp()));
}

class PasalaApp extends StatelessWidget {
  const PasalaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Pasala Resorts',
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const Scaffold(body: Center(child: Text('Pasala'))),
      );
}
```

`main.dart` gains its router in Task 13.

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `flutter test test/core/errors_test.dart && flutter analyze`
Expected: 6 tests pass, analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/core test/core lib/main.dart
git commit -m "feat(app): add env, Supabase client, typed error mapping, and theme"
```

---

### Task 12: Models and repositories

**Files:**
- Create: `lib/data/models/property.dart`, `lib/data/models/unit.dart`, `lib/data/models/slot_type.dart`, `lib/data/models/quote.dart`, `lib/data/models/reservation.dart`, `lib/data/models/availability.dart`, `lib/data/models/app_user.dart`, `lib/data/repositories/catalog_repository.dart`, `lib/data/repositories/booking_repository.dart`, `lib/data/repositories/auth_repository.dart`
- Test: `test/data/quote_test.dart`, `test/data/reservation_test.dart`

**Interfaces:**
- Consumes: `mapPostgrestError`, `supabaseProvider` (Task 11); the RPC surface from Tasks 5, 6, and 8.
- Produces:
  - `Quote` with `int guests, List<QuoteLine> lines, num subtotal, num cleaningFee, num total, String currency`; `QuoteLine` with `DateTime date, String label, num amount, int extraGuests, num extraGuestAmount`.
  - `Reservation` with `String id, String unitId, DateTime start, DateTime end, ReservationKind kind, ReservationStatus status, String? customerId, int? guests, Quote? quote, DateTime? holdExpiresAt, String? blockReason`; getters `bool get isHold`, `Duration? get holdRemaining`.
  - `UnitAvailability` with `String unitId, String unitName, String propertyId, BookingMode bookingMode, bool isAvailable, List<DateTimeRange> busyPeriods`.
  - `CatalogRepository`: `Future<List<Property>> properties()`, `Future<Property> property(String id)`, `Future<List<Unit>> units(String propertyId)`, `Future<List<SlotType>> slotTypes(String propertyId)`.
  - `BookingRepository`: `Future<List<UnitAvailability>> search({String? propertyId, required DateTime from, required DateTime to, int guests = 1, String? slotTypeId})`, `Future<Quote> quote({required String unitId, required DateTime from, required DateTime to, required int guests, String? slotTypeId})`, `Future<Reservation> createHold({required String unitId, required DateTime from, required DateTime to, required int guests, String? slotTypeId, num? expectedTotal})`, `Future<Reservation> confirm({required String reservationId, required String paymentRef, required num amount})`, `Future<Reservation> cancel({required String reservationId, required String reason})`, `Future<List<Reservation>> myBookings()`, `Future<List<Reservation>> allBookings({DateTime? from, DateTime? to})`, `Future<List<Reservation>> blockDates({required String unitId, required List<DateTimeRange> ranges, required String reason})`, `Stream<List<Reservation>> watchUnit(String unitId)`.
  - `AuthRepository`: `Future<AppUser> signIn(String email, String password)`, `Future<AppUser> signUp({required String email, required String password, required String fullName})`, `Future<void> signOut()`, `Future<AppUser?> current()`, `Stream<AppUser?> watch()`.
  - Providers: `catalogRepositoryProvider`, `bookingRepositoryProvider`, `authRepositoryProvider`.

  All repository methods wrap every call in `try/catch` and rethrow
  `mapPostgrestError(e)`.

- [ ] **Step 1: Write the failing tests**

`test/data/quote_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/quote.dart';

void main() {
  const json = {
    'unit_id': 'b1',
    'currency': 'INR',
    'guests': 6,
    'lines': [
      {
        'date': '2026-08-03',
        'label': 'Weekend rate',
        'amount': 12000,
        'rate_rule_id': 'r1',
        'extra_guests': 2,
        'extra_guest_amount': 3000,
      }
    ],
    'subtotal': 15000,
    'cleaning_fee': 1500,
    'total': 16500,
  };

  test('parses the server quote shape', () {
    final quote = Quote.fromJson(json);
    expect(quote.guests, 6);
    expect(quote.lines.single.date, DateTime.utc(2026, 8, 3));
    expect(quote.lines.single.label, 'Weekend rate');
    expect(quote.total, 16500);
  });

  test('total comes from the server, never recomputed', () {
    final quote = Quote.fromJson({...json, 'total': 99999});
    expect(quote.total, 99999);
  });
}
```

The second test is the guard for the "no pricing arithmetic in Dart"
constraint: if anyone later derives `total` from the lines, it fails.

`test/data/reservation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';

void main() {
  Map<String, dynamic> json(String status, String? holdExpiry) => {
        'id': 'c1',
        'unit_id': 'b1',
        'period': '["2026-08-03 08:30:00+00","2026-08-04 05:30:00+00")',
        'kind': 'booking',
        'status': status,
        'customer_id': 'u1',
        'guests': 4,
        'quote': null,
        'hold_expires_at': holdExpiry,
        'block_reason': null,
      };

  test('parses a tstzrange into start and end', () {
    final r = Reservation.fromJson(json('confirmed', null));
    expect(r.start, DateTime.parse('2026-08-03 08:30:00Z'));
    expect(r.end, DateTime.parse('2026-08-04 05:30:00Z'));
    expect(r.status, ReservationStatus.confirmed);
  });

  test('an unexpired hold reports remaining time', () {
    final expiry = DateTime.now().toUtc().add(const Duration(minutes: 10));
    final r = Reservation.fromJson(json('hold', expiry.toIso8601String()));
    expect(r.isHold, isTrue);
    expect(r.holdRemaining!.inMinutes, closeTo(9, 1));
  });

  test('an expired hold reports zero remaining', () {
    final expiry = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    final r = Reservation.fromJson(json('hold', expiry.toIso8601String()));
    expect(r.holdRemaining, Duration.zero);
  });
}
```

- [ ] **Step 2: Run them to make sure they fail**

Run: `flutter test test/data`
Expected: FAIL — `Target of URI doesn't exist: 'package:pasala/data/models/quote.dart'`.

- [ ] **Step 3: Write the models**

`lib/data/models/quote.dart`:

```dart
class QuoteLine {
  const QuoteLine({
    required this.date,
    required this.label,
    required this.amount,
    required this.extraGuests,
    required this.extraGuestAmount,
  });

  final DateTime date;
  final String label;
  final num amount;
  final int extraGuests;
  final num extraGuestAmount;

  factory QuoteLine.fromJson(Map<String, dynamic> json) => QuoteLine(
        date: DateTime.parse('${json['date']}T00:00:00Z'),
        label: json['label'] as String,
        amount: json['amount'] as num,
        extraGuests: (json['extra_guests'] as num?)?.toInt() ?? 0,
        extraGuestAmount: json['extra_guest_amount'] as num? ?? 0,
      );
}

class Quote {
  const Quote({
    required this.currency,
    required this.guests,
    required this.lines,
    required this.subtotal,
    required this.cleaningFee,
    required this.total,
  });

  final String currency;
  final int guests;
  final List<QuoteLine> lines;
  final num subtotal;
  final num cleaningFee;

  /// Server-computed. Never derived from [lines] — the server is the only
  /// authority on price.
  final num total;

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        currency: json['currency'] as String? ?? 'INR',
        guests: (json['guests'] as num).toInt(),
        lines: (json['lines'] as List<dynamic>)
            .map((e) => QuoteLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        subtotal: json['subtotal'] as num,
        cleaningFee: json['cleaning_fee'] as num,
        total: json['total'] as num,
      );
}
```

`lib/data/models/reservation.dart`:

```dart
import 'quote.dart';

enum ReservationKind { booking, block, ota }

enum ReservationStatus { hold, pendingPayment, confirmed, cancelled }

ReservationStatus _status(String raw) => switch (raw) {
      'hold' => ReservationStatus.hold,
      'pending_payment' => ReservationStatus.pendingPayment,
      'confirmed' => ReservationStatus.confirmed,
      'cancelled' => ReservationStatus.cancelled,
      _ => throw ArgumentError('unknown status $raw'),
    };

/// Parses a Postgres tstzrange literal: ["2026-08-03 08:30:00+00","...")
({DateTime start, DateTime end}) parsePeriod(String raw) {
  final parts = raw
      .substring(1, raw.length - 1)
      .split(',')
      .map((s) => s.replaceAll('"', '').trim())
      .toList();
  return (
    start: DateTime.parse(parts[0].replaceFirst(' ', 'T')).toUtc(),
    end: DateTime.parse(parts[1].replaceFirst(' ', 'T')).toUtc(),
  );
}

class Reservation {
  const Reservation({
    required this.id,
    required this.unitId,
    required this.start,
    required this.end,
    required this.kind,
    required this.status,
    this.customerId,
    this.guests,
    this.quote,
    this.holdExpiresAt,
    this.blockReason,
  });

  final String id;
  final String unitId;
  final DateTime start;
  final DateTime end;
  final ReservationKind kind;
  final ReservationStatus status;
  final String? customerId;
  final int? guests;
  final Quote? quote;
  final DateTime? holdExpiresAt;
  final String? blockReason;

  bool get isHold => status == ReservationStatus.hold;

  Duration? get holdRemaining {
    final expiry = holdExpiresAt;
    if (expiry == null) return null;
    final left = expiry.difference(DateTime.now().toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  factory Reservation.fromJson(Map<String, dynamic> json) {
    final period = parsePeriod(json['period'] as String);
    return Reservation(
      id: json['id'] as String,
      unitId: json['unit_id'] as String,
      start: period.start,
      end: period.end,
      kind: ReservationKind.values.byName(json['kind'] as String),
      status: _status(json['status'] as String),
      customerId: json['customer_id'] as String?,
      guests: (json['guests'] as num?)?.toInt(),
      quote: json['quote'] == null
          ? null
          : Quote.fromJson(json['quote'] as Map<String, dynamic>),
      holdExpiresAt: json['hold_expires_at'] == null
          ? null
          : DateTime.parse(json['hold_expires_at'] as String).toUtc(),
      blockReason: json['block_reason'] as String?,
    );
  }
}
```

`lib/data/models/property.dart`:

```dart
class Property {
  const Property({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.address,
    required this.images,
    required this.amenities,
    required this.checkInTime,
    required this.checkOutTime,
    required this.isActive,
  });

  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? address;
  final List<String> images;
  final List<String> amenities;
  final String checkInTime;
  final String checkOutTime;
  final bool isActive;

  factory Property.fromJson(Map<String, dynamic> json) => Property(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        description: json['description'] as String?,
        address: json['address'] as String?,
        images: (json['images'] as List<dynamic>? ?? []).cast<String>(),
        amenities: (json['amenities'] as List<dynamic>? ?? []).cast<String>(),
        checkInTime: json['check_in_time'] as String? ?? '14:00',
        checkOutTime: json['check_out_time'] as String? ?? '11:00',
        isActive: json['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toInsert() => {
        'name': name,
        'slug': slug,
        'description': description,
        'address': address,
        'images': images,
        'amenities': amenities,
        'check_in_time': checkInTime,
        'check_out_time': checkOutTime,
        'is_active': isActive,
      };
}
```

`lib/data/models/unit.dart`:

```dart
enum BookingMode { nightly, slot, both }

class Unit {
  const Unit({
    required this.id,
    required this.propertyId,
    required this.name,
    required this.capacityBase,
    required this.capacityMax,
    required this.bookingMode,
    required this.isActive,
    this.description,
  });

  final String id;
  final String propertyId;
  final String name;
  final String? description;
  final int capacityBase;
  final int capacityMax;
  final BookingMode bookingMode;
  final bool isActive;

  bool get supportsNightly => bookingMode != BookingMode.slot;
  bool get supportsSlots => bookingMode != BookingMode.nightly;

  factory Unit.fromJson(Map<String, dynamic> json) => Unit(
        id: json['id'] as String,
        propertyId: json['property_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        capacityBase: (json['capacity_base'] as num).toInt(),
        capacityMax: (json['capacity_max'] as num).toInt(),
        bookingMode: BookingMode.values.byName(json['booking_mode'] as String),
        isActive: json['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toInsert() => {
        'property_id': propertyId,
        'name': name,
        'description': description,
        'capacity_base': capacityBase,
        'capacity_max': capacityMax,
        'booking_mode': bookingMode.name,
        'is_active': isActive,
      };
}
```

`lib/data/models/slot_type.dart`:

```dart
enum SlotCode { day, night, fullDay }

SlotCode _slotCode(String raw) => switch (raw) {
      'day' => SlotCode.day,
      'night' => SlotCode.night,
      'full_day' => SlotCode.fullDay,
      _ => throw ArgumentError('unknown slot code $raw'),
    };

class SlotType {
  const SlotType({
    required this.id,
    required this.propertyId,
    required this.code,
    required this.startTime,
    required this.endTime,
  });

  final String id;
  final String propertyId;
  final SlotCode code;
  final String startTime;
  final String endTime;

  String get label => switch (code) {
        SlotCode.day => 'Day ($startTime–$endTime)',
        SlotCode.night => 'Night ($startTime–$endTime)',
        SlotCode.fullDay => 'Full day ($startTime–$endTime)',
      };

  factory SlotType.fromJson(Map<String, dynamic> json) => SlotType(
        id: json['id'] as String,
        propertyId: json['property_id'] as String,
        code: _slotCode(json['code'] as String),
        startTime: (json['start_time'] as String).substring(0, 5),
        endTime: (json['end_time'] as String).substring(0, 5),
      );
}
```

`lib/data/models/availability.dart`:

```dart
import 'package:flutter/material.dart' show DateTimeRange;

import 'reservation.dart';
import 'unit.dart';

class UnitAvailability {
  const UnitAvailability({
    required this.unitId,
    required this.propertyId,
    required this.unitName,
    required this.bookingMode,
    required this.isAvailable,
    required this.busyPeriods,
  });

  final String unitId;
  final String propertyId;
  final String unitName;
  final BookingMode bookingMode;
  final bool isAvailable;
  final List<DateTimeRange> busyPeriods;

  factory UnitAvailability.fromJson(Map<String, dynamic> json) =>
      UnitAvailability(
        unitId: json['unit_id'] as String,
        propertyId: json['property_id'] as String,
        unitName: json['unit_name'] as String,
        bookingMode: BookingMode.values.byName(json['booking_mode'] as String),
        isAvailable: json['is_available'] as bool,
        busyPeriods: (json['busy_periods'] as List<dynamic>? ?? [])
            .map((raw) {
              final p = parsePeriod(raw as String);
              return DateTimeRange(start: p.start.toLocal(), end: p.end.toLocal());
            })
            .toList(),
      );
}
```

`lib/data/models/app_user.dart`:

```dart
enum UserRole { customer, staff, admin, accountant, superAdmin }

UserRole roleFromDb(String raw) => switch (raw) {
      'customer' => UserRole.customer,
      'staff' => UserRole.staff,
      'admin' => UserRole.admin,
      'accountant' => UserRole.accountant,
      'super_admin' => UserRole.superAdmin,
      _ => UserRole.customer,
    };

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.role,
    this.fullName,
    this.phone,
  });

  final String id;
  final String email;
  final String? fullName;
  final String? phone;
  final UserRole role;

  bool get isAdmin => role == UserRole.admin || role == UserRole.superAdmin;
  bool get isStaffOrAbove => role != UserRole.customer;
}
```

- [ ] **Step 4: Run the model tests and make sure they pass**

Run: `flutter test test/data`
Expected: PASS, 5 tests.

- [ ] **Step 5: Write the repositories**

`lib/data/repositories/catalog_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/property.dart';
import '../models/slot_type.dart';
import '../models/unit.dart';

class CatalogRepository {
  CatalogRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<List<Property>> properties() => _guard(() async {
        final rows = await _db.from('properties').select().order('name');
        return rows.map(Property.fromJson).toList();
      });

  Future<Property> property(String id) => _guard(() async {
        final row = await _db.from('properties').select().eq('id', id).single();
        return Property.fromJson(row);
      });

  Future<List<Unit>> units(String propertyId) => _guard(() async {
        final rows = await _db
            .from('units')
            .select()
            .eq('property_id', propertyId)
            .order('name');
        return rows.map(Unit.fromJson).toList();
      });

  Future<List<SlotType>> slotTypes(String propertyId) => _guard(() async {
        final rows =
            await _db.from('slot_types').select().eq('property_id', propertyId);
        return rows.map(SlotType.fromJson).toList();
      });

  Future<Property> upsertProperty(Property property, {String? id}) =>
      _guard(() async {
        final payload = property.toInsert();
        final row = id == null
            ? await _db.from('properties').insert(payload).select().single()
            : await _db
                .from('properties')
                .update(payload)
                .eq('id', id)
                .select()
                .single();
        return Property.fromJson(row);
      });

  Future<Unit> upsertUnit(Unit unit, {String? id}) => _guard(() async {
        final payload = unit.toInsert();
        final row = id == null
            ? await _db.from('units').insert(payload).select().single()
            : await _db.from('units').update(payload).eq('id', id).select().single();
        return Unit.fromJson(row);
      });
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(supabaseProvider)),
);
```

`lib/data/repositories/booking_repository.dart`:

```dart
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/availability.dart';
import '../models/quote.dart';
import '../models/reservation.dart';

String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class BookingRepository {
  BookingRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<List<UnitAvailability>> search({
    String? propertyId,
    required DateTime from,
    required DateTime to,
    int guests = 1,
    String? slotTypeId,
  }) =>
      _guard(() async {
        final rows = await _db.rpc('search_availability', params: {
          'p_property_id': propertyId,
          'p_from': _d(from),
          'p_to': _d(to),
          'p_guests': guests,
          'p_slot_type_id': slotTypeId,
        }) as List<dynamic>;
        return rows
            .map((e) => UnitAvailability.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<Quote> quote({
    required String unitId,
    required DateTime from,
    required DateTime to,
    required int guests,
    String? slotTypeId,
  }) =>
      _guard(() async {
        final period = await _db.rpc('build_period', params: {
          'p_unit_id': unitId,
          'p_from': _d(from),
          'p_to': _d(to),
          'p_slot_type_id': slotTypeId,
        });
        final json = await _db.rpc('get_quote', params: {
          'p_unit_id': unitId,
          'p_period': period,
          'p_guests': guests,
          'p_slot_type_id': slotTypeId,
        });
        return Quote.fromJson(json as Map<String, dynamic>);
      });

  Future<Reservation> createHold({
    required String unitId,
    required DateTime from,
    required DateTime to,
    required int guests,
    String? slotTypeId,
    num? expectedTotal,
  }) =>
      _guard(() async {
        final row = await _db.rpc('create_hold', params: {
          'p_unit_id': unitId,
          'p_from': _d(from),
          'p_to': _d(to),
          'p_guests': guests,
          'p_slot_type_id': slotTypeId,
          'p_expected_total': expectedTotal,
        });
        return Reservation.fromJson(row as Map<String, dynamic>);
      });

  Future<Reservation> confirm({
    required String reservationId,
    required String paymentRef,
    required num amount,
  }) =>
      _guard(() async {
        final row = await _db.rpc('confirm_booking', params: {
          'p_reservation_id': reservationId,
          'p_payment_ref': paymentRef,
          'p_amount': amount,
        });
        return Reservation.fromJson(row as Map<String, dynamic>);
      });

  Future<Reservation> cancel({
    required String reservationId,
    required String reason,
  }) =>
      _guard(() async {
        final row = await _db.rpc('cancel_booking', params: {
          'p_reservation_id': reservationId,
          'p_reason': reason,
        });
        return Reservation.fromJson(row as Map<String, dynamic>);
      });

  Future<List<Reservation>> blockDates({
    required String unitId,
    required List<DateTimeRange> ranges,
    required String reason,
  }) =>
      _guard(() async {
        final rows = await _db.rpc('block_dates', params: {
          'p_unit_id': unitId,
          // daterange is [), so the upper bound is the day after the last
          // blocked date.
          'p_ranges': ranges
              .map((r) => '[${_d(r.start)},${_d(r.end.add(const Duration(days: 1)))})')
              .toList(),
          'p_reason': reason,
        }) as List<dynamic>;
        return rows
            .map((e) => Reservation.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<List<Reservation>> myBookings() => _guard(() async {
        final uid = _db.auth.currentUser?.id;
        if (uid == null) throw const NotPermitted();
        final rows = await _db
            .from('reservations')
            .select()
            .eq('customer_id', uid)
            .order('period', ascending: false);
        return rows.map(Reservation.fromJson).toList();
      });

  Future<List<Reservation>> allBookings({DateTime? from, DateTime? to}) =>
      _guard(() async {
        final rows =
            await _db.from('reservations').select().order('period');
        return rows
            .map(Reservation.fromJson)
            .where((r) =>
                (from == null || r.end.isAfter(from)) &&
                (to == null || r.start.isBefore(to)))
            .toList();
      });

  Stream<List<Reservation>> watchUnit(String unitId) => _db
      .from('reservations')
      .stream(primaryKey: ['id'])
      .eq('unit_id', unitId)
      .map((rows) => rows.map(Reservation.fromJson).toList());
}

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => BookingRepository(ref.watch(supabaseProvider)),
);
```

`lib/data/repositories/auth_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/app_user.dart';

class AuthRepository {
  AuthRepository(this._db);
  final SupabaseClient _db;

  Future<AppUser> _profileFor(User user) async {
    final row =
        await _db.from('profiles').select().eq('id', user.id).maybeSingle();
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      fullName: row?['full_name'] as String?,
      phone: row?['phone'] as String?,
      role: roleFromDb(row?['role'] as String? ?? 'customer'),
    );
  }

  Future<AppUser> signIn(String email, String password) async {
    try {
      final res = await _db.auth
          .signInWithPassword(email: email, password: password);
      return _profileFor(res.user!);
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<AppUser> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final res = await _db.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );
      return _profileFor(res.user!);
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<void> signOut() => _db.auth.signOut();

  Future<AppUser?> current() async {
    final user = _db.auth.currentUser;
    return user == null ? null : _profileFor(user);
  }

  Stream<AppUser?> watch() => _db.auth.onAuthStateChange.asyncMap(
        (state) async => state.session == null
            ? null
            : await _profileFor(state.session!.user),
      );
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseProvider)),
);

final currentUserProvider = StreamProvider<AppUser?>((ref) async* {
  final repo = ref.watch(authRepositoryProvider);
  yield await repo.current();
  yield* repo.watch();
});
```

- [ ] **Step 6: Verify the whole suite and analysis**

Run: `flutter test && flutter analyze`
Expected: all tests pass, analyze clean.

- [ ] **Step 7: Commit**

```bash
git add lib/data test/data
git commit -m "feat(app): add models and Supabase-backed repositories"
```

---

### Task 13: Auth screens and the role-aware router

**Files:**
- Create: `lib/core/router.dart`, `lib/features/auth/login_screen.dart`, `lib/features/auth/signup_screen.dart`, `lib/features/shell/app_shell.dart`, `lib/features/shell/not_found_screen.dart`
- Test: `test/features/auth/login_screen_test.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `AuthRepository`, `currentUserProvider`, `AppUser` (Task 12).
- Produces: `routerProvider` (Riverpod `Provider<GoRouter>`) with routes
  `/login`, `/signup`, `/` (browse), `/property/:id`, `/book/:unitId`,
  `/bookings`, `/admin`, `/admin/properties`, `/admin/units/:propertyId`,
  `/admin/rates/:unitId`, `/admin/block/:unitId`, `/admin/bookings`,
  `/staff`; and `AppShell`, the responsive scaffold every screen renders
  inside. Later tasks add screens at these paths only.

- [ ] **Step 1: Write the failing test**

`test/features/auth/login_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/auth/login_screen.dart';

void main() {
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
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/features/auth/login_screen_test.dart`
Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Write the screens and the router**

`lib/features/auth/login_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../data/repositories/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(_email.text.trim(), _password.text);
      if (mounted) context.go('/');
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  Text('Pasala Resorts',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('login-email'),
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter your email' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('login-password'),
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Enter your password'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: const Text('Sign in'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/signup'),
                    child: const Text('Create an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
```

`lib/features/auth/signup_screen.dart` is the same structure with a `Full name`
field (`Key('signup-name')`), `Key('signup-email')`, `Key('signup-password')`,
a `FilledButton` labelled `Create account`, and a call to
`ref.read(authRepositoryProvider).signUp(email: ..., password: ..., fullName: ...)`
followed by `context.go('/')`. Validators: name and email non-empty, password
at least 8 characters with the message `Use at least 8 characters`.

`lib/features/shell/app_shell.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_user.dart';
import '../../data/repositories/auth_repository.dart';

/// Responsive chrome shared by every signed-in screen: a bottom navigation
/// bar on narrow layouts, a navigation rail on wide ones. Destinations vary
/// by role, but the router redirect is what actually blocks access.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  static const _customerDestinations = [
    (path: '/', icon: Icons.home_outlined, label: 'Browse'),
    (path: '/bookings', icon: Icons.event_outlined, label: 'Bookings'),
  ];

  static const _adminDestinations = [
    (path: '/', icon: Icons.home_outlined, label: 'Browse'),
    (path: '/bookings', icon: Icons.event_outlined, label: 'Bookings'),
    (path: '/admin', icon: Icons.settings_outlined, label: 'Admin'),
  ];

  static const _staffDestinations = [
    (path: '/', icon: Icons.home_outlined, label: 'Browse'),
    (path: '/staff', icon: Icons.task_alt_outlined, label: 'Today'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final destinations = switch (user?.role) {
      UserRole.admin || UserRole.superAdmin => _adminDestinations,
      UserRole.staff || UserRole.accountant => _staffDestinations,
      _ => _customerDestinations,
    };

    final location = GoRouterState.of(context).uri.path;
    var index = destinations.indexWhere((d) => location == d.path);
    if (index < 0) index = 0;

    void go(int i) => context.go(destinations[i].path);

    final wide = MediaQuery.sizeOf(context).width >= 840;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pasala Resorts'),
        actions: [
          if (user != null)
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await ref.read(authRepositoryProvider).signOut();
                if (context.mounted) context.go('/login');
              },
            ),
        ],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: go,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final d in destinations)
                    NavigationRailDestination(
                        icon: Icon(d.icon), label: Text(d.label)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: child),
            ])
          : child,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: go,
              destinations: [
                for (final d in destinations)
                  NavigationDestination(icon: Icon(d.icon), label: d.label),
              ],
            ),
    );
  }
}
```

`lib/features/shell/not_found_screen.dart`:

```dart
import 'package:flutter/material.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Page not found')),
      );
}
```

`lib/core/router.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/app_user.dart';
import '../data/repositories/auth_repository.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/not_found_screen.dart';

/// Route guarding is user experience only. RLS in Postgres is what actually
/// enforces access; a customer who forges a route sees a not-found page and
/// would get 42501 from the database regardless.
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(currentUserProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final user = auth.valueOrNull;
      final loggingIn =
          state.matchedLocation == '/login' || state.matchedLocation == '/signup';

      if (user == null) return loggingIn ? null : '/login';
      if (loggingIn) return '/';

      final path = state.matchedLocation;
      if (path.startsWith('/admin') && !user.isAdmin) return '/404';
      if (path.startsWith('/staff') && !user.isStaffOrAbove) return '/404';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/404', builder: (_, __) => const NotFoundScreen()),
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          // Screens are added by Tasks 14 through 21 at these paths.
        ],
      ),
    ],
    errorBuilder: (_, __) => const NotFoundScreen(),
  );
});
```

Update `lib/main.dart` to use it:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/supabase_client.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const ProviderScope(child: PasalaApp()));
}

class PasalaApp extends ConsumerWidget {
  const PasalaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'Pasala Resorts',
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        routerConfig: ref.watch(routerProvider),
      );
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `flutter test && flutter analyze`
Expected: all pass. `flutter run` is not expected to render a home screen yet —
the shell has no child routes until Task 14.

- [ ] **Step 5: Commit**

```bash
git add lib/core/router.dart lib/features lib/main.dart test/features
git commit -m "feat(app): add auth screens, responsive shell, and role-aware router"
```

---

### Task 14: Browse — property list and detail

**Files:**
- Create: `lib/features/browse/browse_screen.dart`, `lib/features/browse/property_screen.dart`, `lib/features/browse/providers.dart`
- Test: `test/features/browse/property_card_test.dart`
- Modify: `lib/core/router.dart`

**Interfaces:**
- Consumes: `CatalogRepository`, `Property`, `Unit`, `SlotType` (Task 12).
- Produces: `propertiesProvider` (`FutureProvider<List<Property>>`),
  `propertyProvider` (`FutureProvider.family<Property, String>`),
  `unitsProvider` (`FutureProvider.family<List<Unit>, String>`),
  `slotTypesProvider` (`FutureProvider.family<List<SlotType>, String>`), and
  the widget `PropertyCard`, reused by Task 21's admin list.

- [ ] **Step 1: Write the failing test**

`test/features/browse/property_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/features/browse/browse_screen.dart';

void main() {
  const property = Property(
    id: 'a1',
    name: 'Pasala Riverside',
    slug: 'riverside',
    description: 'Riverside farmhouse with private pool.',
    address: 'Shamirpet, Hyderabad',
    images: [],
    amenities: ['Pool', 'Wi-Fi'],
    checkInTime: '14:00',
    checkOutTime: '11:00',
    isActive: true,
  );

  testWidgets('renders name, address, and amenities', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PropertyCard(property: property)),
    ));

    expect(find.text('Pasala Riverside'), findsOneWidget);
    expect(find.text('Shamirpet, Hyderabad'), findsOneWidget);
    expect(find.text('Pool'), findsOneWidget);
    expect(find.text('Wi-Fi'), findsOneWidget);
  });

  testWidgets('shows check-in and check-out times', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PropertyCard(property: property)),
    ));

    expect(find.textContaining('14:00'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/features/browse/property_card_test.dart`
Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Write the providers and screens**

`lib/features/browse/providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/property.dart';
import '../../data/models/slot_type.dart';
import '../../data/models/unit.dart';
import '../../data/repositories/catalog_repository.dart';

final propertiesProvider = FutureProvider<List<Property>>(
  (ref) => ref.watch(catalogRepositoryProvider).properties(),
);

final propertyProvider = FutureProvider.family<Property, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).property(id),
);

final unitsProvider = FutureProvider.family<List<Unit>, String>(
  (ref, propertyId) => ref.watch(catalogRepositoryProvider).units(propertyId),
);

final slotTypesProvider = FutureProvider.family<List<SlotType>, String>(
  (ref, propertyId) =>
      ref.watch(catalogRepositoryProvider).slotTypes(propertyId),
);
```

`lib/features/browse/browse_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/property.dart';
import 'providers.dart';

class BrowseScreen extends ConsumerWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(propertiesProvider);

    return properties.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(propertiesProvider),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PropertyCard(
              property: list[i],
              onTap: () => context.go('/property/${list[i].id}'),
            ),
          ),
        ),
      ),
    );
  }
}

class PropertyCard extends StatelessWidget {
  const PropertyCard({super.key, required this.property, this.onTap});

  final Property property;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(property.name,
                    style: Theme.of(context).textTheme.titleLarge),
                if (property.address != null) ...[
                  const SizedBox(height: 4),
                  Text(property.address!,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
                const SizedBox(height: 8),
                Text('Check-in ${property.checkInTime} · '
                    'Check-out ${property.checkOutTime}'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final a in property.amenities) Chip(label: Text(a)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}
```

`lib/features/browse/property_screen.dart` renders `propertyProvider(id)` and
`unitsProvider(id)`: the description, an amenity `Wrap`, then one `ListTile`
per unit showing `unit.name`, `Sleeps ${unit.capacityBase}–${unit.capacityMax}`,
and a mode chip reading `Nightly`, `Slots`, or `Nightly or slots`, each
navigating to `/book/${unit.id}`. Follow the `when(loading/error/data)`
structure used above.

Add both routes inside the `ShellRoute` in `lib/core/router.dart`:

```dart
GoRoute(path: '/', builder: (_, __) => const BrowseScreen()),
GoRoute(
  path: '/property/:id',
  builder: (_, state) =>
      PropertyScreen(propertyId: state.pathParameters['id']!),
),
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `flutter test && flutter analyze`
Expected: all pass.

- [ ] **Step 5: Verify against the seeded database**

```bash
make run-web
```

Sign in as `ravi@example.com` / `password123`. Expected: two property cards;
tapping Riverside lists Whole Villa, Garden Room, and Pool Deck.

- [ ] **Step 6: Commit**

```bash
git add lib/features/browse lib/core/router.dart test/features/browse
git commit -m "feat(app): add property browsing and detail screens"
```

---

### Task 15: Availability calendar with realtime updates

**Files:**
- Create: `lib/features/calendar/availability_calendar.dart`, `lib/features/calendar/providers.dart`
- Test: `test/features/calendar/availability_calendar_test.dart`

**Interfaces:**
- Consumes: `BookingRepository.watchUnit`, `Reservation` (Task 12).
- Produces:
  - `enum DayStatus { available, booked, blocked, pending, past }`
  - `DayStatus statusFor(DateTime day, List<Reservation> reservations, {DateTime? today})` — pure, unit-testable, the only place day colouring is decided.
  - `unitReservationsProvider` (`StreamProvider.family<List<Reservation>, String>`)
  - widget `AvailabilityCalendar({required String unitId, required DateTime month, DateTime? selectedStart, DateTime? selectedEnd, void Function(DateTime)? onDayTap})`

  Task 16 uses this widget for date selection; Task 20 reuses it for admin
  blocking.

- [ ] **Step 1: Write the failing test**

`test/features/calendar/availability_calendar_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/features/calendar/availability_calendar.dart';

void main() {
  Reservation res({
    required String start,
    required String end,
    ReservationKind kind = ReservationKind.booking,
    ReservationStatus status = ReservationStatus.confirmed,
  }) =>
      Reservation(
        id: 'r',
        unitId: 'u',
        start: DateTime.parse(start),
        end: DateTime.parse(end),
        kind: kind,
        status: status,
      );

  final today = DateTime(2026, 8, 1);

  test('a day inside a confirmed booking is booked', () {
    final list = [res(start: '2026-08-03T14:00', end: '2026-08-05T11:00')];
    expect(statusFor(DateTime(2026, 8, 4), list, today: today),
        DayStatus.booked);
  });

  test('the checkout day is available again', () {
    final list = [res(start: '2026-08-03T14:00', end: '2026-08-05T11:00')];
    expect(statusFor(DateTime(2026, 8, 5), list, today: today),
        DayStatus.available);
  });

  test('an admin block renders as blocked, not booked', () {
    final list = [
      res(start: '2026-08-10T14:00', end: '2026-08-12T11:00',
          kind: ReservationKind.block)
    ];
    expect(statusFor(DateTime(2026, 8, 11), list, today: today),
        DayStatus.blocked);
  });

  test('an active hold renders as pending', () {
    final list = [
      res(start: '2026-08-20T14:00', end: '2026-08-21T11:00',
          status: ReservationStatus.hold)
    ];
    expect(statusFor(DateTime(2026, 8, 20), list, today: today),
        DayStatus.pending);
  });

  test('a cancelled reservation does not mark the day', () {
    final list = [
      res(start: '2026-08-03T14:00', end: '2026-08-05T11:00',
          status: ReservationStatus.cancelled)
    ];
    expect(statusFor(DateTime(2026, 8, 4), list, today: today),
        DayStatus.available);
  });

  test('a day before today is past', () {
    expect(statusFor(DateTime(2026, 7, 31), const [], today: today),
        DayStatus.past);
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/features/calendar`
Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Write the calendar**

`lib/features/calendar/providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/reservation.dart';
import '../../data/repositories/booking_repository.dart';

/// Live reservations for one unit. An admin block or a competing booking
/// updates every open calendar without a refresh.
final unitReservationsProvider =
    StreamProvider.family<List<Reservation>, String>(
  (ref, unitId) => ref.watch(bookingRepositoryProvider).watchUnit(unitId),
);
```

`lib/features/calendar/availability_calendar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/reservation.dart';
import 'providers.dart';

enum DayStatus { available, booked, blocked, pending, past }

/// Decides one day's status. Pure so the rule is testable without a widget.
/// A day counts as occupied when the reservation covers its check-in moment,
/// so an 11:00 checkout leaves that day available for a 14:00 arrival.
DayStatus statusFor(
  DateTime day,
  List<Reservation> reservations, {
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final dayStart = DateTime(day.year, day.month, day.day);
  final todayStart = DateTime(now.year, now.month, now.day);
  if (dayStart.isBefore(todayStart)) return DayStatus.past;

  final dayEnd = dayStart.add(const Duration(days: 1));
  var result = DayStatus.available;

  for (final r in reservations) {
    if (r.status == ReservationStatus.cancelled) continue;
    final start = r.start.toLocal();
    final end = r.end.toLocal();
    // Overlap test against the calendar day, excluding a checkout that
    // lands at or before this day's start.
    if (!start.isBefore(dayEnd) || !end.isAfter(dayStart)) continue;
    // A stay ending during this day frees it for the next arrival.
    if (end.isBefore(dayStart.add(const Duration(hours: 12))) &&
        start.isBefore(dayStart)) {
      continue;
    }

    final status = switch (r) {
      _ when r.kind == ReservationKind.block => DayStatus.blocked,
      _ when r.status == ReservationStatus.hold ||
              r.status == ReservationStatus.pendingPayment =>
        DayStatus.pending,
      _ => DayStatus.booked,
    };
    // Booked outranks blocked outranks pending when several overlap.
    if (status == DayStatus.booked) return DayStatus.booked;
    if (status == DayStatus.blocked || result == DayStatus.available) {
      result = status;
    }
  }
  return result;
}

class AvailabilityCalendar extends ConsumerWidget {
  const AvailabilityCalendar({
    super.key,
    required this.unitId,
    required this.month,
    this.selectedStart,
    this.selectedEnd,
    this.onDayTap,
  });

  final String unitId;
  final DateTime month;
  final DateTime? selectedStart;
  final DateTime? selectedEnd;
  final void Function(DateTime day)? onDayTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservations =
        ref.watch(unitReservationsProvider(unitId)).valueOrNull ?? const [];
    final scheme = Theme.of(context).colorScheme;

    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = first.weekday - 1; // Monday-first grid

    Color colorFor(DayStatus s) => switch (s) {
          DayStatus.available => scheme.surfaceContainerHighest,
          DayStatus.booked => scheme.errorContainer,
          DayStatus.blocked => scheme.outlineVariant,
          DayStatus.pending => scheme.tertiaryContainer,
          DayStatus.past => scheme.surface,
        };

    bool isSelected(DateTime d) {
      final s = selectedStart, e = selectedEnd;
      if (s == null) return false;
      if (e == null) return DateUtils.isSameDay(d, s);
      return !d.isBefore(DateUtils.dateOnly(s)) &&
          !d.isAfter(DateUtils.dateOnly(e));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final label in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(child: Center(child: Text(label))),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: leadingBlanks + daysInMonth,
          itemBuilder: (context, i) {
            if (i < leadingBlanks) return const SizedBox.shrink();
            final day = DateTime(month.year, month.month, i - leadingBlanks + 1);
            final status = statusFor(day, reservations);
            final selectable =
                status == DayStatus.available && onDayTap != null;

            return InkWell(
              key: Key('day-${day.day}'),
              onTap: selectable ? () => onDayTap!(day) : null,
              child: Container(
                decoration: BoxDecoration(
                  color: colorFor(status),
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected(day)
                      ? Border.all(color: scheme.primary, width: 2)
                      : null,
                ),
                child: Center(
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      color: status == DayStatus.past
                          ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
                          : null,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 12, children: [
          for (final (status, label) in [
            (DayStatus.available, 'Available'),
            (DayStatus.booked, 'Booked'),
            (DayStatus.blocked, 'Blocked'),
            (DayStatus.pending, 'On hold'),
          ])
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 12,
                  decoration: BoxDecoration(
                      color: colorFor(status),
                      borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 4),
              Text(label),
            ]),
        ]),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `flutter test test/features/calendar && flutter analyze`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar test/features/calendar
git commit -m "feat(app): add realtime availability calendar"
```

---

### Task 16: Booking flow — dates, quote, hold timer, mock payment

**Files:**
- Create: `lib/features/booking/booking_screen.dart`, `lib/features/booking/quote_sheet.dart`, `lib/features/booking/payment_gateway.dart`, `lib/features/booking/providers.dart`, `lib/features/booking/confirmation_screen.dart`
- Test: `test/features/booking/payment_gateway_test.dart`, `test/features/booking/quote_sheet_test.dart`
- Modify: `lib/core/router.dart`

**Interfaces:**
- Consumes: `BookingRepository`, `Quote`, `Reservation` (Task 12); `AvailabilityCalendar` (Task 15).
- Produces:
  - `abstract interface class PaymentGateway { Future<PaymentResult> charge({required String reservationId, required num amount}); }`
  - `class PaymentResult { final bool succeeded; final String reference; final String? failureMessage; }`
  - `class MockGateway implements PaymentGateway` with `MockGateway({bool alwaysFail = false, Duration latency = const Duration(milliseconds: 400)})`
  - `paymentGatewayProvider` (`Provider<PaymentGateway>`, returns `MockGateway()`)
  - `QuoteSheet({required Quote quote, required VoidCallback onPay, required bool busy})`

  Phase 2 replaces the provider's implementation with `RazorpayGateway`;
  nothing else changes.

- [ ] **Step 1: Write the failing tests**

`test/features/booking/payment_gateway_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/booking/payment_gateway.dart';

void main() {
  test('mock gateway succeeds and returns a reference', () async {
    final result = await MockGateway(latency: Duration.zero)
        .charge(reservationId: 'c1', amount: 11500);

    expect(result.succeeded, isTrue);
    expect(result.reference, startsWith('mock_'));
    expect(result.reference, contains('c1'));
  });

  test('mock gateway can be configured to fail', () async {
    final result = await MockGateway(alwaysFail: true, latency: Duration.zero)
        .charge(reservationId: 'c1', amount: 11500);

    expect(result.succeeded, isFalse);
    expect(result.failureMessage, isNotNull);
  });
}
```

`test/features/booking/quote_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/quote.dart';
import 'package:pasala/features/booking/quote_sheet.dart';

void main() {
  final quote = Quote.fromJson(const {
    'currency': 'INR',
    'guests': 6,
    'lines': [
      {'date': '2026-08-03', 'label': 'Weekend rate', 'amount': 12000,
       'extra_guests': 2, 'extra_guest_amount': 3000},
    ],
    'subtotal': 15000,
    'cleaning_fee': 1500,
    'total': 16500,
  });

  testWidgets('renders the server total verbatim', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: QuoteSheet(quote: quote, busy: false, onPay: () {}),
      ),
    ));

    expect(find.text('₹16,500'), findsOneWidget);
    expect(find.text('Weekend rate'), findsOneWidget);
    expect(find.textContaining('Cleaning'), findsOneWidget);
  });

  testWidgets('the pay button is disabled while busy', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: QuoteSheet(quote: quote, busy: true, onPay: () {}),
      ),
    ));

    final button = tester.widget<FilledButton>(
        find.byKey(const Key('pay-button')));
    expect(button.onPressed, isNull);
  });
}
```

- [ ] **Step 2: Run them to make sure they fail**

Run: `flutter test test/features/booking`
Expected: FAIL — the URIs do not exist.

- [ ] **Step 3: Write the gateway and the quote sheet**

`lib/features/booking/payment_gateway.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PaymentResult {
  const PaymentResult.success(this.reference)
      : succeeded = true,
        failureMessage = null;

  const PaymentResult.failure(this.failureMessage)
      : succeeded = false,
        reference = '';

  final bool succeeded;
  final String reference;
  final String? failureMessage;
}

/// The seam phase 2 replaces with Razorpay. Everything upstream of this
/// interface — hold creation, confirmation, calendar updates — is already
/// exercised by the mock, so swapping the implementation changes no other file.
abstract interface class PaymentGateway {
  Future<PaymentResult> charge({
    required String reservationId,
    required num amount,
  });
}

class MockGateway implements PaymentGateway {
  const MockGateway({
    this.alwaysFail = false,
    this.latency = const Duration(milliseconds: 400),
  });

  final bool alwaysFail;
  final Duration latency;

  @override
  Future<PaymentResult> charge({
    required String reservationId,
    required num amount,
  }) async {
    await Future<void>.delayed(latency);
    if (alwaysFail) {
      return const PaymentResult.failure('Mock gateway declined the payment.');
    }
    return PaymentResult.success(
        'mock_${reservationId}_${amount.toStringAsFixed(0)}');
  }
}

final paymentGatewayProvider =
    Provider<PaymentGateway>((ref) => const MockGateway());
```

`lib/features/booking/quote_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/models/quote.dart';

/// Displays a server-computed quote. This widget performs no arithmetic:
/// every figure shown comes straight from [Quote].
class QuoteSheet extends StatelessWidget {
  const QuoteSheet({
    super.key,
    required this.quote,
    required this.onPay,
    required this.busy,
  });

  final Quote quote;
  final VoidCallback onPay;
  final bool busy;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Price breakdown',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final line in quote.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text('${formatDay(line.date)} · ${line.label}')),
                  Text(formatInr(line.amount)),
                ]),
              ),
            for (final line in quote.lines)
              if (line.extraGuests > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                        child: Text('${formatDay(line.date)} · '
                            '${line.extraGuests} extra guests')),
                    Text(formatInr(line.extraGuestAmount)),
                  ]),
                ),
            const Divider(),
            Row(children: [
              const Expanded(child: Text('Cleaning fee')),
              Text(formatInr(quote.cleaningFee)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: Text('Total',
                      style: Theme.of(context).textTheme.titleLarge)),
              Text(formatInr(quote.total),
                  style: Theme.of(context).textTheme.titleLarge),
            ]),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('pay-button'),
              onPressed: busy ? null : onPay,
              child: Text(busy ? 'Processing…' : 'Pay and confirm'),
            ),
          ],
        ),
      );
}
```

- [ ] **Step 4: Run those tests and make sure they pass**

Run: `flutter test test/features/booking`
Expected: PASS, 4 tests.

- [ ] **Step 5: Write the booking screen**

`lib/features/booking/booking_screen.dart` is a `ConsumerStatefulWidget` taking
`unitId`. State: `DateTime? _from`, `DateTime? _to`, `int _guests = 2`,
`String? _slotTypeId`, `DateTime _month`, `Quote? _quote`, `Reservation? _hold`,
`bool _busy`, `Timer? _ticker`.

Behaviour, in order:

1. Render `AvailabilityCalendar(unitId: unitId, month: _month, selectedStart: _from, selectedEnd: _to, onDayTap: _pickDay)`. `_pickDay` sets `_from` when empty or when both are set; otherwise sets `_to` and, if the tapped day is before `_from`, swaps them.
2. A guest `Slider` or stepper bounded by the unit's `capacityMax`, and — when `unit.supportsSlots` — a `SegmentedButton` of the property's slot types plus a `Nightly` option. Selecting a slot sets `_to = _from`.
3. When `_from` and `_to` are both set, call `bookingRepositoryProvider.quote(...)` and store the result in `_quote`.
4. Show `QuoteSheet` in a `showModalBottomSheet`. `onPay` runs `_pay`.
5. `_pay`:

```dart
Future<void> _pay() async {
  setState(() => _busy = true);
  try {
    final repo = ref.read(bookingRepositoryProvider);
    final hold = _hold ??= await repo.createHold(
      unitId: widget.unitId,
      from: _from!,
      to: _to!,
      guests: _guests,
      slotTypeId: _slotTypeId,
      expectedTotal: _quote!.total,
    );
    _startHoldTicker();

    final payment = await ref.read(paymentGatewayProvider).charge(
          reservationId: hold.id,
          amount: _quote!.total,
        );
    if (!payment.succeeded) {
      throw InvalidState(payment.failureMessage ?? 'Payment failed');
    }

    final confirmed = await repo.confirm(
      reservationId: hold.id,
      paymentRef: payment.reference,
      amount: _quote!.total,
    );
    if (mounted) context.go('/booking/${confirmed.id}');
  } on BookingFailure catch (e) {
    _handleFailure(e);
  } finally {
    if (mounted) setState(() => _busy = false);
  }
}
```

6. `_handleFailure` maps failures to recovery, closing the sheet first:

```dart
void _handleFailure(BookingFailure failure) {
  if (!mounted) return;
  Navigator.of(context).maybePop();
  switch (failure) {
    case UnitUnavailable():
      setState(() { _hold = null; _to = null; _quote = null; });
      ref.invalidate(unitReservationsProvider(widget.unitId));
    case HoldExpired():
      setState(() { _hold = null; _quote = null; });  // dates kept
    case QuoteStale():
      setState(() { _hold = null; _quote = null; });  // re-quote on rebuild
    default:
      break;
  }
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(failure.message)));
}
```

7. `_startHoldTicker` runs a one-second `Timer.periodic` that calls `setState` so a banner reading `Holding your dates — 14:32 left` counts down from `_hold!.holdRemaining`. At `Duration.zero` it cancels itself, clears `_hold`, and shows the `HoldExpired` message. Cancel the timer in `dispose`.

`lib/features/booking/confirmation_screen.dart` takes a `reservationId`, loads
the reservation, and shows a success icon, the unit name, the stay dates via
`formatDay`, the total from `reservation.quote!.total` via `formatInr`, and
buttons for `View my bookings` (`/bookings`) and `Browse more` (`/`).

Add the routes inside `ShellRoute`:

```dart
GoRoute(
  path: '/book/:unitId',
  builder: (_, state) =>
      BookingScreen(unitId: state.pathParameters['unitId']!),
),
GoRoute(
  path: '/booking/:id',
  builder: (_, state) =>
      ConfirmationScreen(reservationId: state.pathParameters['id']!),
),
```

- [ ] **Step 6: Verify the full flow against the seeded database**

```bash
make run-web
```

Sign in as `ravi@example.com` / `password123`, book Garden Room for two nights,
and confirm. Then, in a second browser window signed in as
`meera@example.com`, attempt the same dates. Expected: the second attempt shows
`Those dates were just taken.` and the calendar repaints without a reload.

- [ ] **Step 7: Run the suite and commit**

```bash
flutter test && flutter analyze
git add lib/features/booking lib/core/router.dart test/features/booking
git commit -m "feat(app): add booking flow with hold timer and mock gateway"
```

---

### Task 17: My bookings and cancellation

**Files:**
- Create: `lib/features/account/my_bookings_screen.dart`, `lib/features/account/booking_detail_screen.dart`, `lib/features/account/providers.dart`
- Test: `test/features/account/booking_tile_test.dart`
- Modify: `lib/core/router.dart`

**Interfaces:**
- Consumes: `BookingRepository.myBookings`, `BookingRepository.cancel`, `Reservation` (Task 12).
- Produces: `myBookingsProvider` (`FutureProvider<List<Reservation>>`) and the
  widget `BookingTile({required Reservation reservation, VoidCallback? onTap})`,
  reused by Task 21's admin list.

- [ ] **Step 1: Write the failing test**

`test/features/account/booking_tile_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/features/account/my_bookings_screen.dart';

void main() {
  Reservation res(ReservationStatus status) => Reservation(
        id: 'c1',
        unitId: 'b1',
        start: DateTime(2026, 8, 3, 14),
        end: DateTime(2026, 8, 5, 11),
        kind: ReservationKind.booking,
        status: status,
        guests: 4,
      );

  testWidgets('shows the stay dates and a status chip', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BookingTile(reservation: res(ReservationStatus.confirmed))),
    ));

    expect(find.textContaining('3 Aug'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
  });

  testWidgets('a cancelled booking is labelled cancelled', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BookingTile(reservation: res(ReservationStatus.cancelled))),
    ));

    expect(find.text('Cancelled'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/features/account`
Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Write the screens**

`lib/features/account/providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/reservation.dart';
import '../../data/repositories/booking_repository.dart';

final myBookingsProvider = FutureProvider<List<Reservation>>(
  (ref) => ref.watch(bookingRepositoryProvider).myBookings(),
);
```

`lib/features/account/my_bookings_screen.dart` imports `../../core/format.dart`
(for `formatDay`), `../../data/models/reservation.dart`, and `providers.dart`,
then renders `myBookingsProvider`
with the usual `when(loading/error/data)`, an empty state reading
`No bookings yet.`, and one `BookingTile` per reservation navigating to
`/booking-detail/:id`. `BookingTile`:

```dart
class BookingTile extends StatelessWidget {
  const BookingTile({super.key, required this.reservation, this.onTap});

  final Reservation reservation;
  final VoidCallback? onTap;

  String get _statusLabel => switch (reservation.status) {
        ReservationStatus.hold => 'On hold',
        ReservationStatus.pendingPayment => 'Payment due',
        ReservationStatus.confirmed => 'Confirmed',
        ReservationStatus.cancelled => 'Cancelled',
      };

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: onTap,
          title: Text('${formatDay(reservation.start.toLocal())} → '
              '${formatDay(reservation.end.toLocal())}'),
          subtitle: reservation.guests == null
              ? null
              : Text('${reservation.guests} guests'),
          trailing: Chip(label: Text(_statusLabel)),
        ),
      );
}
```

`lib/features/account/booking_detail_screen.dart` shows the stay dates, guest
count, the stored `quote` breakdown (reuse `QuoteSheet`'s line layout, without
the pay button), and a `Cancel booking` `OutlinedButton` shown only when
`reservation.status == ReservationStatus.confirmed`. The button opens an
`AlertDialog` with a reason `TextField` and, on confirm, calls
`bookingRepositoryProvider.cancel(reservationId: id, reason: reason)`, then
invalidates `myBookingsProvider` and pops. Catch `BookingFailure` and show
`e.message` in a `SnackBar`.

Add the routes inside `ShellRoute`:

```dart
GoRoute(path: '/bookings', builder: (_, __) => const MyBookingsScreen()),
GoRoute(
  path: '/booking-detail/:id',
  builder: (_, state) =>
      BookingDetailScreen(reservationId: state.pathParameters['id']!),
),
```

- [ ] **Step 4: Run the tests and verify manually**

Run: `flutter test && flutter analyze`
Then `make run-web`: as `ravi@example.com`, open Bookings, cancel the seeded
stay, and confirm those dates turn available on the unit's calendar without a
reload.

- [ ] **Step 5: Commit**

```bash
git add lib/features/account lib/core/router.dart test/features/account
git commit -m "feat(app): add my bookings list, detail, and cancellation"
```

---

### Task 18: Admin — properties and units CRUD

**Files:**
- Create: `lib/features/admin/admin_home_screen.dart`, `lib/features/admin/property_form_screen.dart`, `lib/features/admin/units_screen.dart`, `lib/features/admin/unit_form_screen.dart`
- Test: `test/features/admin/unit_form_test.dart`
- Modify: `lib/core/router.dart`

**Interfaces:**
- Consumes: `CatalogRepository.upsertProperty`, `CatalogRepository.upsertUnit`, `propertiesProvider`, `unitsProvider` (Tasks 12, 14).
- Produces: `AdminHomeScreen` (the `/admin` landing with links to Properties,
  Bookings, and Today), plus the four admin routes listed below.

- [ ] **Step 1: Write the failing test**

`test/features/admin/unit_form_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/admin/unit_form_screen.dart';

void main() {
  testWidgets('rejects max capacity below base capacity', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: UnitFormScreen(propertyId: 'a1'),
    ));

    await tester.enterText(find.byKey(const Key('unit-name')), 'Villa');
    await tester.enterText(find.byKey(const Key('unit-capacity-base')), '8');
    await tester.enterText(find.byKey(const Key('unit-capacity-max')), '4');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(find.text('Max must be at least the base capacity'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/features/admin`
Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Write the screens**

`lib/features/admin/admin_home_screen.dart` is a `ListView` of `ListTile`s:
`Properties` (`/admin/properties`), `All bookings` (`/admin/bookings`),
`Today` (`/staff`).

`lib/features/admin/property_form_screen.dart` takes an optional
`Property? existing` and edits name, slug, description, address, check-in time,
check-out time (both via `showTimePicker`, stored as `HH:mm`), amenities (a
comma-separated `TextField` split on `,` and trimmed), and an `is_active`
`Switch`. `Save` calls `upsertProperty(property, id: existing?.id)`, invalidates
`propertiesProvider`, and pops.

`lib/features/admin/units_screen.dart` lists `unitsProvider(propertyId)` with a
trailing overflow menu per unit offering `Edit`, `Rates`
(`/admin/rates/:unitId`), and `Block dates` (`/admin/block/:unitId`), plus a
`FloatingActionButton` for a new unit.

`lib/features/admin/unit_form_screen.dart` takes `required String propertyId`
and an optional `Unit? existing`. Fields keyed `unit-name`,
`unit-capacity-base`, `unit-capacity-max`, a `SegmentedButton<BookingMode>`,
and an active `Switch`. Validation:

```dart
validator: (v) {
  final max = int.tryParse(v ?? '');
  final base = int.tryParse(_capacityBase.text);
  if (max == null || max < 1) return 'Enter a number';
  if (base != null && max < base) {
    return 'Max must be at least the base capacity';
  }
  return null;
},
```

`Save` calls `upsertUnit(unit, id: existing?.id)`, invalidates
`unitsProvider(propertyId)`, and pops. A unit created without a base rate rule
cannot be quoted, so after a successful create, show a `SnackBar` reading
`Unit created. Add a base rate before it can be booked.` and navigate to
`/admin/rates/${created.id}`.

Add the routes inside `ShellRoute`:

```dart
GoRoute(path: '/admin', builder: (_, __) => const AdminHomeScreen()),
GoRoute(path: '/admin/properties', builder: (_, __) => const AdminPropertiesScreen()),
GoRoute(
  path: '/admin/units/:propertyId',
  builder: (_, state) =>
      UnitsScreen(propertyId: state.pathParameters['propertyId']!),
),
```

`AdminPropertiesScreen` lives in `property_form_screen.dart`'s file as a small
list widget reusing `PropertyCard` from Task 14, each card navigating to
`/admin/units/${property.id}` and carrying an edit action.

- [ ] **Step 4: Run the tests and verify manually**

Run: `flutter test && flutter analyze`
Then `make run-web`: sign in as `admin@pasala.test` / `password123`, create a
unit, and confirm the Admin destination is absent when signed in as
`ravi@example.com` and that navigating to `/admin` directly shows the
not-found page.

- [ ] **Step 5: Commit**

```bash
git add lib/features/admin lib/core/router.dart test/features/admin
git commit -m "feat(app): add admin property and unit management"
```

---

### Task 19: Admin — rate rules

**Files:**
- Create: `lib/features/admin/rate_rules_screen.dart`, `lib/data/models/rate_rule.dart`, `lib/data/repositories/rate_repository.dart`
- Test: `test/data/rate_rule_test.dart`
- Modify: `lib/core/router.dart`

**Interfaces:**
- Consumes: `mapPostgrestError`, `supabaseProvider` (Task 11).
- Produces:
  - `RateRule` with `String id, String unitId, RateKind kind, String? label, String? slotTypeId, DateTime? validFrom, DateTime? validTo, List<int> weekdays, num price, num extraGuestPrice, num cleaningFee, int priority`
  - `enum RateKind { base, weekend, override_ }` — `override` is a Dart reserved-adjacent name, so the enum member is `override_` and maps to the database value `override`.
  - `RateRepository` with `Future<List<RateRule>> forUnit(String unitId)`, `Future<RateRule> upsert(RateRule rule, {String? id})`, `Future<void> delete(String id)`
  - `rateRepositoryProvider`, `rateRulesProvider` (`FutureProvider.family<List<RateRule>, String>`)

- [ ] **Step 1: Write the failing test**

`test/data/rate_rule_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/rate_rule.dart';

void main() {
  test('maps the override kind to and from the database value', () {
    final rule = RateRule.fromJson(const {
      'id': 'r1',
      'unit_id': 'b1',
      'kind': 'override',
      'label': 'Diwali season',
      'price': 8100,
      'extra_guest_price': 800,
      'cleaning_fee': 600,
      'priority': 50,
      'valid_from': '2026-11-06',
      'valid_to': '2026-11-12',
      'weekdays': null,
    });

    expect(rule.kind, RateKind.override_);
    expect(rule.validFrom, DateTime.parse('2026-11-06'));
    expect(rule.toInsert()['kind'], 'override');
  });

  test('parses weekday arrays', () {
    final rule = RateRule.fromJson(const {
      'id': 'r2', 'unit_id': 'b1', 'kind': 'weekend', 'price': 6300,
      'extra_guest_price': 800, 'cleaning_fee': 600, 'priority': 10,
      'weekdays': [6, 7], 'valid_from': null, 'valid_to': null, 'label': null,
    });

    expect(rule.weekdays, [6, 7]);
    expect(rule.kind, RateKind.weekend);
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/data/rate_rule_test.dart`
Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Write the model, repository, and screen**

`lib/data/models/rate_rule.dart`:

```dart
enum RateKind { base, weekend, override_ }

RateKind rateKindFromDb(String raw) => switch (raw) {
      'base' => RateKind.base,
      'weekend' => RateKind.weekend,
      'override' => RateKind.override_,
      _ => throw ArgumentError('unknown rate kind $raw'),
    };

String rateKindToDb(RateKind kind) => switch (kind) {
      RateKind.base => 'base',
      RateKind.weekend => 'weekend',
      RateKind.override_ => 'override',
    };

class RateRule {
  const RateRule({
    required this.id,
    required this.unitId,
    required this.kind,
    required this.price,
    required this.extraGuestPrice,
    required this.cleaningFee,
    required this.priority,
    this.label,
    this.slotTypeId,
    this.validFrom,
    this.validTo,
    this.weekdays = const [],
  });

  final String id;
  final String unitId;
  final RateKind kind;
  final String? label;
  final String? slotTypeId;
  final DateTime? validFrom;
  final DateTime? validTo;
  final List<int> weekdays;
  final num price;
  final num extraGuestPrice;
  final num cleaningFee;
  final int priority;

  factory RateRule.fromJson(Map<String, dynamic> json) => RateRule(
        id: json['id'] as String,
        unitId: json['unit_id'] as String,
        kind: rateKindFromDb(json['kind'] as String),
        label: json['label'] as String?,
        slotTypeId: json['slot_type_id'] as String?,
        validFrom: json['valid_from'] == null
            ? null
            : DateTime.parse(json['valid_from'] as String),
        validTo: json['valid_to'] == null
            ? null
            : DateTime.parse(json['valid_to'] as String),
        weekdays:
            (json['weekdays'] as List<dynamic>? ?? []).map((e) => e as int).toList(),
        price: json['price'] as num,
        extraGuestPrice: json['extra_guest_price'] as num,
        cleaningFee: json['cleaning_fee'] as num,
        priority: (json['priority'] as num).toInt(),
      );

  Map<String, dynamic> toInsert() => {
        'unit_id': unitId,
        'kind': rateKindToDb(kind),
        'label': label,
        'slot_type_id': slotTypeId,
        'valid_from': validFrom?.toIso8601String().substring(0, 10),
        'valid_to': validTo?.toIso8601String().substring(0, 10),
        'weekdays': weekdays.isEmpty ? null : weekdays,
        'price': price,
        'extra_guest_price': extraGuestPrice,
        'cleaning_fee': cleaningFee,
        'priority': priority,
      };
}
```

`lib/data/repositories/rate_repository.dart` follows the `_guard` pattern from
Task 12, querying `from('rate_rules')` filtered by `unit_id` and ordered by
`priority` descending, with `upsert` and `delete`.

`lib/features/admin/rate_rules_screen.dart` lists the unit's rules grouped by
kind, each showing label, price, priority, and — for overrides — the date
range. A `FloatingActionButton` opens a form with: kind
(`SegmentedButton<RateKind>`), label, price, extra guest price, cleaning fee,
priority, an optional date range via `showDateRangePicker` (required and
enforced when kind is `override_`, matching the `rate_rules_override_dates`
constraint), and weekday `FilterChip`s numbered 1–7 with Monday first. Save
calls `upsert`, invalidates `rateRulesProvider(unitId)`, and pops.

Add the route inside `ShellRoute`:

```dart
GoRoute(
  path: '/admin/rates/:unitId',
  builder: (_, state) =>
      RateRulesScreen(unitId: state.pathParameters['unitId']!),
),
```

- [ ] **Step 4: Run the tests and verify manually**

Run: `flutter test && flutter analyze`
Then `make run-web` as `admin@pasala.test`: add an override for a future week at
double the base price, then open the customer booking screen for that unit and
confirm the quote for those dates reflects it.

- [ ] **Step 5: Commit**

```bash
git add lib/features/admin/rate_rules_screen.dart lib/data/models/rate_rule.dart lib/data/repositories/rate_repository.dart lib/core/router.dart test/data/rate_rule_test.dart
git commit -m "feat(app): add admin rate rule management"
```

---

### Task 20: Admin — date blocking

**Files:**
- Create: `lib/features/admin/block_dates_screen.dart`
- Test: `test/features/admin/block_selection_test.dart`
- Modify: `lib/core/router.dart`

**Interfaces:**
- Consumes: `BookingRepository.blockDates` (Task 12), `AvailabilityCalendar`, `unitReservationsProvider` (Task 15).
- Produces: `List<DateTimeRange> collapseToRanges(Set<DateTime> days)` — pure,
  converts a set of individually tapped days into contiguous ranges so that
  three adjacent taps become one reservation row rather than three.

The SRS requires blocking a single date, several dates, and a range. All three
are the same gesture here: tap days, and adjacent selections collapse.

- [ ] **Step 1: Write the failing test**

`test/features/admin/block_selection_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/admin/block_dates_screen.dart';

void main() {
  test('a single day becomes one range', () {
    final ranges = collapseToRanges({DateTime(2026, 8, 3)});
    expect(ranges, hasLength(1));
    expect(ranges.single.start, DateTime(2026, 8, 3));
    expect(ranges.single.end, DateTime(2026, 8, 3));
  });

  test('adjacent days collapse into one range', () {
    final ranges = collapseToRanges({
      DateTime(2026, 8, 3),
      DateTime(2026, 8, 4),
      DateTime(2026, 8, 5),
    });
    expect(ranges, hasLength(1));
    expect(ranges.single.start, DateTime(2026, 8, 3));
    expect(ranges.single.end, DateTime(2026, 8, 5));
  });

  test('a gap splits the selection into two ranges', () {
    final ranges = collapseToRanges({
      DateTime(2026, 8, 3),
      DateTime(2026, 8, 4),
      DateTime(2026, 8, 9),
    });
    expect(ranges, hasLength(2));
    expect(ranges.first.end, DateTime(2026, 8, 4));
    expect(ranges.last.start, DateTime(2026, 8, 9));
  });

  test('unsorted input is handled', () {
    final ranges = collapseToRanges({
      DateTime(2026, 8, 5),
      DateTime(2026, 8, 3),
      DateTime(2026, 8, 4),
    });
    expect(ranges, hasLength(1));
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/features/admin/block_selection_test.dart`
Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Write the screen**

`lib/features/admin/block_dates_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/repositories/booking_repository.dart';
import '../calendar/availability_calendar.dart';
import '../calendar/providers.dart';

/// Collapses individually selected days into contiguous ranges, so three
/// adjacent taps produce one reservation row instead of three.
List<DateTimeRange> collapseToRanges(Set<DateTime> days) {
  if (days.isEmpty) return const [];
  final sorted = days.map(DateUtils.dateOnly).toList()..sort();

  final ranges = <DateTimeRange>[];
  var start = sorted.first;
  var previous = sorted.first;

  for (final day in sorted.skip(1)) {
    if (day.difference(previous).inDays == 1) {
      previous = day;
      continue;
    }
    ranges.add(DateTimeRange(start: start, end: previous));
    start = day;
    previous = day;
  }
  ranges.add(DateTimeRange(start: start, end: previous));
  return ranges;
}

class BlockDatesScreen extends ConsumerStatefulWidget {
  const BlockDatesScreen({super.key, required this.unitId});
  final String unitId;

  @override
  ConsumerState<BlockDatesScreen> createState() => _BlockDatesScreenState();
}

class _BlockDatesScreenState extends ConsumerState<BlockDatesScreen> {
  final _selected = <DateTime>{};
  final _reason = TextEditingController();
  DateTime _month = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected.isEmpty || _reason.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(bookingRepositoryProvider).blockDates(
            unitId: widget.unitId,
            ranges: collapseToRanges(_selected),
            reason: _reason.text.trim(),
          );
      ref.invalidate(unitReservationsProvider(widget.unitId));
      if (mounted) {
        setState(_selected.clear);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Dates blocked')));
      }
    } on BookingFailure catch (e) {
      // A UnitUnavailable here means a real booking is in the way; the
      // admin must cancel it deliberately rather than block over it.
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() =>
                  _month = DateTime(_month.year, _month.month - 1)),
            ),
            Expanded(
              child: Center(child: Text('${_month.month}/${_month.year}')),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() =>
                  _month = DateTime(_month.year, _month.month + 1)),
            ),
          ]),
          AvailabilityCalendar(
            unitId: widget.unitId,
            month: _month,
            onDayTap: (day) => setState(() {
              _selected.contains(day)
                  ? _selected.remove(day)
                  : _selected.add(day);
            }),
          ),
          const SizedBox(height: 16),
          Text('${_selected.length} days selected · '
              '${collapseToRanges(_selected).length} ranges'),
          const SizedBox(height: 8),
          TextField(
            key: const Key('block-reason'),
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Maintenance, private event, owner stay…',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || _selected.isEmpty ? null : _save,
            child: const Text('Block selected dates'),
          ),
        ],
      );
}
```

Selected days are not highlighted by `AvailabilityCalendar`'s
`selectedStart`/`selectedEnd`, which model a contiguous stay. Multi-select
highlighting comes from the day cells turning `DayStatus.blocked` after saving;
before saving, the count line above the reason field is the feedback.

Add the route inside `ShellRoute`:

```dart
GoRoute(
  path: '/admin/block/:unitId',
  builder: (_, state) =>
      BlockDatesScreen(unitId: state.pathParameters['unitId']!),
),
```

- [ ] **Step 4: Run the tests and verify manually**

Run: `flutter test && flutter analyze`
Then `make run-web` as `admin@pasala.test`: block three adjacent days plus one
separate day on Garden Room. Expected: two rows created; the customer calendar
for that unit shows all four days blocked without a reload; attempting to block
a day inside an existing confirmed booking shows
`Those dates were just taken.`

- [ ] **Step 5: Commit**

```bash
git add lib/features/admin/block_dates_screen.dart lib/core/router.dart test/features/admin/block_selection_test.dart
git commit -m "feat(app): add admin date blocking with range collapsing"
```

---

### Task 21: Admin bookings list and staff arrivals and departures

**Files:**
- Create: `lib/features/admin/admin_bookings_screen.dart`, `lib/features/staff/today_screen.dart`, `lib/features/staff/providers.dart`
- Test: `test/features/staff/today_partition_test.dart`
- Modify: `lib/core/router.dart`

**Interfaces:**
- Consumes: `BookingRepository.allBookings` (Task 12), `BookingTile` (Task 17).
- Produces: `({List<Reservation> arrivals, List<Reservation> departures, List<Reservation> staying}) partitionToday(List<Reservation> all, DateTime today)` — pure, decides which stays appear in each staff list.

- [ ] **Step 1: Write the failing test**

`test/features/staff/today_partition_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/features/staff/today_screen.dart';

void main() {
  Reservation res(String start, String end,
          {ReservationStatus status = ReservationStatus.confirmed,
          ReservationKind kind = ReservationKind.booking}) =>
      Reservation(
        id: '$start-$end',
        unitId: 'b1',
        start: DateTime.parse(start),
        end: DateTime.parse(end),
        kind: kind,
        status: status,
      );

  final today = DateTime(2026, 8, 4);

  test('a stay starting today is an arrival', () {
    final p = partitionToday(
        [res('2026-08-04T14:00', '2026-08-06T11:00')], today);
    expect(p.arrivals, hasLength(1));
    expect(p.departures, isEmpty);
  });

  test('a stay ending today is a departure', () {
    final p = partitionToday(
        [res('2026-08-02T14:00', '2026-08-04T11:00')], today);
    expect(p.departures, hasLength(1));
    expect(p.arrivals, isEmpty);
  });

  test('a stay spanning today is staying', () {
    final p = partitionToday(
        [res('2026-08-02T14:00', '2026-08-06T11:00')], today);
    expect(p.staying, hasLength(1));
  });

  test('cancelled stays and admin blocks are excluded', () {
    final p = partitionToday([
      res('2026-08-04T14:00', '2026-08-06T11:00',
          status: ReservationStatus.cancelled),
      res('2026-08-04T14:00', '2026-08-06T11:00',
          kind: ReservationKind.block),
    ], today);
    expect(p.arrivals, isEmpty);
    expect(p.staying, isEmpty);
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `flutter test test/features/staff`
Expected: FAIL — the URI does not exist.

- [ ] **Step 3: Write the screens**

`lib/features/staff/today_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/reservation.dart';
import '../account/my_bookings_screen.dart' show BookingTile;
import 'providers.dart';

typedef TodayLists = ({
  List<Reservation> arrivals,
  List<Reservation> departures,
  List<Reservation> staying,
});

/// Splits confirmed stays into the three lists staff work from. Blocks and
/// cancellations are not guest activity and are excluded.
TodayLists partitionToday(List<Reservation> all, DateTime today) {
  final day = DateUtils.dateOnly(today);
  final arrivals = <Reservation>[];
  final departures = <Reservation>[];
  final staying = <Reservation>[];

  for (final r in all) {
    if (r.kind != ReservationKind.booking) continue;
    if (r.status != ReservationStatus.confirmed) continue;

    final start = DateUtils.dateOnly(r.start.toLocal());
    final end = DateUtils.dateOnly(r.end.toLocal());

    if (start == day) {
      arrivals.add(r);
    } else if (end == day) {
      departures.add(r);
    } else if (start.isBefore(day) && end.isAfter(day)) {
      staying.add(r);
    }
  }
  return (arrivals: arrivals, departures: departures, staying: staying);
}

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(allBookingsProvider);

    return bookings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (all) {
        final lists = partitionToday(all, DateTime.now());
        Widget section(String title, List<Reservation> items) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('$title (${items.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('None'),
                  ),
                for (final r in items) BookingTile(reservation: r),
              ],
            );

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(allBookingsProvider),
          child: ListView(children: [
            section('Arrivals', lists.arrivals),
            section('Departures', lists.departures),
            section('In house', lists.staying),
          ]),
        );
      },
    );
  }
}
```

`lib/features/staff/providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/reservation.dart';
import '../../data/repositories/booking_repository.dart';

final allBookingsProvider = FutureProvider<List<Reservation>>(
  (ref) => ref.watch(bookingRepositoryProvider).allBookings(),
);
```

`lib/features/admin/admin_bookings_screen.dart` renders `allBookingsProvider`
with a `SegmentedButton` filtering by status (`All`, `On hold`, `Confirmed`,
`Cancelled`) and one `BookingTile` per row, tapping through to
`/booking-detail/:id`. Admins reuse the same detail screen, whose cancel button
is already permitted for them by `cancel_booking`.

Add the routes inside `ShellRoute`:

```dart
GoRoute(path: '/admin/bookings', builder: (_, __) => const AdminBookingsScreen()),
GoRoute(path: '/staff', builder: (_, __) => const TodayScreen()),
```

- [ ] **Step 4: Run the tests and verify manually**

Run: `flutter test && flutter analyze`
Then `make run-web` as `staff@pasala.test`: confirm the Today screen lists the
seeded stay under the right heading, and that `/admin` redirects to the
not-found page for this role.

- [ ] **Step 5: Commit**

```bash
git add lib/features/staff lib/features/admin/admin_bookings_screen.dart lib/core/router.dart test/features/staff
git commit -m "feat(app): add admin bookings list and staff today view"
```

---

### Task 22: Cross-platform verification and README

**Files:**
- Create: `README.md`
- Modify: `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes: everything.
- Produces: a documented, verified build on all three targets. This is the
  task that proves the spec's final success criterion.

Local Supabase serves plain HTTP, which iOS and Android block by default.
Both exemptions below are development-only and must be removed before any
deployed build.

- [ ] **Step 1: Allow cleartext to the local stack on iOS**

In `ios/Runner/Info.plist`, inside the top-level `<dict>`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSExceptionDomains</key>
  <dict>
    <key>localhost</key>
    <dict>
      <key>NSExceptionAllowsInsecureHTTPLoads</key>
      <true/>
    </dict>
    <key>127.0.0.1</key>
    <dict>
      <key>NSExceptionAllowsInsecureHTTPLoads</key>
      <true/>
    </dict>
  </dict>
</dict>
```

- [ ] **Step 2: Allow cleartext to the emulator host on Android**

Create `android/app/src/main/res/xml/network_security_config.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
  <domain-config cleartextTrafficPermitted="true">
    <domain includeSubdomains="false">10.0.2.2</domain>
    <domain includeSubdomains="false">127.0.0.1</domain>
  </domain-config>
</network-security-config>
```

Then add to the `<application>` tag in
`android/app/src/main/AndroidManifest.xml`:

```
android:networkSecurityConfig="@xml/network_security_config"
```

Add `<uses-permission android:name="android.permission.INTERNET"/>` above
`<application>` if it is not already present.

- [ ] **Step 3: Verify the web build**

```bash
make run-web
```

Sign in as `ravi@example.com` / `password123`, complete a booking end to end,
then cancel it.

- [ ] **Step 4: Confirm the Android build compiles**

```bash
flutter build apk --debug --dart-define=SUPABASE_URL=http://10.0.2.2:54321 --dart-define=SUPABASE_ANON_KEY=<local anon key>
```

Expected: the build succeeds. Running it against the local stack on an
emulator is the user's manual check, not this task's.

- [ ] **Step 5: Confirm the iOS build compiles**

```bash
flutter build ios --debug --no-codesign --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=<local anon key>
```

Expected: the build succeeds. Running it on a simulator is the user's manual
check, not this task's.

- [ ] **Step 6: Run the whole suite**

```bash
supabase db reset && supabase test db && flutter test && flutter analyze
```

Expected: every pgTAP file green, every Dart test green, analyze clean. Record
the actual counts — this output is the evidence for the completion claim.

- [ ] **Step 7: Write the README**

`README.md` covers: what phase 1 includes and what it deliberately excludes
(pointing at the spec's phase list); prerequisites (Flutter 3.38.9, Docker,
Supabase CLI); first-run steps (`supabase start`, copy the anon key,
`supabase db reset`, `make run-web`); the seeded accounts and the shared
password; the `make` targets; the per-platform host table; and an explicit
warning that the cleartext exemptions from Steps 1 and 2 are development-only.

- [ ] **Step 8: Commit**

```bash
git add README.md ios/Runner/Info.plist android/app/src/main/AndroidManifest.xml android/app/src/main/res/xml/network_security_config.xml
git commit -m "chore: verify Android, iOS, and web builds and document setup"
```

---

## Spec Coverage

| Spec section | Tasks |
|---|---|
| §3 decisions — one codebase, role-gated | 13 |
| §4 profiles and roles | 3, 9 |
| §4 properties, units, slot types | 4, 18 |
| §4 rate rules and pricing | 5, 19 |
| §4 reservations and exclusion constraint | 6 |
| §4 payments and audit log | 7 |
| §4 RLS | 3, 4, 6, 7, 9 |
| §5 RPC surface, all six functions | 5, 6, 8 |
| §5 workflow steps 1–2, availability | 6, 15, 16 |
| §5 workflow steps 3–4, quote | 5, 16 |
| §5 workflow steps 5–7, hold, pay, confirm, block | 8, 16 |
| §5 workflow steps 8–10, transition records | 7 |
| §5 admin blocking | 8, 20 |
| §5 cancellation | 8, 17 |
| §5 realtime calendar | 15 |
| §6 Flutter structure, router, shell | 11, 12, 13 |
| §7 error handling | 11, 16 |
| §8 testing, all three layers | every task |
| §9 local development, seed, env | 1, 10, 22 |
| §10 success criteria | 8 (race), 15 (realtime), 12 (no client pricing), 9 (RLS), 22 (three platforms) |

## Execution Notes

- Tasks 1–10 are the database and are strictly sequential.
- Tasks 11–13 are the Flutter foundation and are sequential.
- Tasks 14–21 depend on 13 but are largely independent of each other; 16 needs 15, and 17 needs nothing beyond 12.
- Task 22 is last.
