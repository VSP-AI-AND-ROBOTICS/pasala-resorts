# Owner / Super Admin Flow — Design

## Why

The owner (`super_admin`) had no view of the business distinct from a
regular `admin`'s `/admin` section, and several owner-level concerns —
cancellation policy, tax rate, booking limits, payment display settings,
notification channel toggles — had no UI at all: they were either
Postgres-Studio-only (refund policy, `advance_pct`) or didn't exist in the
schema (tax, food/activity sales, expenses, staff performance, booking
rules, notification toggles).

## Scope decisions

- **New dedicated `/owner` section**, gated to `super_admin` only in
  `redirectFor` (`lib/core/router.dart`). `/admin` is untouched for
  admin/staff/accountant. Route guarding is UX only — every RPC/table below
  carries its own Postgres-level gate.
- **Food/Activity Sales and Expenses get full CRUD + reports** — new
  tables, RLS, RPCs, and admin-style screens, not a reports-only shell.
- **Payment configuration is business-facing only**: advance %, displayed
  payment methods, a gateway display name. Real gateway credentials
  (`RAZORPAY_KEY_ID`/`SECRET`) remain a `--dart-define` build-time concern —
  never stored in the database or editable through this screen.
- Wherever a flow step already had a real, working screen (Revenue/
  Occupancy reports, Bookings, Farmhouse info, Pricing, Staff permissions),
  the Owner hub links to it rather than duplicating it.

## Database (migrations `0025`–`0030`)

- **`0025_property_settings.sql`** — `properties.tax_pct`/`gstin`/
  `min_nights`/`max_nights`/`payment_display_methods`/`gateway_display_name`,
  all zero/null-defaulted (no behaviour change until an owner sets a
  value). `get_quote` gains tax as an additive line (`tax_amount`, added
  after the coupon discount) and a min/max-nights check for nightly
  bookings, new error code `P0015`.
- **`0026_food_activity_sales.sql`** — `food_activity_sales` (staff-or-above
  read/insert, admin-only update/delete) + `report_food_sales` RPC.
- **`0027_expenses.sql`** — `expenses` (admin/accountant/super_admin read,
  admin-only write — tighter than sales, since this is financial data) +
  `report_expenses` RPC.
- **`0028_notification_settings.sql`** — `notification_settings`
  (email/sms/whatsapp toggles, **all default enabled** — an opt-out
  control, since every channel was already reachable whenever contact info
  existed; defaulting to disabled would have been a real behaviour change).
  `enqueue_outbox_message` now skips a disabled channel with a
  `'skipped'` row naming the reason, distinct from "no phone on file".
- **`0029_staff_performance.sql`** — `tasks.completed_at` (set once, on the
  first transition to `done`) + `staff_performance_summary` RPC (`security
  invoker`, reads only tables that already have working admin-select RLS —
  no new policies needed).
- **`0030_owner_dashboard_summary.sql`** — `dashboard_summary()` gains
  `food_sales_today`/`expenses_month_total`/`net_profit_month`, purely
  additive; `/admin/dashboard` needs no change to keep working.

## Known pre-existing issue found during verification

Running the full `supabase test db` suite surfaced that this local
Postgres/Supabase image now grants `anon`/`authenticated` broad default
table privileges via `ALTER DEFAULT PRIVILEGES` (`pg_default_acl`) —
meaning a `select * from <table>` that this app's own design expects to be
rejected outright (`42501`, no grant) instead succeeds and returns zero
rows (RLS still correctly hides everything; there is no actual data leak).
This affects **every** table in the app, old and new alike (`07_rls_test`,
`11_coupons_test`, `18_leave_requests_test`, `19_attendance_records_test`,
`20_tasks_test`, and this feature's own `22`/`23` all show the identical
symptom) — it predates this feature and is an environment/version-drift
issue, not something introduced here. Left unfixed as out of scope for this
change; worth its own investigation.

## Flutter

- `lib/features/owner/` — new screens, following the existing
  `ConsumerWidget`/`FutureProvider`/`AsyncView`/`FailureView`/`EmptyState`
  pattern throughout (see `tasks_screen.dart` as the template for every
  CRUD screen here).
- `lib/data/models/food_sale.dart`, `expense.dart`, `staff_performance.dart`,
  `notification_settings.dart`, `refund_rule.dart` — plain hand-written
  classes, matching `report.dart`'s style.
- `Property` gained six new optional fields, read-only via
  `Property.toInsert()` (which `PropertyFormScreen` still uses unmodified) —
  written instead through `CatalogRepository.updateSettings`, a narrow
  targeted update each Settings screen calls with only the columns it owns.
- `lib/core/router.dart` — `/owner/*` routes, `super_admin`-only redirect
  branch, `landingPathFor` sends `super_admin` to `/owner` (was `/admin`).
- `lib/features/shell/app_shell.dart` — `super_admin` gets an "Owner" nav
  destination instead of "Admin"; the Owner hub links into `/admin/*` for
  anything not rebuilt here, so no capability is lost.
