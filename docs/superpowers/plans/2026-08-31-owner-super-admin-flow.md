# Owner / Super Admin Flow — Implementation Plan

Design rationale: `docs/superpowers/specs/2026-08-31-owner-super-admin-flow-design.md`.

Flow: Owner Login → Business Dashboard → Revenue → Occupancy → Bookings →
Food/Activity Sales → Expenses → Staff Performance → Reports → Settings
(Farmhouse info, Pricing, Taxes, Payment configuration, Cancellation
policy, Booking rules, Staff permissions, Notification settings).

## Tasks

1. **Schema** — migrations `0025`–`0030` (property settings + `get_quote`
   tax/night-range, food/activity sales + report RPC, expenses + report
   RPC, notification settings + outbox skip path, staff performance RPC +
   `tasks.completed_at`, dashboard summary extension), each paired with a
   pgTAP test (`supabase/tests/21`–`26`).
2. **Data layer** — new models (`food_sale`, `expense`, `staff_performance`,
   `notification_settings`, `refund_rule`), new repositories for each, plus
   targeted extensions to `report_repository.dart` and
   `catalog_repository.dart` (`updateSettings`).
3. **UI** — `lib/features/owner/`: hub screen, Business Dashboard, Food &
   Activity Sales (CRUD), Expenses (CRUD), Staff Performance (read-only),
   Reports (CSV export hub), Settings hub + Tax/Payment/Cancellation
   Policy/Booking Rules/Notification sub-screens. Farmhouse Information,
   Pricing, and Staff permissions link to existing admin screens instead of
   duplicating them.
4. **Routing** — `/owner/*` route tree, `super_admin`-only gate in
   `redirectFor`, `landingPathFor` sends `super_admin` to `/owner`,
   `AppShell` swaps the "Admin" nav destination for "Owner" for that role.
5. **Tests** — widget tests for the new CRUD/read screens
   (`test/features/owner/`), router tests for the new `/owner` gating.
6. **Verification** — `supabase db reset && supabase test db`,
   `flutter analyze`, `flutter test`, manual click-through as
   `super@pasala.test` in a browser.

## Result

All six migrations and their pgTAP tests pass. The only test failures
remaining after this change are a pre-existing, environment-level issue
(see the spec's "Known pre-existing issue" section) affecting every table
in the app equally, not something this feature introduced.
