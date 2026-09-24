# ResortHub Tenancy Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the single-business Pasala app into the ResortHub tenancy foundation: per-resort memberships, per-resort data isolation enforced in Postgres, Pasala migrated in as resort #1, and the Flutter app scoped to a current resort.

**Architecture:** Shared tables with a required `property_id` on every resort-owned row. Row-level security and every `security definer` function check the caller's role *at that row's resort* through `has_resort_role`. The app loads the user's memberships, keeps a current resort, and passes its id explicitly to every repository call.

**Tech Stack:** Supabase Postgres 15 (plpgsql, RLS, pgTAP via `supabase test db`), Flutter 3 / Dart, Riverpod, go_router, `shared_preferences`.

**Spec:** `docs/superpowers/specs/2026-09-24-resorthub-tenancy-design.md`

## Global Constraints

- Migrations are `0043_resort_tenancy.sql`, `0044_resort_policies.sql`, `0045_resort_functions.sql`, `0046_drop_global_role_helpers.sql`. Each must apply with `supabase migration up --local` on a database at `0042`, and `supabase db reset` must rebuild from zero.
- New error codes: `P0020 not_a_member`, `P0021 resort_mismatch`, `P0022 resort_suspended`, `P0023 last_owner`. Raise with `raise exception using errcode = 'P0020', message = '...'`.
- Every new or rewritten `security definer` function has `set search_path = public, pg_temp`.
- Resort roles: `owner`, `admin`, `staff`, `accountant` (enum `public.resort_role`). Platform roles: `customer`, `platform_admin` (enum `public.platform_role`).
- Role mapping from the old helpers, used everywhere in this plan:
  - `is_admin()` becomes `owner, admin`
  - `is_staff_or_above()` / `assert_staff()` becomes `owner, admin, staff, accountant`
  - `is_super_admin()` becomes `owner`
  - `current_role() in ('admin','accountant','super_admin')` becomes `owner, admin, accountant`
- The platform admin gets **no** row access to resort-owned tables.
- No service-role key in the client. No in-app account creation.
- UI copy says "Resort"; the table stays `properties`. The `staff` role is labelled "Staff / Incharge".
- Existing code style: repositories wrap calls in `_guard` which maps errors through `mapPostgrestError` (`lib/core/errors.dart`). Keep it.
- Run the database suite with `supabase test db`; the Flutter suite with `flutter test`; static checks with `flutter analyze` (baseline: 3 pre-existing infos, no new ones).
- Never run `dart format` over whole directories — the repo is not formatted with the current SDK and it churns unrelated files. Format only lines you write.

## Review Focus

1. **A person with memberships at two resorts** must never see resort B's rows while working in resort A — in lists (tasks, shifts, bookings, expenses), not only in single-row fetches. RLS lets them read both, so the *app* must filter by the current resort. Owning tasks: 15, 16, 17 (each repository list test asserts the `property_id` filter).
2. **A guest with bookings at two resorts** sees both in My Bookings, each labelled with its resort. Owning task: 20.
3. **The last owner** of a resort cannot be demoted or removed, including two owners demoting each other concurrently. Owning task: 10.
4. **A remembered current resort the user has since been removed from** must be discarded at sign-in, not used. Owning task: 13.
5. **Suspended resort:** staff writes via functions raise `P0022`, direct table writes are refused, the guest can still read and cancel. Owning tasks: 5, 7, 12.

---

## File Structure

**Database**
- Create `supabase/migrations/0043_resort_tenancy.sql` — enums, `properties.status`, `resort_members`, helper functions, `property_id` columns, backfill, parent-match triggers, role move.
- Create `supabase/migrations/0044_resort_policies.sql` — every policy on resort-owned tables and `profiles`, rewritten.
- Create `supabase/migrations/0045_resort_functions.sql` — every existing `security definer` function rewritten; new member-management and platform functions.
- Create `supabase/migrations/0046_drop_global_role_helpers.sql` — `profiles.role` to `platform_role`; drop old helpers and `user_role`.
- Create `supabase/tests/36_resort_tenancy_test.sql` — schema, helpers, backfill, triggers.
- Create `supabase/tests/37_tenancy_isolation_test.sql` — the cross-resort leak suite and catalog guards.
- Create `supabase/tests/38_resort_members_test.sql` — member management and platform functions.
- Modify all 35 existing `supabase/tests/*.sql` — give test users memberships instead of global roles.
- Modify `supabase/seed.sql` — memberships instead of global roles.

**App**
- Create `lib/data/models/resort_membership.dart` — `ResortRole`, `ResortMembership`.
- Modify `lib/data/models/app_user.dart` — `PlatformRole`, `memberships`, `isPlatformAdmin`.
- Modify `lib/data/repositories/auth_repository.dart` — load memberships.
- Create `lib/core/current_resort.dart` — `currentResortProvider` and its persistence.
- Modify `lib/core/router.dart` — membership-based landing and guards; new routes.
- Modify `lib/core/errors.dart` — P0020–P0023.
- Modify every repository under `lib/data/repositories/` that touches resort data — explicit `propertyId`.
- Create `lib/data/repositories/resort_member_repository.dart` — Team.
- Create `lib/data/repositories/platform_repository.dart` — platform functions.
- Create `lib/features/resorts/choose_resort_screen.dart`, `lib/features/resorts/resort_switcher.dart`.
- Create `lib/features/owner/team_screen.dart`; delete `lib/features/admin/users_screen.dart` and `lib/data/repositories/user_admin_repository.dart`.
- Create `lib/features/platform/platform_screen.dart`.
- Modify `lib/features/browse/browse_screen.dart`, account/stay booking lists, welcome screen, `lib/main.dart` title.
- Tests mirror each file under `test/`.

---

## Phase 1 — Database

### Task 1: Resorts, memberships and helper functions

**Files:**
- Create: `supabase/migrations/0043_resort_tenancy.sql`
- Create: `supabase/tests/36_resort_tenancy_test.sql`

**Interfaces:**
- Produces: enum `public.resort_role('owner','admin','staff','accountant')`; enum `public.platform_role('customer','platform_admin')`; column `properties.status text`; table `public.resort_members(property_id, user_id, role, created_at)`; functions `is_platform_admin() returns boolean`, `resort_role(p_property uuid) returns public.resort_role`, `has_resort_role(p_property uuid, p_write boolean, variadic p_roles public.resort_role[]) returns boolean`, `assert_resort_role(p_property uuid, p_write boolean, variadic p_roles public.resort_role[]) returns void`.
- Note: `profiles.role` keeps type `user_role` until Task 12. Until then `is_platform_admin()` reads a new nullable column `profiles.platform_role public.platform_role not null default 'customer'`, which Task 12 folds into `role`.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/36_resort_tenancy_test.sql`:

```sql
begin;
select plan(12);

select enum_has_labels('public','resort_role',
  array['owner','admin','staff','accountant']);
select enum_has_labels('public','platform_role',
  array['customer','platform_admin']);
select has_table('public','resort_members','resort_members exists');
select col_not_null('public','properties','status','properties.status is required');

insert into auth.users (id, email) values
  ('a1000000-0000-0000-0000-000000000001','owner-a@example.com'),
  ('a1000000-0000-0000-0000-000000000002','staff-a@example.com'),
  ('b1000000-0000-0000-0000-000000000001','owner-b@example.com');
insert into public.properties (id, name, slug) values
  ('aaaaaaaa-1111-0000-0000-000000000001','Resort A','resort-a'),
  ('bbbbbbbb-1111-0000-0000-000000000001','Resort B','resort-b');
insert into public.resort_members (property_id, user_id, role) values
  ('aaaaaaaa-1111-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','owner'),
  ('aaaaaaaa-1111-0000-0000-000000000001','a1000000-0000-0000-0000-000000000002','staff'),
  ('bbbbbbbb-1111-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','owner');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(public.resort_role('aaaaaaaa-1111-0000-0000-000000000001'),
          'staff'::public.resort_role, 'staff role at own resort');
select is(public.resort_role('bbbbbbbb-1111-0000-0000-000000000001'),
          null, 'no role at another resort');
select ok(public.has_resort_role('aaaaaaaa-1111-0000-0000-000000000001', true,
          'owner','admin','staff','accountant'), 'staff passes staff-or-above');
select ok(not public.has_resort_role('aaaaaaaa-1111-0000-0000-000000000001', true,
          'owner','admin'), 'staff fails admin check');
select ok(not public.is_platform_admin(), 'staff is not platform admin');

reset role;
update public.properties set status = 'suspended'
  where id = 'aaaaaaaa-1111-0000-0000-000000000001';
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"a1000000-0000-0000-0000-000000000002","role":"authenticated"}';

select ok(public.has_resort_role('aaaaaaaa-1111-0000-0000-000000000001', false,
          'owner','admin','staff','accountant'), 'suspended resort: reads allowed');
select ok(not public.has_resort_role('aaaaaaaa-1111-0000-0000-000000000001', true,
          'owner','admin','staff','accountant'), 'suspended resort: writes refused');
select throws_ok(
  $$select public.assert_resort_role('aaaaaaaa-1111-0000-0000-000000000001', true,
      'owner','admin','staff','accountant')$$,
  'P0022', null, 'assert on suspended write raises P0022');

select * from finish();
rollback;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `supabase test db`
Expected: `36_resort_tenancy_test.sql` fails (`resort_role` enum does not exist); all other files pass.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/0043_resort_tenancy.sql`:

```sql
-- ResortHub tenancy foundation, part 1: resorts, memberships, helpers.
-- See docs/superpowers/specs/2026-09-24-resorthub-tenancy-design.md.

create type public.resort_role as enum ('owner','admin','staff','accountant');
create type public.platform_role as enum ('customer','platform_admin');

alter table public.properties
  add column status text not null default 'active'
    check (status in ('active','suspended','archived'));

-- Folded into profiles.role by 0046; separate until then so the old
-- user_role-based helpers keep working while 0044/0045 are applied.
alter table public.profiles
  add column platform_role public.platform_role not null default 'customer';

create table public.resort_members (
  property_id uuid not null references public.properties(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  role        public.resort_role not null,
  created_at  timestamptz not null default now(),
  primary key (property_id, user_id)
);
create index resort_members_user_idx on public.resort_members (user_id);
alter table public.resort_members enable row level security;

create function public.is_platform_admin()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select platform_role = 'platform_admin' from public.profiles
      where id = auth.uid()),
    false);
$$;

create function public.resort_role(p_property uuid)
returns public.resort_role
language sql stable security definer
set search_path = public, pg_temp
as $$
  select role from public.resort_members
   where property_id = p_property and user_id = auth.uid();
$$;

create function public.has_resort_role(
  p_property uuid,
  p_write    boolean,
  variadic p_roles public.resort_role[]
) returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select m.role = any (p_roles)
       and (p.status = 'active' or (p.status = 'suspended' and not p_write))
      from public.resort_members m
      join public.properties p on p.id = m.property_id
     where m.property_id = p_property and m.user_id = auth.uid()
  ), false);
$$;

-- For functions: raises instead of returning false, so callers get a
-- specific error code.
create function public.assert_resort_role(
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
  if p_write and v_status <> 'active' then
    raise exception using errcode = 'P0022', message = 'resort_suspended';
  end if;
  if not p_write and v_status = 'archived' then
    raise exception using errcode = 'P0020', message = 'not_a_member';
  end if;
end;
$$;

grant execute on function public.is_platform_admin() to authenticated;
grant execute on function public.resort_role(uuid) to authenticated;
grant execute on function public.has_resort_role(uuid, boolean, public.resort_role[]) to authenticated, anon;
grant execute on function public.assert_resort_role(uuid, boolean, public.resort_role[]) to authenticated;

-- Members read their own resort's roster; owners manage it through the
-- functions in 0045 (no direct write policy).
create policy resort_members_read on public.resort_members
  for select to authenticated
  using (user_id = auth.uid()
         or public.has_resort_role(property_id, false, 'owner','admin'));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `supabase migration up --local && supabase test db`
Expected: all files pass, including `36_resort_tenancy_test.sql` (12 assertions).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0043_resort_tenancy.sql supabase/tests/36_resort_tenancy_test.sql
git commit -m "feat(db): add resorts status, resort memberships and role helpers"
```

---

### Task 2: `property_id` on every resort-owned table, with backfill

**Files:**
- Modify: `supabase/migrations/0043_resort_tenancy.sql` (append)
- Modify: `supabase/tests/36_resort_tenancy_test.sql`

**Interfaces:**
- Consumes: Task 1's schema.
- Produces: `property_id uuid not null` (nullable on `outbox_templates` and `audit_log`) with index `<table>_property_idx` on the 22 tables listed below; trigger function `public.fill_property_id()`; error `P0021`.

Parent map (child → parent column → parent table):

| Child | Parent column | Parent table |
|---|---|---|
| reservations | unit_id | units |
| rate_rules, ical_feeds, ical_export_tokens | unit_id | units |
| payments, food_orders, activity_bookings, coupon_redemptions, reviews, service_requests, maintenance_issues, unit_calendar_events | reservation_id | reservations |
| food_items | category_id | food_categories |
| food_order_items | order_id | food_orders |

Backfilled to the single existing property ("no link today"): coupons, outbox, outbox_templates, staff_shifts, leave_requests, attendance_records, tasks, audit_log.

- [ ] **Step 1: Write the failing tests**

Append before `select * from finish();` in `36_resort_tenancy_test.sql`, and raise `plan(12)` to `plan(17)`:

```sql
reset role;
insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('aaaaaaaa-2222-0000-0000-000000000001','aaaaaaaa-1111-0000-0000-000000000001','UA',2,4),
  ('bbbbbbbb-2222-0000-0000-000000000001','bbbbbbbb-1111-0000-0000-000000000001','UB',2,4);
insert into public.reservations (id, unit_id, period, kind, status, guests) values
  ('aaaaaaaa-3333-0000-0000-000000000001','aaaaaaaa-2222-0000-0000-000000000001',
   tstzrange('2027-01-03 14:00+05:30','2027-01-04 11:00+05:30','[)'),'block','confirmed',1);

select is((select property_id from public.reservations
            where id = 'aaaaaaaa-3333-0000-0000-000000000001'),
          'aaaaaaaa-1111-0000-0000-000000000001'::uuid,
          'reservation property_id filled from its unit');
select col_not_null('public','tasks','property_id','tasks.property_id required');
select col_is_null('public','audit_log','property_id','audit_log.property_id nullable');

select throws_ok(
  $$insert into public.payments (reservation_id, property_id, kind, amount, status)
    values ('aaaaaaaa-3333-0000-0000-000000000001',
            'bbbbbbbb-1111-0000-0000-000000000001','advance',100,'succeeded')$$,
  'P0021', null, 'payment cannot point at a different resort than its reservation');

select throws_ok(
  $$update public.reservations set unit_id = 'bbbbbbbb-2222-0000-0000-000000000001'
     where id = 'aaaaaaaa-3333-0000-0000-000000000001'$$,
  'P0021', null, 'moving a reservation to another resort''s unit is refused');
```

- [ ] **Step 2: Run to verify failure**

Run: `supabase test db`
Expected: `36_resort_tenancy_test.sql` fails (`reservations.property_id` does not exist).

- [ ] **Step 3: Append the migration**

Append to `0043_resort_tenancy.sql`:

```sql
-- ---------------------------------------------------------------------
-- property_id on every resort-owned table.

create function public.fill_property_id()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_parent_table text := tg_argv[0];
  v_parent_col   text := tg_argv[1];
  v_parent_id    uuid;
  v_property     uuid;
begin
  execute format('select ($1).%I', v_parent_col) into v_parent_id using new;
  if v_parent_id is null then
    return new;
  end if;
  execute format('select property_id from public.%I where id = $1', v_parent_table)
    into v_property using v_parent_id;
  if tg_op = 'INSERT' and new.property_id is null then
    new.property_id := v_property;
  elsif new.property_id is distinct from v_property then
    raise exception using errcode = 'P0021', message = 'resort_mismatch';
  end if;
  return new;
end;
$$;

do $$
declare
  r record;
begin
  for r in select * from (values
    ('reservations','unit_id','units'),
    ('rate_rules','unit_id','units'),
    ('ical_feeds','unit_id','units'),
    ('ical_export_tokens','unit_id','units'),
    ('payments','reservation_id','reservations'),
    ('food_orders','reservation_id','reservations'),
    ('activity_bookings','reservation_id','reservations'),
    ('coupon_redemptions','reservation_id','reservations'),
    ('reviews','reservation_id','reservations'),
    ('service_requests','reservation_id','reservations'),
    ('maintenance_issues','reservation_id','reservations'),
    ('unit_calendar_events','reservation_id','reservations'),
    ('food_items','category_id','food_categories'),
    ('food_order_items','order_id','food_orders')
  ) as t(child, col, parent)
  loop
    execute format('alter table public.%I add column property_id uuid references public.properties(id)', r.child);
    execute format(
      'update public.%I c set property_id = p.property_id from public.%I p where p.id = c.%I',
      r.child, r.parent, r.col);
    execute format('create index %I on public.%I (property_id)', r.child || '_property_idx', r.child);
    execute format(
      'create trigger %I before insert or update on public.%I
         for each row execute function public.fill_property_id(%L, %L)',
      r.child || '_fill_property', r.child, r.parent, r.col);
  end loop;
end;
$$;

-- Tables with no path to a resort: everything that exists today belongs
-- to the single existing property.
do $$
declare
  v_pasala uuid;
  t text;
begin
  select id into v_pasala from public.properties order by created_at limit 1;
  foreach t in array array['coupons','outbox','outbox_templates','staff_shifts',
                           'leave_requests','attendance_records','tasks','audit_log']
  loop
    execute format('alter table public.%I add column property_id uuid references public.properties(id)', t);
    if v_pasala is not null and t not in ('outbox_templates') then
      execute format('update public.%I set property_id = $1', t) using v_pasala;
    end if;
    execute format('create index %I on public.%I (property_id)', t || '_property_idx', t);
  end loop;
end;
$$;

-- outbox_templates rows stay platform defaults (property_id null);
-- audit_log keeps null for platform-level events. Everything else is
-- required from here on.
do $$
declare
  t text;
begin
  foreach t in array array[
    'reservations','rate_rules','ical_feeds','ical_export_tokens','payments',
    'food_orders','activity_bookings','coupon_redemptions','reviews',
    'service_requests','maintenance_issues','unit_calendar_events','food_items',
    'food_order_items','coupons','outbox','staff_shifts','leave_requests',
    'attendance_records','tasks']
  loop
    execute format('alter table public.%I alter column property_id set not null', t);
  end loop;
end;
$$;
```

Note: `unit_calendar_events` rows with a null `reservation_id` (imported iCal events) must take their unit's resort. If the table has a `unit_id` column (check with `\d public.unit_calendar_events`), change its tuple in the loop to `('unit_calendar_events','unit_id','units')`.

- [ ] **Step 4: Run to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: all files pass. `db reset` proves the migration works on an empty database; also run it against a copy of real data: `supabase migration up --local` on a database at `0042` must succeed.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0043_resort_tenancy.sql supabase/tests/36_resort_tenancy_test.sql
git commit -m "feat(db): tag every resort-owned row with property_id"
```

---

### Task 3: Move existing roles into Pasala memberships

**Files:**
- Modify: `supabase/migrations/0043_resort_tenancy.sql` (append)
- Modify: `supabase/seed.sql:42-49`
- Modify: `supabase/tests/36_resort_tenancy_test.sql`

**Interfaces:**
- Produces: every existing `super_admin/admin/staff/accountant` profile has a `resort_members` row at the first property with role `owner/admin/staff/accountant`. `profiles.role` is left unchanged here (Task 12 resets it).

- [ ] **Step 1: Write the failing test**

Append to `36_resort_tenancy_test.sql` (and `plan(17)` → `plan(18)`):

```sql
select is(
  (select count(*)::int from public.resort_members m
     join public.profiles p on p.id = m.user_id
    where p.role <> 'customer'
      and m.role::text <> case p.role::text when 'super_admin' then 'owner'
                                             else p.role::text end),
  0, 'every migrated membership matches the old global role');
```

- [ ] **Step 2: Run to verify** — this passes vacuously on an empty test database. Verify against the seed instead:

Run: `supabase db reset && docker exec supabase_db_pasala_farm psql -U postgres -c "select count(*) from public.resort_members"`
Expected before the change: `0`.

- [ ] **Step 3: Append the role move**

Append to `0043_resort_tenancy.sql`:

```sql
-- Existing global staff roles become memberships at the first property.
insert into public.resort_members (property_id, user_id, role)
select (select id from public.properties order by created_at limit 1),
       p.id,
       case p.role when 'super_admin' then 'owner'::public.resort_role
                   else p.role::text::public.resort_role end
  from public.profiles p
 where p.role <> 'customer'
   and exists (select 1 from public.properties);
```

Then change `supabase/seed.sql` lines 42–49: keep the four `update public.profiles set role = ...` statements (they still type-check until Task 12) and add, after the `insert into public.properties` block, one `insert into public.resort_members (property_id, user_id, role) values (...)` per seeded staff user, using the same user ids and the seeded property id: super admin → `owner`, admin → `admin`, staff → `staff`, accountant → `accountant`.

- [ ] **Step 4: Verify**

Run: `supabase db reset && docker exec supabase_db_pasala_farm psql -U postgres -c "select role, count(*) from public.resort_members group by 1 order by 1"`
Expected: one row each for `owner`, `admin`, `staff`, `accountant`. Then `supabase test db` — all pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0043_resort_tenancy.sql supabase/seed.sql supabase/tests/36_resort_tenancy_test.sql
git commit -m "feat(db): move existing staff roles into Pasala memberships"
```

---

### Task 4: Give existing pgTAP test users memberships

The policy rewrite in Task 5 makes the global role irrelevant, so every existing test that promotes a user with `update public.profiles set role = 'X'` must also grant a membership. Doing this *before* Task 5 keeps the suite green at every commit.

**Files:**
- Modify: every file in `supabase/tests/` that contains `update public.profiles set role`

**Interfaces:**
- Consumes: `resort_members` from Task 1.

- [ ] **Step 1: List the files**

Run: `grep -ln "update public.profiles set role" supabase/tests/*.sql`

- [ ] **Step 2: In each file, add memberships**

After the file's first `insert into public.properties` statement, add one `insert into public.resort_members` row per promoted user, for **every property the file creates**, mapping `super_admin` → `owner` and keeping other roles. Example for `07_rls_test.sql` (one property `aaaaaaaa-0000-0000-0000-000000000001`, users 3/4/5):

```sql
insert into public.resort_members (property_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001','33333333-3333-3333-3333-333333333333','staff'),
  ('aaaaaaaa-0000-0000-0000-000000000001','44444444-4444-4444-4444-444444444444','admin'),
  ('aaaaaaaa-0000-0000-0000-000000000001','55555555-5555-5555-5555-555555555555','accountant');
```

If a file promotes users before creating any property, move the membership insert to just after the property insert. If a file creates no property at all (for example `01_profiles_test.sql`), leave it unchanged — Task 12 handles it.

- [ ] **Step 3: Run the suite**

Run: `supabase test db`
Expected: all files pass (memberships are unused by policies yet, so nothing changes).

- [ ] **Step 4: Commit**

```bash
git add supabase/tests
git commit -m "test(db): give test users resort memberships alongside global roles"
```

---

### Task 5: Rewrite every policy to check the row's resort

**Files:**
- Create: `supabase/migrations/0044_resort_policies.sql`
- Create: `supabase/tests/37_tenancy_isolation_test.sql`

**Interfaces:**
- Consumes: `has_resort_role` (Task 1), `property_id` columns (Task 2).
- Produces: policies named `<table>_read`, `<table>_write`, plus the guest-own and self policies listed below.

Target policy matrix. "Staff+" = `'owner','admin','staff','accountant'`; "Admin+" = `'owner','admin'`. `R(roles)` means `public.has_resort_role(property_id, false, roles)`; `W(roles)` means `public.has_resort_role(property_id, true, roles)`. `active(pid)` means `exists (select 1 from public.properties p where p.id = pid and p.status = 'active')`. `own_res` means `exists (select 1 from public.reservations r where r.id = <table>.reservation_id and r.customer_id = auth.uid())`.

| Table | Select | Insert / Update / Delete |
|---|---|---|
| properties | anon+auth: `status = 'active'`; auth: `R(Staff+)` on `id` | update: `W(Admin+)` on `id`. No insert/delete policy (use `create_resort`). |
| units, slot_types, rate_rules | anon+auth: `active(property_id)` (units also `is_active`); auth: `R(Staff+)` | all: `W(Admin+)` |
| activities, food_categories, food_items | auth: `active(property_id) or R(Staff+)` | all: `W(Admin+)` |
| unit_calendar_events | anon+auth: `active(property_id)`; auth: `R(Staff+)` | none (trigger-maintained) |
| reservations | `customer_id = auth.uid() or R(Staff+)` | all: `W(Admin+)` |
| payments, food_orders, activity_bookings, service_requests, maintenance_issues | `R(Staff+) or own_res` | payments: all `W(Admin+)`; food_orders update: `W(Staff+)`; activity_bookings update (guest cancel): keep existing `own_res and status = 'cancelled'` check; service_requests / maintenance_issues update: `W(Staff+)` (their `*_enforce_write` triggers are rewritten in Task 9) |
| food_order_items | `R(Staff+) or exists (select 1 from food_orders o join reservations r on r.id = o.reservation_id where o.id = order_id and r.customer_id = auth.uid())` | none |
| coupon_redemptions | `R(Staff+) or customer_id = auth.uid()` | all: `W(Admin+)` |
| coupons | `(is_active and (customer_id is null or customer_id = auth.uid()) and active(property_id)) or R(Staff+)` | all: `W(Admin+)` |
| reviews | `true` (public) | insert: existing checked-out-guest check, unchanged |
| refund_rules, notification_settings, outbox, outbox_templates | `R(Staff+)`; outbox_templates also `property_id is null` (platform defaults) for Staff+ at any resort | refund_rules, notification_settings, outbox_templates: all `W(Admin+)` |
| expenses | `R('owner','admin','accountant')` | all: `W(Admin+)` |
| food_activity_sales | `R(Staff+)` | insert: `W(Staff+)`; update, delete: `W(Admin+)` |
| staff_shifts, tasks | `R(Admin+) or staff_id / assignee_id = auth.uid()` | insert, delete: `W(Admin+)`; update: tasks `W(Admin+) or assignee_id = auth.uid()`, shifts `W(Admin+)` |
| leave_requests | `R(Admin+) or staff_id = auth.uid()` | insert: existing own-pending check plus `W(Staff+)`; update: `W(Admin+)` |
| attendance_records | `R(Admin+) or staff_id = auth.uid()` | insert: existing own-today check plus `W(Staff+)` |
| audit_log | `property_id is not null and R(Staff+)` | none |
| ical_feeds, ical_export_tokens | `R(Admin+)` | all: `W(Admin+)` |
| profiles | self: `id = auth.uid()`; resort staff: `exists (select 1 from reservations r where r.customer_id = profiles.id and public.has_resort_role(r.property_id, false, 'owner','admin','staff','accountant'))`; colleagues: `exists (select 1 from resort_members a join resort_members b using (property_id) where a.user_id = auth.uid() and b.user_id = profiles.id)`; review authors: existing `profiles_review_author_read` unchanged | update self only, with the existing "cannot change own role" check. Drop `profiles_admin_insert`, `profiles_admin_delete`, `profiles_admin_update`, `profiles_admin_select`. |

- [ ] **Step 1: Write the failing leak test**

Create `supabase/tests/37_tenancy_isolation_test.sql`. It seeds two complete resorts, then asserts as each of A's roles that B's rows are invisible and unwritable:

```sql
begin;
select plan(26);

-- Users: A's owner/admin/staff/accountant, B's owner, one guest per resort.
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-00000000000a','a-owner@example.com'),
  ('a0000000-0000-0000-0000-00000000000b','a-admin@example.com'),
  ('a0000000-0000-0000-0000-00000000000c','a-staff@example.com'),
  ('a0000000-0000-0000-0000-00000000000d','a-acct@example.com'),
  ('b0000000-0000-0000-0000-00000000000a','b-owner@example.com'),
  ('c0000000-0000-0000-0000-00000000000a','guest-a@example.com'),
  ('c0000000-0000-0000-0000-00000000000b','guest-b@example.com');

insert into public.properties (id, name, slug) values
  ('aaaaaaaa-0000-4000-8000-000000000001','Resort A','iso-a'),
  ('bbbbbbbb-0000-4000-8000-000000000001','Resort B','iso-b');

insert into public.resort_members (property_id, user_id, role) values
  ('aaaaaaaa-0000-4000-8000-000000000001','a0000000-0000-0000-0000-00000000000a','owner'),
  ('aaaaaaaa-0000-4000-8000-000000000001','a0000000-0000-0000-0000-00000000000b','admin'),
  ('aaaaaaaa-0000-4000-8000-000000000001','a0000000-0000-0000-0000-00000000000c','staff'),
  ('aaaaaaaa-0000-4000-8000-000000000001','a0000000-0000-0000-0000-00000000000d','accountant'),
  ('bbbbbbbb-0000-4000-8000-000000000001','b0000000-0000-0000-0000-00000000000a','owner');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('aaaaaaaa-0000-4000-8000-000000000011','aaaaaaaa-0000-4000-8000-000000000001','UA',2,4),
  ('bbbbbbbb-0000-4000-8000-000000000011','bbbbbbbb-0000-4000-8000-000000000001','UB',2,4);

insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests) values
  ('aaaaaaaa-0000-4000-8000-000000000021','aaaaaaaa-0000-4000-8000-000000000011',
   tstzrange('2027-02-01 14:00+05:30','2027-02-02 11:00+05:30','[)'),
   'booking','confirmed','c0000000-0000-0000-0000-00000000000a',2),
  ('bbbbbbbb-0000-4000-8000-000000000021','bbbbbbbb-0000-4000-8000-000000000011',
   tstzrange('2027-02-01 14:00+05:30','2027-02-02 11:00+05:30','[)'),
   'booking','confirmed','c0000000-0000-0000-0000-00000000000b',2);

insert into public.payments (reservation_id, kind, amount, status) values
  ('aaaaaaaa-0000-4000-8000-000000000021','advance',1000,'succeeded'),
  ('bbbbbbbb-0000-4000-8000-000000000021','advance',1000,'succeeded');

insert into public.expenses (property_id, category, amount, spent_on, created_by) values
  ('aaaaaaaa-0000-4000-8000-000000000001','supplies',10,'2027-02-01','a0000000-0000-0000-0000-00000000000a'),
  ('bbbbbbbb-0000-4000-8000-000000000001','supplies',10,'2027-02-01','b0000000-0000-0000-0000-00000000000a');

insert into public.tasks (property_id, title, assignee_id, created_by) values
  ('aaaaaaaa-0000-4000-8000-000000000001','Clean pool','a0000000-0000-0000-0000-00000000000c','a0000000-0000-0000-0000-00000000000b'),
  ('bbbbbbbb-0000-4000-8000-000000000001','Fix gate','b0000000-0000-0000-0000-00000000000a','b0000000-0000-0000-0000-00000000000a');

-- Owner
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is((select count(*)::int from public.reservations where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A owner: no B reservations');
select is((select count(*)::int from public.payments where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A owner: no B payments');
select is((select count(*)::int from public.expenses where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A owner: no B expenses');
select is((select count(*)::int from public.tasks where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A owner: no B tasks');
select is((select count(*)::int from public.profiles where id = 'c0000000-0000-0000-0000-00000000000b'), 0, 'A owner: cannot read B guest profile');
select is((select count(*)::int from public.profiles where id = 'c0000000-0000-0000-0000-00000000000a'), 1, 'A owner: can read own guest profile');
select is((select count(*)::int from public.expenses where property_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 1, 'A owner: sees own expenses');
select throws_ok($$insert into public.expenses (property_id, category, amount, spent_on, created_by)
  values ('bbbbbbbb-0000-4000-8000-000000000001','supplies',5,'2027-02-01','a0000000-0000-0000-0000-00000000000a')$$,
  '42501', null, 'A owner: cannot insert B expense');
update public.units set name = 'hacked' where id = 'bbbbbbbb-0000-4000-8000-000000000011';
reset role;
select is((select name from public.units where id = 'bbbbbbbb-0000-4000-8000-000000000011'), 'UB', 'A owner: B unit update affected nothing');

-- Admin
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select is((select count(*)::int from public.reservations where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A admin: no B reservations');
select is((select count(*)::int from public.tasks where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A admin: no B tasks');
select is((select count(*)::int from public.resort_members where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A admin: no B members');

-- Staff
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select is((select count(*)::int from public.reservations where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A staff: no B reservations');
select is((select count(*)::int from public.payments where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A staff: no B payments');
select is((select count(*)::int from public.expenses), 0, 'A staff: no expenses at all (not an expense reader)');
select is((select count(*)::int from public.tasks), 1, 'A staff: only own assigned task');

-- Accountant
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000d","role":"authenticated"}';
select is((select count(*)::int from public.expenses where property_id = 'bbbbbbbb-0000-4000-8000-000000000001'), 0, 'A accountant: no B expenses');
select is((select count(*)::int from public.expenses where property_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 1, 'A accountant: own expenses');

-- Guest of A
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is((select count(*)::int from public.reservations), 1, 'guest A: only own reservation');
select is((select count(*)::int from public.payments), 1, 'guest A: only own payment');

-- Suspended resort A
reset role;
update public.properties set status = 'suspended' where id = 'aaaaaaaa-0000-4000-8000-000000000001';
set local role anon;
select is((select count(*)::int from public.properties where id = 'aaaaaaaa-0000-4000-8000-000000000001'), 0, 'suspended resort hidden from anon');
select is((select count(*)::int from public.units where property_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 0, 'suspended resort units hidden from anon');
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select is((select count(*)::int from public.reservations where property_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 1, 'suspended: admin still reads');
select throws_ok($$insert into public.expenses (property_id, category, amount, spent_on, created_by)
  values ('aaaaaaaa-0000-4000-8000-000000000001','supplies',5,'2027-02-01','a0000000-0000-0000-0000-00000000000b')$$,
  '42501', null, 'suspended: admin direct write refused');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is((select count(*)::int from public.reservations), 1, 'suspended: guest still sees own booking');

-- Platform admin sees no resort rows.
reset role;
update public.profiles set platform_role = 'platform_admin' where id = 'b0000000-0000-0000-0000-00000000000a';
delete from public.resort_members where user_id = 'b0000000-0000-0000-0000-00000000000a';
set local role authenticated;
set local request.jwt.claims to '{"sub":"b0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is((select count(*)::int from public.reservations), 0, 'platform admin: no reservation rows');

select * from finish();
rollback;
```

Before running, check the real column names of `payments`, `expenses` and `tasks` with `\d public.payments` / `\d public.expenses` / `\d public.tasks` in `docker exec -it supabase_db_pasala_farm psql -U postgres` and adjust the inserts if they differ (the columns above are the ones the repositories write in `lib/data/models/expense.dart` and `task.dart`).

- [ ] **Step 2: Run to verify failure**

Run: `supabase test db`
Expected: `37_tenancy_isolation_test.sql` fails — for example "A owner: no B reservations" gets 1, because the old `is_staff_or_above()` policy lets a Pasala-wide role see everything.

- [ ] **Step 3: Write `0044_resort_policies.sql`**

Structure: for each table in the matrix, `drop policy if exists` every existing policy on that table (names from `select policyname from pg_policies where schemaname='public' and tablename='<t>'`), then `create policy` per the matrix. Worked example for three tables; write the rest the same way from the matrix:

```sql
-- ResortHub tenancy, part 2: every policy checks the row's resort.

-- expenses: owner/admin/accountant read, owner/admin write.
drop policy if exists expenses_read on public.expenses;
drop policy if exists expenses_admin_write on public.expenses;
create policy expenses_read on public.expenses
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','accountant'));
create policy expenses_write on public.expenses
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

-- reservations: guest's own, or any role at the resort; admins write.
drop policy if exists reservations_select_own on public.reservations;
drop policy if exists reservations_admin_write on public.reservations;
create policy reservations_read on public.reservations
  for select to authenticated
  using (customer_id = auth.uid()
         or public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));
create policy reservations_write on public.reservations
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

-- units: public catalog of active resorts, staff of the resort, admins write.
drop policy if exists units_read on public.units;
drop policy if exists units_write on public.units;
create policy units_read on public.units
  for select to anon, authenticated
  using ((is_active and exists (select 1 from public.properties p
                                 where p.id = units.property_id and p.status = 'active'))
         or public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));
create policy units_write on public.units
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));
```

Keep every existing grant; this migration changes policies only. Tables that had a `using (true)` update or delete policy guarded by an `*_enforce_*` trigger (staff_shifts, tasks, leave_requests, service_requests, maintenance_issues) get a real `W(...)` policy from the matrix instead; their triggers are rewritten in Task 9.

- [ ] **Step 4: Run to verify it passes**

Run: `supabase migration up --local && supabase test db`
Expected: `37_tenancy_isolation_test.sql` passes. Existing files that still rely on a global role with no membership fail — fix each by adding the missing membership (Task 4's pattern), never by loosening a policy.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0044_resort_policies.sql supabase/tests
git commit -m "feat(db): scope every row-level policy to the row's resort"
```

---

### Tasks 6–10: Rewrite the `security definer` functions (`0045_resort_functions.sql`)

All five tasks append to one migration file, `supabase/migrations/0045_resort_functions.sql`, and add assertions to `37_tenancy_isolation_test.sql`. **Rewrite pattern** for every function: copy its *latest* definition (find it with `grep -ln "function public.<name>" supabase/migrations/*.sql | tail -1`), change `create function` to `create or replace function`, keep the body, and replace the old role check with the new one from the inventory below. Where the resort must be derived, add at the top of the body:

```sql
  select property_id into v_property from public.reservations where id = p_reservation_id;
  if v_property is null then
    raise exception using errcode = 'P0002', message = 'not_found';
  end if;
  perform public.assert_resort_role(v_property, true, 'owner','admin','staff','accountant');
```

(Declare `v_property uuid;`. Use `false` instead of `true` for read-only functions.) Guest-facing functions keep their existing ownership check and add a resort-status check:

```sql
  if not exists (select 1 from public.properties where id = v_property and status = 'active') then
    raise exception using errcode = 'P0022', message = 'resort_suspended';
  end if;
```

Any `insert` into a table that gained `property_id` in Task 2's "no link" group (`outbox`, `audit_log`, `staff_shifts`, `tasks`, `attendance_records`, `leave_requests`, `coupons`) must now set `property_id`.

Where a signature changes (new `p_property_id` parameter), `drop function` the old signature first, then create the new one, then re-grant `execute` exactly as the old one was granted.

#### Function inventory

| # | Function | Resort from | New check | Task |
|---|---|---|---|---|
| 1 | `search_availability(p_property_id, …)` | `p_property_id` | resort must be `active` (else empty result); no role | 6 |
| 2 | `get_quote(p_unit_id, …)` | `units.property_id` | resort `active` else `P0022` | 6 |
| 3 | `create_hold(p_unit_id, …)` | `units.property_id` | resort `active` else `P0022`; `property_id` passed to `resolve_coupon` | 6 |
| 4 | `resolve_coupon(p_code, p_uid, p_amount)` → **add** `p_property_id uuid` as first param | `p_property_id` | coupon must have `property_id = p_property_id`, else existing "not found" coupon error | 6 |
| 5 | `confirm_booking(p_reservation_id, …)` | reservation | existing owner-of-hold check; resort `active` else `P0022` | 6 |
| 6 | `compute_refund(p_reservation_id)` | reservation | guest own, or `assert_resort_role(v, false, Staff+)` | 6 |
| 7 | `cancel_booking(p_reservation_id, p_reason)` | reservation | guest own (allowed while suspended), or `assert_resort_role(v, true, Admin+)` | 6 |
| 8 | `block_dates(p_unit_id, …)` | unit | `assert_resort_role(v, true, Admin+)` | 6 |
| 9 | `release_expired_holds()` | — | unchanged (cron only; not granted to clients) | 6 |
| 10 | `release_reservation_coupon(p_reservation_id)` | — | unchanged (internal) | 6 |
| 11 | `check_in_booking(p_reservation_id)` | reservation | `assert_resort_role(v, true, Staff+)` | 7 |
| 12 | `checkout_booking(p_reservation_id, …)` | reservation | guest own (existing customer path), or `assert_resort_role(v, true, Staff+)` | 7 |
| 13 | `current_charges(p_reservation_id)` | reservation | guest own, or `assert_resort_role(v, false, Staff+)` | 7 |
| 14 | `place_food_order(p_reservation_id, …)` | reservation | existing guest check; resort `active` else `P0022` | 7 |
| 15 | `book_activity(p_reservation_id, …)` | reservation | existing guest check; resort `active` else `P0022` | 7 |
| 16 | `create_service_request(p_reservation_id, …)` | reservation | existing guest check; resort `active` else `P0022` | 7 |
| 17 | `report_maintenance_issue(p_reservation_id, …)` | reservation | existing guest-or-staff check → guest own, or `assert_resort_role(v, true, Staff+)` | 7 |
| 18 | `dashboard_summary()` → **add** `p_property_id uuid` | param | `assert_resort_role(p, false, Staff+)`; every inner query filtered by `property_id = p_property_id` | 8 |
| 19 | `report_revenue(p_from, p_to, p_property_id)` → `p_property_id` becomes **required** (no default) | param | `assert_resort_role(p, false, Staff+)` replacing `assert_staff()` | 8 |
| 20 | `report_occupancy(…)` | same as 19 | same | 8 |
| 21 | `report_food_sales(…)` | same as 19 | same | 8 |
| 22 | `report_expenses(…)` | same as 19 | `assert_resort_role(p, false, 'owner','admin','accountant')` | 8 |
| 23 | `staff_performance_summary(p_staff_id, p_from, …)` (invoker) → **add** `p_property_id uuid` first | param | `assert_resort_role(p, false, Admin+)`; filter by `property_id` | 8 |
| 24 | `list_staff_shifts(p_staff_id, p_from, p_to)` (invoker) → **add** `p_property_id uuid` first | param | filter `property_id = p_property_id`; RLS does the rest | 8 |
| 25 | `assert_staff()` | — | **drop** in Task 12 after 19–22 stop calling it | 12 |
| 26 | `staff_shifts_enforce_admin_write()` trigger | `new/old.property_id` | `has_resort_role(…, true, Admin+)` | 9 |
| 27 | `leave_requests_enforce_admin_decision()` trigger | row | `has_resort_role(…, true, Admin+)` | 9 |
| 28 | `attendance_records_enforce_own_checkout()` trigger | row | unchanged logic; replace any `is_admin()` with `has_resort_role(…, true, Admin+)` | 9 |
| 29 | `attendance_records_force_checkin_time()` trigger | row | unchanged | 9 |
| 30 | `check_out_attendance(p_id)` | row | own row, resort `active` else `P0022` | 9 |
| 31 | `tasks_enforce_write()` trigger | row | `has_resort_role(…, true, Admin+)` or assignee's allowed columns (existing rule) | 9 |
| 32 | `service_requests_enforce_write()` trigger | row | `has_resort_role(…, true, Staff+)` | 9 |
| 33 | `maintenance_issues_enforce_write()` trigger | row | `has_resort_role(…, true, Staff+)` | 9 |
| 34 | `enqueue_reservation_outbox()` trigger | `new.property_id` | sets `outbox.property_id` | 9 |
| 35 | `enqueue_outbox_message(p_reservation_id, p_template)` | reservation | `assert_resort_role(v, true, Staff+)`; sets `outbox.property_id` | 9 |
| 36 | `render_template(p_template, p_reservation_id)` | reservation | template lookup: resort's own row first, then `property_id is null` default | 9 |
| 37 | `record_reservation_transition()` trigger | `new.property_id` | sets `audit_log.property_id` | 9 |
| 38 | `sync_unit_calendar_event()` trigger | `new.property_id` | sets `unit_calendar_events.property_id` | 9 |
| 39 | `ical_provision_token()` trigger | `new.property_id` (unit) | sets `ical_export_tokens.property_id` | 9 |
| 40 | `rotate_ical_token(p_unit_id)` | unit | `assert_resort_role(v, true, Admin+)` | 9 |
| 41 | `ical_export(p_unit_id)` | unit | `assert_resort_role(v, false, Admin+)` | 9 |
| 42 | `ical_build_document(p_unit_id)` | — | unchanged (internal; not granted to clients) | 9 |
| 43 | `ical_export_public(p_token)` | token | unchanged; returns nothing when the unit's resort is not `active` | 9 |
| 44 | `ical_import_event(p_unit_id, …)` | unit | unchanged (called by poller only; not granted to clients) | 9 |
| 45 | `ical_poll_feed(p_feed_id)` | feed | `assert_resort_role(feed.property_id, true, Admin+)` | 9 |
| 46 | `ical_poll_all_feeds()` | — | unchanged (cron only) | 9 |
| 47 | `handle_new_user()` trigger | — | unchanged here; Task 12 changes the inserted role type | 12 |
| 48 | `list_profiles()`, `set_user_role(…)` | — | **dropped**; replaced by Task 10 functions | 10 |

### Task 6: Booking, quote, coupon and refund functions (inventory 1–10)

**Files:**
- Create: `supabase/migrations/0045_resort_functions.sql`
- Modify: `supabase/tests/37_tenancy_isolation_test.sql`, `supabase/tests/11_coupons_test.sql`, `supabase/tests/03_quote_test.sql`, `supabase/tests/06_booking_flow_test.sql`

**Interfaces:**
- Consumes: `assert_resort_role` (Task 1).
- Produces: `resolve_coupon(p_property_id uuid, p_code text, p_uid uuid, p_amount numeric)`. The other signatures are unchanged.

- [ ] **Step 1: Write the failing tests** — append to `37_tenancy_isolation_test.sql` (raise `plan` by 4):

```sql
-- As A's admin (resort A active again):
reset role;
update public.properties set status = 'active' where id = 'aaaaaaaa-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select throws_ok($$select public.block_dates('bbbbbbbb-0000-4000-8000-000000000011',
  array[daterange('2027-03-01','2027-03-02')], 'x')$$, 'P0020', null, 'A admin cannot block B dates');
select throws_ok($$select public.cancel_booking('bbbbbbbb-0000-4000-8000-000000000021','x')$$,
  'P0020', null, 'A admin cannot cancel B booking');
select throws_ok($$select public.compute_refund('bbbbbbbb-0000-4000-8000-000000000021')$$,
  'P0020', null, 'A admin cannot quote B refund');
-- Suspended resort: new holds refused.
reset role;
update public.properties set status = 'suspended' where id = 'bbbbbbbb-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select throws_ok($$select public.create_hold('bbbbbbbb-0000-4000-8000-000000000011',
  '2027-04-01','2027-04-02',2)$$, 'P0022', null, 'cannot hold at suspended resort');
```

In `11_coupons_test.sql`, update every direct `resolve_coupon(` call to pass the property id first, and give each test coupon a `property_id`.

- [ ] **Step 2: Run to verify failure** — `supabase test db`. Expected: the four new assertions fail (old functions don't check resorts).
- [ ] **Step 3: Implement** inventory rows 1–10 in `0045_resort_functions.sql` using the rewrite pattern.
- [ ] **Step 4: Run** — `supabase migration up --local && supabase test db`. Expected: all pass.
- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0045_resort_functions.sql supabase/tests
git commit -m "feat(db): scope booking, quote, coupon and refund functions to resorts"
```

### Task 7: Stay and guest-service functions (inventory 11–17)

**Files:**
- Modify: `supabase/migrations/0045_resort_functions.sql` (append)
- Modify: `supabase/tests/37_tenancy_isolation_test.sql`

- [ ] **Step 1: Write the failing tests** (raise `plan` by 4):

```sql
reset role;
update public.properties set status = 'active' where id = 'bbbbbbbb-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select throws_ok($$select public.check_in_booking('bbbbbbbb-0000-4000-8000-000000000021')$$,
  'P0020', null, 'A staff cannot check in a B guest');
select throws_ok($$select public.current_charges('bbbbbbbb-0000-4000-8000-000000000021')$$,
  'P0020', null, 'A staff cannot read B charges');
reset role;
update public.properties set status = 'suspended' where id = 'aaaaaaaa-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000c","role":"authenticated"}';
select throws_ok($$select public.check_in_booking('aaaaaaaa-0000-4000-8000-000000000021')$$,
  'P0022', null, 'staff write at suspended resort raises P0022');
set local request.jwt.claims to '{"sub":"c0000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select lives_ok($$select public.cancel_booking('aaaaaaaa-0000-4000-8000-000000000021','changed plans')$$,
  'guest can still cancel at a suspended resort');
```

- [ ] **Step 2: Run to verify failure** — `supabase test db`.
- [ ] **Step 3: Implement** rows 11–17.
- [ ] **Step 4: Run** — `supabase migration up --local && supabase test db`. Expected: all pass.
- [ ] **Step 5: Commit** — `git commit -am "feat(db): scope stay and guest-service functions to resorts"`

### Task 8: Reports, dashboard, performance and shift listing (inventory 18–24)

**Files:**
- Modify: `supabase/migrations/0045_resort_functions.sql` (append)
- Modify: `supabase/tests/37_tenancy_isolation_test.sql`, `10_reports_test.sql`, `22_food_activity_sales_test.sql`, `23_expenses_test.sql`, `25_staff_performance_test.sql`, `26_owner_dashboard_summary_test.sql`, `34_stay_dashboard_summary_test.sql`, `17_staff_shifts_test.sql`

**Interfaces:**
- Produces: `dashboard_summary(p_property_id uuid)`, `report_revenue(p_from date, p_to date, p_property_id uuid)` (required), same for `report_occupancy`, `report_food_sales`, `report_expenses`; `staff_performance_summary(p_property_id uuid, p_staff_id uuid default null, p_from date default …, p_to date default …)`; `list_staff_shifts(p_property_id uuid, p_staff_id uuid default null, p_from date default null, p_to date default null)`.

- [ ] **Step 1: Write the failing tests** (raise `plan` by 3):

```sql
reset role;
update public.properties set status = 'active' where id = 'aaaaaaaa-0000-4000-8000-000000000001';
set local role authenticated;
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000d","role":"authenticated"}';
select throws_ok($$select * from public.report_revenue('2027-01-01','2027-12-31','bbbbbbbb-0000-4000-8000-000000000001')$$,
  'P0020', null, 'A accountant cannot read B revenue');
select throws_ok($$select public.dashboard_summary('bbbbbbbb-0000-4000-8000-000000000001')$$,
  'P0020', null, 'A accountant cannot read B dashboard');
select throws_ok($$select * from public.report_expenses('2027-01-01','2027-12-31','bbbbbbbb-0000-4000-8000-000000000001')$$,
  'P0020', null, 'A accountant cannot read B expenses report');
```

In the listed existing test files, pass the file's property id as the new argument to every call of these functions.

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** rows 18–24.
- [ ] **Step 4: Run** — all pass.
- [ ] **Step 5: Commit** — `git commit -am "feat(db): require a resort for reports, dashboard and staff listings"`

### Task 9: Staff-ops triggers, outbox, audit and iCal (inventory 26–46)

**Files:**
- Modify: `supabase/migrations/0045_resort_functions.sql` (append)
- Modify: `supabase/tests/37_tenancy_isolation_test.sql`, `13_outbox_test.sql`, `14_ical_test.sql`, `17`–`20`, `30`, `31`

- [ ] **Step 1: Write the failing tests** (raise `plan` by 4):

```sql
set local request.jwt.claims to '{"sub":"a0000000-0000-0000-0000-00000000000b","role":"authenticated"}';
select throws_ok($$select public.rotate_ical_token('bbbbbbbb-0000-4000-8000-000000000011')$$,
  'P0020', null, 'A admin cannot rotate B iCal token');
select throws_ok($$select public.enqueue_outbox_message('bbbbbbbb-0000-4000-8000-000000000021','booking_confirmed')$$,
  'P0020', null, 'A admin cannot send B guest messages');
reset role;
select is((select count(*)::int from public.outbox where property_id is null), 0,
  'every outbox row carries a resort');
select is((select count(*)::int from public.audit_log a
             join public.reservations r on r.id = a.entity_id
            where a.property_id is distinct from r.property_id), 0,
  'audit rows for reservations carry the reservation''s resort');
```

Check the real `audit_log` column that references the reservation with `\d public.audit_log` and adjust `a.entity_id` if it is named differently. In the listed existing test files, add `property_id` to every direct insert into `staff_shifts`, `tasks`, `leave_requests`, `attendance_records`, `outbox_templates`, `coupons`.

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** rows 26–46.
- [ ] **Step 4: Run** — all pass.
- [ ] **Step 5: Commit** — `git commit -am "feat(db): scope staff-ops triggers, outbox, audit and iCal to resorts"`

### Task 10: Member management and platform functions

**Files:**
- Modify: `supabase/migrations/0045_resort_functions.sql` (append)
- Create: `supabase/tests/38_resort_members_test.sql`
- Delete: `supabase/tests/15_user_admin_test.sql` (its guarantees move to file 38)

**Interfaces:**
- Produces:
  - `list_resort_members(p_property uuid) returns table(user_id uuid, email text, full_name text, role public.resort_role, created_at timestamptz)` — owner, admin.
  - `add_resort_member(p_property uuid, p_email text, p_role public.resort_role) returns void` — owner. `P0002` when no account has that email.
  - `set_member_role(p_property uuid, p_user uuid, p_role public.resort_role) returns void` — owner. `P0023` if it would leave no owner.
  - `remove_resort_member(p_property uuid, p_user uuid) returns void` — owner. `P0023` likewise.
  - `platform_resorts() returns table(property_id uuid, name text, status text, owner_emails text[], created_at timestamptz, bookings_30d int, revenue_30d numeric, bookings_365d int, revenue_365d numeric)` — platform admin.
  - `set_resort_status(p_property uuid, p_status text) returns void` — platform admin; writes `audit_log` with `property_id = p_property`.
  - `create_resort(p_name text, p_owner_email text) returns uuid` — platform admin; slug derived from the name; `P0002` if no such account.
  - Platform functions raise `P0008` (existing "not permitted") for non-platform-admins.

- [ ] **Step 1: Write the failing test** `supabase/tests/38_resort_members_test.sql`:

```sql
begin;
select plan(11);

insert into auth.users (id, email) values
  ('d0000000-0000-0000-0000-000000000001','owner1@example.com'),
  ('d0000000-0000-0000-0000-000000000002','owner2@example.com'),
  ('d0000000-0000-0000-0000-000000000003','newhire@example.com'),
  ('d0000000-0000-0000-0000-000000000004','platform@example.com');
insert into public.properties (id, name, slug) values
  ('dddddddd-0000-4000-8000-000000000001','Resort D','resort-d');
insert into public.resort_members (property_id, user_id, role) values
  ('dddddddd-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000001','owner');
update public.profiles set platform_role = 'platform_admin'
  where id = 'd0000000-0000-0000-0000-000000000004';

set local role authenticated;
set local request.jwt.claims to '{"sub":"d0000000-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok($$select public.add_resort_member('dddddddd-0000-4000-8000-000000000001','newhire@example.com','staff')$$,
  'owner adds an existing account as staff');
select throws_ok($$select public.add_resort_member('dddddddd-0000-4000-8000-000000000001','nobody@example.com','staff')$$,
  'P0002', null, 'unknown email is not found');
select is((select count(*)::int from public.list_resort_members('dddddddd-0000-4000-8000-000000000001')), 2,
  'roster lists both members');
select throws_ok($$select public.set_member_role('dddddddd-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000001','admin')$$,
  'P0023', null, 'sole owner cannot demote themself');
select throws_ok($$select public.remove_resort_member('dddddddd-0000-4000-8000-000000000001','d0000000-0000-0000-0000-000000000001')$$,
  'P0023', null, 'sole owner cannot remove themself');

set local request.jwt.claims to '{"sub":"d0000000-0000-0000-0000-000000000003","role":"authenticated"}';
select throws_ok($$select public.add_resort_member('dddddddd-0000-4000-8000-000000000001','owner2@example.com','owner')$$,
  'P0020', null, 'staff cannot add members');
select throws_ok($$select * from public.platform_resorts()$$,
  'P0008', null, 'staff cannot call platform functions');

set local request.jwt.claims to '{"sub":"d0000000-0000-0000-0000-000000000004","role":"authenticated"}';
select ok((select count(*) from public.platform_resorts() where property_id = 'dddddddd-0000-4000-8000-000000000001') = 1,
  'platform admin sees resort summary');
select lives_ok($$select public.set_resort_status('dddddddd-0000-4000-8000-000000000001','suspended')$$,
  'platform admin suspends a resort');
select isnt(public.create_resort('Resort E','owner2@example.com'), null,
  'platform admin creates a resort for an existing account');
select throws_ok($$select * from public.list_resort_members('dddddddd-0000-4000-8000-000000000001')$$,
  'P0020', null, 'platform admin cannot read a resort roster');

select * from finish();
rollback;
```

The concurrent two-owner race is covered by the locking: `set_member_role` and `remove_resort_member` start with `perform 1 from public.resort_members where property_id = p_property and role = 'owner' for update;` before counting owners — the same pattern as `set_user_role` in `0019_user_admin.sql` after commit `ecd7182`. Copy that function's locking comment and structure.

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** the seven functions, `drop function public.list_profiles(); drop function public.set_user_role(uuid, public.user_role);`, and grant `execute` on the new ones to `authenticated`.
- [ ] **Step 4: Run** — all pass.
- [ ] **Step 5: Commit** — `git commit -am "feat(db): add resort member management and platform functions"`

### Task 11: Catalog guards

**Files:**
- Modify: `supabase/tests/37_tenancy_isolation_test.sql`

- [ ] **Step 1: Add the guards** (raise `plan` by 3):

```sql
reset role;
select is(
  (select array_agg(c.relname::text order by c.relname)
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
      and exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = c.relname
                     and column_name = 'property_id')),
  null, 'every table with property_id has row security enabled');

select is(
  (select array_agg(tablename || '.' || policyname order by 1)
     from pg_policies
    where schemaname = 'public'
      and tablename in (select table_name from information_schema.columns
                         where table_schema = 'public' and column_name = 'property_id')
      and coalesce(qual,'') || coalesce(with_check,'') not similar to
          '%(has_resort_role|auth.uid\(\)|status = ''active''|true)%'),
  null, 'every policy on a resort-owned table checks the resort or the guest');

select is(
  (select array_agg(p.proname::text order by 1)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and p.proname <> all (array[
        'is_platform_admin','resort_role','has_resort_role','assert_resort_role',
        'fill_property_id','handle_new_user',
        'search_availability','get_quote','create_hold','resolve_coupon','confirm_booking',
        'compute_refund','cancel_booking','block_dates','release_expired_holds',
        'release_reservation_coupon','check_in_booking','checkout_booking','current_charges',
        'place_food_order','book_activity','create_service_request','report_maintenance_issue',
        'dashboard_summary','report_revenue','report_occupancy','report_food_sales',
        'report_expenses','staff_shifts_enforce_admin_write','leave_requests_enforce_admin_decision',
        'attendance_records_enforce_own_checkout','attendance_records_force_checkin_time',
        'check_out_attendance','tasks_enforce_write','service_requests_enforce_write',
        'maintenance_issues_enforce_write','enqueue_reservation_outbox','enqueue_outbox_message',
        'render_template','record_reservation_transition','sync_unit_calendar_event',
        'ical_provision_token','rotate_ical_token','ical_export','ical_build_document',
        'ical_export_public','ical_import_event','ical_poll_feed','ical_poll_all_feeds',
        'list_resort_members','add_resort_member','set_member_role','remove_resort_member',
        'platform_resorts','set_resort_status','create_resort'])),
  null, 'every security definer function is on the reviewed allow-list');
```

The `true` alternative in the second guard exists for `reviews_read_all`; if the guard flags any other `true` policy, that policy is wrong — fix the policy, don't widen the pattern.

- [ ] **Step 2: Run** — `supabase test db`. Expected: pass. If a guard lists names, fix the table, policy or function it names and rerun.
- [ ] **Step 3: Commit** — `git commit -am "test(db): guard row security and definer functions against tenancy gaps"`

### Task 12: Retire the global roles (`0046`)

**Files:**
- Create: `supabase/migrations/0046_drop_global_role_helpers.sql`
- Modify: `supabase/seed.sql`, every `supabase/tests/*.sql` that still sets `profiles.role` to a staff role, `supabase/tests/00_setup_test.sql`, `supabase/tests/01_profiles_test.sql`
- Modify: `supabase/tests/36_resort_tenancy_test.sql`

- [ ] **Step 1: Write the failing test** — in `00_setup_test.sql` replace the `user_role` assertion with:

```sql
select enum_has_labels('public', 'platform_role', array['customer','platform_admin']);
```

and in `36_resort_tenancy_test.sql` add (raise `plan` by 3):

```sql
select hasnt_function('public','is_admin', 'is_admin() is gone');
select hasnt_function('public','is_staff_or_above', 'is_staff_or_above() is gone');
select col_type_is('public','profiles','role','platform_role', 'profiles.role is platform_role');
```

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Write the migration**

```sql
-- ResortHub tenancy, part 4: retire the global business roles.

alter table public.profiles drop column role cascade;
alter table public.profiles rename column platform_role to role;

drop function if exists public.assert_staff();
drop function if exists public.is_super_admin();
drop function if exists public.is_admin();
drop function if exists public.is_staff_or_above();
drop function if exists public.current_role();
drop type public.user_role;

create or replace function public.is_platform_admin()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select role = 'platform_admin' from public.profiles where id = auth.uid()),
    false);
$$;
```

`drop column role cascade` also drops the old `profiles_update_self` policy that compares `role`; recreate it right after the rename:

```sql
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid()
              and role = (select p.role from public.profiles p where p.id = auth.uid()));
```

Then read the latest `handle_new_user()` definition and recreate it so it inserts `role = 'customer'` of the new type. Re-run `grep -rn "platform_role\|current_role\|is_admin\|is_staff_or_above\|assert_staff\|is_super_admin" supabase/migrations/0044* supabase/migrations/0045*` and fix any remaining reference.

In `supabase/seed.sql` and every test file, delete the `update public.profiles set role = '<staff role>'` lines (memberships from Tasks 3 and 4 replace them), and change any `platform_role` reference in tests from Tasks 5 and 10 to `role`.

- [ ] **Step 4: Run** — `supabase db reset && supabase test db`. Expected: all pass. Also `supabase migration up --local` on a copy of a `0042` database.
- [ ] **Step 5: Commit**

```bash
git add supabase
git commit -m "feat(db): retire global business roles in favour of resort memberships"
```

---

## Phase 2 — App

### Task 13: Memberships in the signed-in user

**Files:**
- Create: `lib/data/models/resort_membership.dart`
- Modify: `lib/data/models/app_user.dart`
- Modify: `lib/data/repositories/auth_repository.dart:12-22`
- Modify: `lib/core/errors.dart:108-126`
- Test: `test/data/app_user_test.dart`, `test/data/resort_membership_test.dart`, `test/core/errors_test.dart`

**Interfaces:**
- Produces:

```dart
enum ResortRole { owner, admin, staff, accountant }
ResortRole resortRoleFromDb(String raw);
String resortRoleToDb(ResortRole role);
String resortRoleLabel(ResortRole role); // 'Owner','Admin','Staff / Incharge','Accountant'

class ResortMembership {
  const ResortMembership({required this.propertyId, required this.resortName,
      required this.role, this.status = 'active'});
  factory ResortMembership.fromJson(Map<String, dynamic> json);
  final String propertyId;
  final String resortName;
  final ResortRole role;
  final String status;
}

enum PlatformRole { customer, platformAdmin }

class AppUser {
  const AppUser({required this.id, required this.email, this.platformRole = PlatformRole.customer,
      this.memberships = const [], this.fullName, this.phone});
  final PlatformRole platformRole;
  final List<ResortMembership> memberships;
  bool get isPlatformAdmin;
  ResortMembership? membershipFor(String propertyId);
}
```

  `UserRole`, `roleFromDb`, `roleToDb`, `AppUser.role`, `isAdmin` and `isStaffOrAbove` **stay for now**, so the app keeps compiling: `role` is filled from the first membership (`owner` maps to `UserRole.superAdmin`, other roles by name; no membership maps to `UserRole.customer`). Mark them `@Deprecated('Use memberships and currentResortProvider')`. Task 14 removes them.
- Errors: `P0020` → `NotAMember()`, `P0021` → `InvalidState(message)`, `P0022` → `ResortSuspended()`, `P0023` → `InvalidState(message)`. Add the two new `AppFailure` subclasses next to `NotPermitted` in `errors.dart`, with `FailureView.messageFor` texts "You no longer have access to this resort." and "This resort is suspended — changes are disabled."

- [ ] **Step 1: Write the failing tests**

`test/data/resort_membership_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/resort_membership.dart';

void main() {
  test('parses a membership row joined with its resort', () {
    final m = ResortMembership.fromJson({
      'property_id': 'p1',
      'role': 'staff',
      'properties': {'name': 'Pasala Farm House', 'status': 'active'},
    });
    expect(m.propertyId, 'p1');
    expect(m.resortName, 'Pasala Farm House');
    expect(m.role, ResortRole.staff);
    expect(resortRoleLabel(m.role), 'Staff / Incharge');
  });

  test('unknown role text is rejected, not defaulted', () {
    expect(() => resortRoleFromDb('super_admin'), throwsArgumentError);
  });
}
```

`test/data/app_user_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_membership.dart';

void main() {
  const a = ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.owner);
  const b = ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.staff);

  test('membershipFor finds the role at a given resort', () {
    const u = AppUser(id: 'u', email: 'u@x', memberships: [a, b]);
    expect(u.membershipFor('b')?.role, ResortRole.staff);
    expect(u.membershipFor('c'), isNull);
  });

  test('platform admin flag', () {
    const u = AppUser(id: 'u', email: 'u@x', platformRole: PlatformRole.platformAdmin);
    expect(u.isPlatformAdmin, isTrue);
  });
}
```

In `test/core/errors_test.dart` add cases asserting `mapPostgrestError(PostgrestException(message: 'not_a_member', code: 'P0020'))` is a `NotAMember` and `P0022` is a `ResortSuspended`, matching how the file already tests `P0008`.

- [ ] **Step 2: Run to verify failure** — `flutter test test/data test/core/errors_test.dart`. Expected: compile errors (missing types).
- [ ] **Step 3: Implement** the models and error mapping. Resort roles throw `ArgumentError` on unknown text (a silent default would hide a data bug). In `AuthRepository._profileFor`, load memberships in the same call:

```dart
  Future<AppUser> _profileFor(User user) async {
    final row = await _db
        .from('profiles')
        .select('*, resort_members(property_id, role, properties(name, status))')
        .eq('id', user.id)
        .maybeSingle();
    final memberships = ((row?['resort_members'] as List?) ?? const [])
        .map((e) => ResortMembership.fromJson(e as Map<String, dynamic>))
        .toList();
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      fullName: row?['full_name'] as String?,
      phone: row?['phone'] as String?,
      platformRole: row?['role'] == 'platform_admin'
          ? PlatformRole.platformAdmin
          : PlatformRole.customer,
      memberships: memberships,
      // Legacy, removed in Task 14.
      role: memberships.isEmpty
          ? UserRole.customer
          : switch (memberships.first.role) {
              ResortRole.owner => UserRole.superAdmin,
              ResortRole.admin => UserRole.admin,
              ResortRole.staff => UserRole.staff,
              ResortRole.accountant => UserRole.accountant,
            },
    );
  }
```

- [ ] **Step 4: Run** — `flutter test` (whole suite). Expected: pass; `flutter analyze` shows only deprecation infos for the legacy getters plus the 3 pre-existing infos.
- [ ] **Step 5: Commit** — `git commit -am "feat(app): load resort memberships with the signed-in user"`

### Task 14: Current resort, choose-resort screen and routing

**Files:**
- Create: `lib/core/current_resort.dart`
- Create: `lib/features/resorts/choose_resort_screen.dart`
- Modify: `lib/core/router.dart:85-176` (`redirectFor`, `landingPathFor`, routes)
- Modify: every screen that reads the legacy global role — `lib/features/shell/app_shell.dart`, `lib/features/staff/staff_profile_screen.dart`, `lib/features/staff/staff_dashboard_hub_screen.dart`, `lib/features/owner/{expenses,food_sales,staff_performance}_screen.dart`, `lib/features/admin/{attendance,leave_requests,maintenance_issues,service_requests,staff_shifts,tasks}_screen.dart` (find them with `grep -rnE '\.isAdmin|\.isStaffOrAbove|\.role ==|UserRole\.' lib`)
- Modify: `lib/data/models/app_user.dart` — delete `UserRole`, `roleFromDb`, `roleToDb`, `role`, `isAdmin`, `isStaffOrAbove`
- Test: `test/core/current_resort_test.dart`, `test/core/router_test.dart`, `test/features/resorts/choose_resort_screen_test.dart`, and every existing test that builds an `AppUser` with `role:`

**Interfaces:**
- Produces:

```dart
/// The resort the signed-in staff member is working in, or null for
/// customers, platform admins, and users with 2+ memberships who have not
/// picked one yet.
final currentResortProvider = NotifierProvider<CurrentResort, ResortMembership?>(CurrentResort.new);

class CurrentResort extends Notifier<ResortMembership?> {
  Future<void> select(String propertyId); // persists to shared_preferences key 'current_resort_id'
  Future<void> clear();
}

/// Pure resolution used by the notifier and by tests.
ResortMembership? resolveCurrentResort(AppUser? user, String? rememberedId);

String? redirectFor({required AppUser? user, required ResortMembership? resort,
    required String path, required bool onPreAuthScreen});
String landingPathFor(AppUser user, ResortMembership? resort);
```

`resolveCurrentResort`: null user → null; remembered id matching a membership → that membership; exactly one membership → it; otherwise null. A remembered id with no matching membership is ignored (Review Focus #4).

`landingPathFor`: platform admin → `/platform`; no memberships → `/`; memberships but `resort == null` → `/choose-resort`; then by `resort.role`: owner → `/owner`, admin → `/admin`, accountant → `/staff/dashboard`, staff → `/staff`.

`redirectFor`: keep every existing path rule and comment, replacing `user.isAdmin` with `resort?.role` in `{owner, admin}`, `user.isStaffOrAbove` with `resort != null`, and `user.role == UserRole.superAdmin` with `resort?.role == ResortRole.owner`. Add: `/platform` requires `user.isPlatformAdmin`; `/choose-resort` requires `user.memberships.length >= 2`; `/owner/team` requires owner. Any `/admin`, `/staff`, `/owner` path with `resort == null` and memberships present redirects to `/choose-resort`.

- [ ] **Step 1: Write the failing tests**

`test/core/current_resort_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/resort_membership.dart';

void main() {
  const a = ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.owner);
  const b = ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.staff);

  test('single membership is selected automatically', () {
    const u = AppUser(id: 'u', email: 'e', memberships: [a]);
    expect(resolveCurrentResort(u, null), a);
  });

  test('two memberships and nothing remembered: no resort yet', () {
    const u = AppUser(id: 'u', email: 'e', memberships: [a, b]);
    expect(resolveCurrentResort(u, null), isNull);
  });

  test('remembered resort is used when still a member', () {
    const u = AppUser(id: 'u', email: 'e', memberships: [a, b]);
    expect(resolveCurrentResort(u, 'b'), b);
  });

  test('remembered resort the user was removed from is discarded', () {
    const u = AppUser(id: 'u', email: 'e', memberships: [a, b]);
    expect(resolveCurrentResort(u, 'gone'), isNull);
    const single = AppUser(id: 'u', email: 'e', memberships: [a]);
    expect(resolveCurrentResort(single, 'gone'), a);
  });
}
```

In `test/core/router_test.dart`, replace the role-matrix cases with membership cases. The file already calls `redirectFor` directly; add a `resort:` argument everywhere and these cases:

```dart
  test('owner lands on /owner, staff on /staff, accountant on dashboard', () {
    for (final (role, path) in [
      (ResortRole.owner, '/owner'),
      (ResortRole.admin, '/admin'),
      (ResortRole.staff, '/staff'),
      (ResortRole.accountant, '/staff/dashboard'),
    ]) {
      final m = ResortMembership(propertyId: 'a', resortName: 'A', role: role);
      final u = AppUser(id: 'u', email: 'e', memberships: [m]);
      expect(landingPathFor(u, m), path, reason: '$role');
    }
  });

  test('two memberships without a pick go to /choose-resort', () {
    const u = AppUser(id: 'u', email: 'e', memberships: [
      ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.owner),
      ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.staff),
    ]);
    expect(landingPathFor(u, null), '/choose-resort');
    expect(redirectFor(user: u, resort: null, path: '/admin', onPreAuthScreen: false),
        '/choose-resort');
  });

  test('staff at the current resort cannot reach /owner even if owner elsewhere', () {
    const staffHere = ResortMembership(propertyId: 'b', resortName: 'B', role: ResortRole.staff);
    const u = AppUser(id: 'u', email: 'e', memberships: [
      ResortMembership(propertyId: 'a', resortName: 'A', role: ResortRole.owner),
      staffHere,
    ]);
    expect(redirectFor(user: u, resort: staffHere, path: '/owner', onPreAuthScreen: false), '/404');
  });

  test('platform admin lands on /platform; others are refused it', () {
    const admin = AppUser(id: 'p', email: 'e', platformRole: PlatformRole.platformAdmin);
    expect(landingPathFor(admin, null), '/platform');
    const cust = AppUser(id: 'c', email: 'e');
    expect(redirectFor(user: cust, resort: null, path: '/platform', onPreAuthScreen: false), '/404');
  });
```

Add to `test/core/current_resort_test.dart` a test for access loss: build a `ProviderContainer` with a user holding memberships A and B, select B, then call `handleResortAccessLost(container)` (below); assert `currentResortProvider` is null and the remembered id in `SharedPreferences` (use `SharedPreferences.setMockInitialValues({})`) is gone.

`test/features/resorts/choose_resort_screen_test.dart`: pump `ChooseResortScreen` with a `currentUserProvider` override returning a user with memberships A (owner) and B (staff); assert both resort names and their role labels render; tap B; assert `currentResortProvider` now holds B (read it through the `ProviderContainer`).

- [ ] **Step 2: Run to verify failure** — `flutter test test/core test/features/resorts`.
- [ ] **Step 3: Implement.** Wire the router's `refreshListenable`/redirect to read both `currentUserProvider` and `currentResortProvider` the same way it reads the user today. Add the route `/choose-resort` → `ChooseResortScreen`. (`/platform` and `/owner/team` are added by Tasks 19 and 18, which build their screens.) In each listed screen, replace legacy role checks with the current resort's role: `user.isAdmin` → `const {ResortRole.owner, ResortRole.admin}.contains(ref.watch(currentResortProvider)?.role)`; `user.isStaffOrAbove` → `ref.watch(currentResortProvider) != null`; `role == UserRole.superAdmin` → `…?.role == ResortRole.owner`; `role == UserRole.accountant` → `…?.role == ResortRole.accountant`. `staff_profile_screen.dart` shows the role label from `resortRoleLabel`. Add to `current_resort.dart`:

```dart
/// Called wherever a `NotAMember` failure surfaces: the user lost access to
/// the current resort (removed, or the resort was archived). Forget the
/// pick and re-fetch the user so the router re-runs `landingPathFor`.
Future<void> handleResortAccessLost(ProviderContainer container) async {
  await container.read(currentResortProvider.notifier).clear();
  container.invalidate(currentUserProvider);
}
```

and call it (through `ProviderScope.containerOf(context)`) from `FailureView` when the failure is `NotAMember`, after showing its message. Then delete the legacy members from `app_user.dart`, and update every test that constructs `AppUser(role: …)` to pass `memberships:` instead (plus a `currentResortProvider` override where the screen reads it).
- [ ] **Step 4: Run** — `flutter test` (whole suite) passes; `flutter analyze` shows only the 3 pre-existing infos.
- [ ] **Step 5: Commit** — `git commit -am "feat(app): add current resort, choose-resort screen and membership routing"`

### Tasks 15–17: Repositories take the resort

Transformation rule for every method listed below:
- **Lists and reads of resort data** gain a required `String propertyId` parameter and add `.eq('property_id', propertyId)` to the query. RLS alone is not enough: a person with two memberships would otherwise see both resorts (Review Focus #1).
- **Inserts** into the tables listed gain `'property_id': propertyId`.
- **RPCs** with a new `p_property_id` parameter pass it.
- **Providers** that call these methods become `.family` keyed by property id, and screens read `ref.watch(currentResortProvider)!.propertyId` to call them. A screen reached without a current resort is impossible after Task 14's redirect; assert with `!`.
- Methods operating on a single row by id (update/delete by `id`, RPCs taking a reservation id) are unchanged — the database derives and checks the resort.

Each repository test follows the file's existing fake-client pattern and asserts the resort id reaches the query or RPC. Worked example (`test/data/repositories/expense_repository_test.dart`; create it if absent, using the same `FakeSupabaseClient` helper the other repository tests use under `test/data/`):

```dart
  test('list filters by the current resort', () async {
    final db = FakeSupabaseClient();
    final repo = ExpenseRepository(db);
    await repo.list(propertyId: 'resort-a', from: DateTime(2027), to: DateTime(2027, 12, 31));
    expect(db.lastQuery.table, 'expenses');
    expect(db.lastQuery.filters, contains(('eq', 'property_id', 'resort-a')));
  });
```

If no fake Supabase client exists in `test/`, check how `test/data/**` currently tests repositories (`grep -rln "Repository(" test/data`) and follow that; if repositories are only tested through screens with provider overrides, test at that level instead: override the repository provider with a fake that records the `propertyId` it was called with, and assert the screen passes the current resort's id.

### Task 15: Owner and finance repositories

**Files:** `lib/data/repositories/report_repository.dart` (`dashboard`, `revenue`, `occupancy`, `foodSales`, `expenses` — pass `p_property_id`), `expense_repository.dart` (`list`; `create` sets `property_id` in `Expense.toInsert` via a new required `propertyId` field on the model), `food_sale_repository.dart` (`list`, `create` likewise), `staff_performance_repository.dart` (`summary`), `notification_settings_repository.dart` and `refund_rule_repository.dart` (already take `propertyId`; callers switch from the single property to the current resort), `catalog_repository.dart` (`updateSettings` callers switch likewise); the screens under `lib/features/owner/` and `lib/features/reports/`; their tests.

- [ ] Step 1: Write the failing repository/screen tests per the rule above, one per method.
- [ ] Step 2: `flutter test test/data test/features/owner test/features/reports` — fail.
- [ ] Step 3: Implement.
- [ ] Step 4: Same command — pass; `flutter analyze` shows no new issues in these files.
- [ ] Step 5: `git commit -am "feat(app): scope owner and finance data to the current resort"`

### Task 16: Staff-ops repositories

**Files:** `staff_shift_repository.dart` (`list` passes `p_property_id` to `list_staff_shifts`; `createRange` sets `property_id` on each row), `leave_request_repository.dart` (`list`, `create`), `attendance_repository.dart` (`list`, `checkIn`), `task_repository.dart` (`list`, `create`), `outbox_repository.dart` (`messages`), `service_request_repository.dart` (`list`), `maintenance_repository.dart` (`list`), `food_order_repository.dart` (`allOrders`), `stay_repository.dart` (`todaysArrivals`, `checkedIn`); the screens under `lib/features/staff/` and the staff-facing screens under `lib/features/admin/` that call them; their tests.

- [ ] Step 1: Failing tests per the rule, one per method, including a test for `TaskRepository.list` where the fake returns rows for two resorts and only the current resort's reach the screen.
- [ ] Step 2: `flutter test test/data test/features/staff test/features/admin` — fail.
- [ ] Step 3: Implement.
- [ ] Step 4: Pass; no new analyzer issues.
- [ ] Step 5: `git commit -am "feat(app): scope staff operations to the current resort"`

### Task 17: Catalog, bookings and iCal administration

**Files:** `booking_repository.dart` (`allBookings` gains `propertyId`), `catalog_repository.dart` (admin `properties()` list for staff becomes the current resort only; `units(propertyId)` callers switch), `rate_repository.dart`, `ical_repository.dart` (`addFeed` needs no property — the trigger fills it), the screens under `lib/features/admin/` for properties/units/rates/blocking/bookings/OTA; their tests.

- [ ] Step 1: Failing tests per the rule.
- [ ] Step 2: `flutter test test/data test/features/admin test/features/ota` — fail.
- [ ] Step 3: Implement.
- [ ] Step 4: Pass.
- [ ] Step 5: `git commit -am "feat(app): scope catalog, bookings and iCal admin to the current resort"`

### Task 18: Team screen and resort switcher

**Files:**
- Create: `lib/data/repositories/resort_member_repository.dart`
- Create: `lib/features/owner/team_screen.dart`
- Create: `lib/features/resorts/resort_switcher.dart`
- Delete: `lib/features/admin/users_screen.dart`, `lib/data/repositories/user_admin_repository.dart`, `test/features/admin/users_screen_test.dart`
- Modify: `lib/core/router.dart` (route `/owner/team`; remove `/admin/users`), the owner hub's link to it, the staff app bars in `lib/features/shell/`
- Test: `test/features/owner/team_screen_test.dart`, `test/features/resorts/resort_switcher_test.dart`

**Interfaces:**

```dart
class ResortMember {
  const ResortMember({required this.userId, required this.email, this.fullName,
      required this.role, required this.createdAt});
  factory ResortMember.fromJson(Map<String, dynamic> json);
  final String userId; final String email; final String? fullName;
  final ResortRole role; final DateTime createdAt;
}

abstract class ResortMemberSource {
  Future<List<ResortMember>> list(String propertyId);
  Future<void> add(String propertyId, String email, ResortRole role);
  Future<void> setRole(String propertyId, String userId, ResortRole role);
  Future<void> remove(String propertyId, String userId);
}
final resortMemberSourceProvider = Provider<ResortMemberSource>(...);
final resortMembersProvider = FutureProvider.family<List<ResortMember>, String>(...);
```

Team screen: roster with a role dropdown and a remove action per member; an "Add member" dialog taking an email and a role. It keeps the old Users screen's explainer banner, reworded: accounts are created at Sign Up, and owners add them here by email. Errors show `FailureView.messageFor`, so `P0023` shows the database's "last owner" message and `P0002` shows "No account with that email — ask them to sign up first."

Resort switcher: an app-bar action rendered only when the user has 2 or more memberships; a menu of resort names; picking one calls `currentResortProvider.notifier.select(id)` then `context.go(landingPathFor(user, membership))`.

- [ ] **Step 1: Write the failing tests**
  - Team screen with a fake source: renders members and role labels; adding `new@x.com` as Staff calls `add('resort-a','new@x.com',ResortRole.staff)`; a `P0023` failure from `setRole` shows the error text and leaves the dropdown on the old role.
  - Switcher: hidden with one membership; with two, selecting B updates `currentResortProvider` to B.
- [ ] **Step 2: Run** — `flutter test test/features/owner/team_screen_test.dart test/features/resorts` — fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — pass; `flutter analyze` clean of new issues.
- [ ] **Step 5: Commit** — `git commit -am "feat(app): add resort Team screen and resort switcher"`

### Task 19: Platform screen

**Files:**
- Create: `lib/data/repositories/platform_repository.dart`
- Create: `lib/features/platform/platform_screen.dart`
- Modify: `lib/core/router.dart` (route `/platform`)
- Test: `test/features/platform/platform_screen_test.dart`

**Interfaces:**

```dart
class ResortSummary {
  factory ResortSummary.fromJson(Map<String, dynamic> json);
  final String propertyId; final String name; final String status;
  final List<String> ownerEmails; final DateTime createdAt;
  final int bookings30d; final num revenue30d; final int bookings365d; final num revenue365d;
}
abstract class PlatformSource {
  Future<List<ResortSummary>> resorts();
  Future<void> setStatus(String propertyId, String status);
  Future<String> createResort(String name, String ownerEmail);
}
```

Screen: list of resorts with status chip, owners, 30-day bookings and revenue (`formatInr`); Suspend/Reactivate button per row with a confirmation dialog; "New resort" dialog with name and owner email.

- [ ] Step 1: Failing test: renders two resorts from a fake; tapping Suspend then confirming calls `setStatus(id,'suspended')`; creating calls `createResort('Resort E','owner@x.com')` and refreshes the list.
- [ ] Step 2: Run — fail.
- [ ] Step 3: Implement.
- [ ] Step 4: Run — pass.
- [ ] Step 5: `git commit -am "feat(app): add minimal platform console"`

### Task 20: Guest browse and bookings across resorts

**Files:**
- Modify: `lib/features/browse/browse_screen.dart:40-50` (remove the single-property redirect)
- Modify: `lib/data/models/reservation.dart` (add `resortName`), `booking_repository.dart` `myBookings` and `stay_repository.dart` `currentStay`/`mostRecentCheckedOut` (select `*, properties(name)`)
- Modify: the My Bookings and My Stay screens under `lib/features/account/` and `lib/features/stay/`
- Test: `test/features/browse/browse_screen_test.dart`, `test/features/account/my_bookings_screen_test.dart`

- [ ] **Step 1: Write the failing tests**
  - Browse with one active property: stays on the list (no redirect to `/property/<id>`), shows the property card.
  - Browse with two properties: both cards render. (Replace the existing "single property redirects" test.)
  - My Bookings with bookings at two resorts: each row shows its resort name (Review Focus #2).
- [ ] **Step 2: Run** — fail.
- [ ] **Step 3: Implement.** `Reservation.fromJson` reads `json['properties']?['name']` into a nullable `resortName`.
- [ ] **Step 4: Run** — pass.
- [ ] **Step 5: Commit** — `git commit -am "feat(app): list every active resort and label bookings by resort"`

### Task 21: ResortHub branding and welcome-screen fix

**Files:**
- Modify: `lib/main.dart` (`title: 'ResortHub'`), `web/index.html` `<title>`, the welcome screen under `lib/features/auth/` (or wherever `/welcome` is built — `grep -rn "'/welcome'" lib/core/router.dart`)
- Test: `test/features/auth/welcome_screen_test.dart`

- [ ] **Step 1: Write the failing test**: the welcome screen shows "ResortHub" and does not show "Pasala Resorts"; at a 400×900 surface, exactly one hero `Image` is found and its render box's left edge is at x = 0.
- [ ] **Step 2: Run** — fail.
- [ ] **Step 3: Implement.** Neutral copy: "ResortHub" / "Book stays at independent resorts". Keep the hero photo (it's a real resort photo), with the Pasala logo mark removed from the welcome screen. Find the cause of the duplicated left strip in the hero layout (the screenshot shows a second copy of the image in a strip about 16 px wide on the left) and fix it; the test pins it.
- [ ] **Step 4: Run** — pass. Then run the app (`run-web` in `.claude/launch.json`) and compare the welcome screen at 400 px and 1200 px widths.
- [ ] **Step 5: Commit** — `git commit -am "feat(app): rebrand to ResortHub and fix welcome hero layout"`

### Task 22: Docs and full verification

**Files:**
- Modify: `README.md` (ResortHub; how to grant `platform_admin`; how memberships work)
- Modify: `docs/superpowers/specs/2026-08-13-single-property-onboarding-design.md` (one-line "Superseded by 2026-09-24-resorthub-tenancy-design.md" note at the top)

- [ ] **Step 1: README** — add a "Platform admin" section:

```markdown
### Platform admin

Nobody is a platform admin by default. After signing up, grant it once:

    docker exec supabase_db_pasala_farm psql -U postgres -c \
      "update public.profiles set role = 'platform_admin' where id = (select id from auth.users where email = 'you@example.com');"
```

- [ ] **Step 2: Full verification**

```bash
supabase db reset
supabase test db
flutter analyze
flutter test
```

Expected: every pgTAP file passes; analyzer shows only the 3 pre-existing infos; all Flutter tests pass.

- [ ] **Step 3: Manual check in the running app** (`run-web`): sign in as the seeded owner → lands on `/owner` for Pasala; Team screen lists the four seeded staff; as the seeded admin, Pasala data only; grant yourself `platform_admin`, open `/platform`, create "Test Resort" for the seeded accountant's email, sign in as the accountant → the switcher appears with Pasala and Test Resort; Test Resort shows no Pasala bookings or expenses.
- [ ] **Step 4: Commit** — `git commit -am "docs: document ResortHub platform admin and memberships"`
