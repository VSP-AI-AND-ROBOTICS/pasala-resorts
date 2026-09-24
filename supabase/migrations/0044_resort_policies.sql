-- ResortHub tenancy, part 2: every policy checks the row's resort.
-- See docs/superpowers/specs/2026-09-24-resorthub-tenancy-design.md
-- ("Access rules" and "Global data").
--
-- Role sets used below:
--   Staff+ = 'owner','admin','staff','accountant'
--   Admin+ = 'owner','admin'
-- Reads call has_resort_role(property_id, false, ...), which also lets
-- members of a suspended resort read; writes call it with true, which
-- requires the resort to be active. No policy grants a platform admin
-- row access to any resort-owned table.
--
-- This migration changes policies only, plus one missing grant
-- (resort_members was created in 0043 with a read policy but no SELECT
-- grant, which the colleague policy on profiles needs).

grant select on public.resort_members to authenticated;

-- ---------------------------------------------------------------------
-- properties: public when active; staff of the resort; admins update.
-- Creating and deleting resorts goes through create_resort (0045).
-- is_active is kept alongside status so a property an admin hid stays
-- hidden from the public.

drop policy if exists properties_read on public.properties;
drop policy if exists properties_write on public.properties;
create policy properties_read on public.properties
  for select to anon, authenticated
  using ((status = 'active' and is_active)
         or public.has_resort_role(id, false, 'owner','admin','staff','accountant'));
create policy properties_update on public.properties
  for update to authenticated
  using (public.has_resort_role(id, true, 'owner','admin'))
  with check (public.has_resort_role(id, true, 'owner','admin'));

-- ---------------------------------------------------------------------
-- Guest-facing catalog readable by anon: units, slot_types, rate_rules.

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

drop policy if exists slot_types_read on public.slot_types;
drop policy if exists slot_types_write on public.slot_types;
create policy slot_types_read on public.slot_types
  for select to anon, authenticated
  using (exists (select 1 from public.properties p
                  where p.id = slot_types.property_id and p.status = 'active')
         or public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));
create policy slot_types_write on public.slot_types
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

drop policy if exists rate_rules_read on public.rate_rules;
drop policy if exists rate_rules_write on public.rate_rules;
create policy rate_rules_read on public.rate_rules
  for select to anon, authenticated
  using (exists (select 1 from public.properties p
                  where p.id = rate_rules.property_id and p.status = 'active')
         or public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));
create policy rate_rules_write on public.rate_rules
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

-- ---------------------------------------------------------------------
-- Guest-facing catalog for signed-in users: activities, food menu.

drop policy if exists activities_read on public.activities;
drop policy if exists activities_admin_write on public.activities;
create policy activities_read on public.activities
  for select to authenticated
  using (exists (select 1 from public.properties p
                  where p.id = activities.property_id and p.status = 'active')
         or public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));
create policy activities_write on public.activities
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

drop policy if exists food_categories_read on public.food_categories;
drop policy if exists food_categories_admin_write on public.food_categories;
create policy food_categories_read on public.food_categories
  for select to authenticated
  using (exists (select 1 from public.properties p
                  where p.id = food_categories.property_id and p.status = 'active')
         or public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));
create policy food_categories_write on public.food_categories
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

drop policy if exists food_items_read on public.food_items;
drop policy if exists food_items_admin_write on public.food_items;
create policy food_items_read on public.food_items
  for select to authenticated
  using (exists (select 1 from public.properties p
                  where p.id = food_items.property_id and p.status = 'active')
         or public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));
create policy food_items_write on public.food_items
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

-- ---------------------------------------------------------------------
-- unit_calendar_events: public busy-times of active resorts; written
-- only by the sync trigger.

drop policy if exists calendar_events_read on public.unit_calendar_events;
create policy unit_calendar_events_read on public.unit_calendar_events
  for select to anon, authenticated
  using (exists (select 1 from public.properties p
                  where p.id = unit_calendar_events.property_id and p.status = 'active')
         or public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));

-- ---------------------------------------------------------------------
-- reservations: the guest's own, or any role at the resort; admins write.

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

-- ---------------------------------------------------------------------
-- Stay children: resort staff, or the guest who owns the reservation.

drop policy if exists payments_select on public.payments;
drop policy if exists payments_admin_write on public.payments;
create policy payments_read on public.payments
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','staff','accountant')
         or exists (select 1 from public.reservations r
                     where r.id = payments.reservation_id and r.customer_id = auth.uid()));
create policy payments_write on public.payments
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

drop policy if exists food_orders_read on public.food_orders;
drop policy if exists food_orders_admin_write on public.food_orders;
create policy food_orders_read on public.food_orders
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','staff','accountant')
         or exists (select 1 from public.reservations r
                     where r.id = food_orders.reservation_id and r.customer_id = auth.uid()));
create policy food_orders_update on public.food_orders
  for update to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin','staff','accountant'))
  with check (public.has_resort_role(property_id, true, 'owner','admin','staff','accountant'));

drop policy if exists food_order_items_read on public.food_order_items;
create policy food_order_items_read on public.food_order_items
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','staff','accountant')
         or exists (select 1 from public.food_orders o
                      join public.reservations r on r.id = o.reservation_id
                     where o.id = food_order_items.order_id and r.customer_id = auth.uid()));

-- activity_bookings_owner_cancel (guest cancels own booking) is kept
-- unchanged: it only allows setting status = 'cancelled'.
drop policy if exists activity_bookings_read on public.activity_bookings;
create policy activity_bookings_read on public.activity_bookings
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','staff','accountant')
         or exists (select 1 from public.reservations r
                     where r.id = activity_bookings.reservation_id and r.customer_id = auth.uid()));

-- service_requests / maintenance_issues: the old using(true) update
-- policies relied on *_enforce_write triggers (rewritten in 0045); the
-- policy itself now scopes updates to the resort's staff.
drop policy if exists service_requests_read on public.service_requests;
drop policy if exists service_requests_update on public.service_requests;
create policy service_requests_read on public.service_requests
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','staff','accountant')
         or exists (select 1 from public.reservations r
                     where r.id = service_requests.reservation_id and r.customer_id = auth.uid()));
create policy service_requests_update on public.service_requests
  for update to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin','staff','accountant'))
  with check (public.has_resort_role(property_id, true, 'owner','admin','staff','accountant'));

drop policy if exists maintenance_issues_read on public.maintenance_issues;
drop policy if exists maintenance_issues_update on public.maintenance_issues;
create policy maintenance_issues_read on public.maintenance_issues
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','staff','accountant')
         or exists (select 1 from public.reservations r
                     where r.id = maintenance_issues.reservation_id and r.customer_id = auth.uid()));
create policy maintenance_issues_update on public.maintenance_issues
  for update to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin','staff','accountant'))
  with check (public.has_resort_role(property_id, true, 'owner','admin','staff','accountant'));

-- ---------------------------------------------------------------------
-- Coupons.

drop policy if exists coupon_redemptions_select on public.coupon_redemptions;
drop policy if exists coupon_redemptions_admin_write on public.coupon_redemptions;
create policy coupon_redemptions_read on public.coupon_redemptions
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','staff','accountant')
         or customer_id = auth.uid());
create policy coupon_redemptions_write on public.coupon_redemptions
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

drop policy if exists coupons_read_active on public.coupons;
drop policy if exists coupons_admin_write on public.coupons;
create policy coupons_read on public.coupons
  for select to authenticated
  using ((is_active
          and (customer_id is null or customer_id = auth.uid())
          and exists (select 1 from public.properties p
                       where p.id = coupons.property_id and p.status = 'active'))
         or public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));
create policy coupons_write on public.coupons
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

-- ---------------------------------------------------------------------
-- reviews: public read (the app filters by resort); the checked-out
-- guest insert policy reviews_insert is kept unchanged.

drop policy if exists reviews_read_all on public.reviews;
create policy reviews_read on public.reviews
  for select to authenticated
  using (true);

-- ---------------------------------------------------------------------
-- Resort settings and messaging.

drop policy if exists refund_rules_read on public.refund_rules;
drop policy if exists refund_rules_admin_write on public.refund_rules;
create policy refund_rules_read on public.refund_rules
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));
create policy refund_rules_write on public.refund_rules
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

drop policy if exists notification_settings_read on public.notification_settings;
drop policy if exists notification_settings_admin_write on public.notification_settings;
create policy notification_settings_read on public.notification_settings
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));
create policy notification_settings_write on public.notification_settings
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

drop policy if exists outbox_read on public.outbox;
create policy outbox_read on public.outbox
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));

-- outbox_templates: a resort's own templates, plus the platform
-- defaults (property_id null) for anyone who is a member of any resort
-- (every resort role is Staff+).
drop policy if exists outbox_templates_read on public.outbox_templates;
drop policy if exists outbox_templates_admin_write on public.outbox_templates;
create policy outbox_templates_read on public.outbox_templates
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','staff','accountant')
         or (property_id is null
             and exists (select 1 from public.resort_members m
                          where m.user_id = auth.uid())));
create policy outbox_templates_write on public.outbox_templates
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

-- ---------------------------------------------------------------------
-- Finance.

drop policy if exists expenses_read on public.expenses;
drop policy if exists expenses_admin_write on public.expenses;
create policy expenses_read on public.expenses
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','accountant'));
create policy expenses_write on public.expenses
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

drop policy if exists food_activity_sales_read on public.food_activity_sales;
drop policy if exists food_activity_sales_insert on public.food_activity_sales;
drop policy if exists food_activity_sales_admin_write on public.food_activity_sales;
drop policy if exists food_activity_sales_admin_delete on public.food_activity_sales;
create policy food_activity_sales_read on public.food_activity_sales
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));
create policy food_activity_sales_insert on public.food_activity_sales
  for insert to authenticated
  with check (public.has_resort_role(property_id, true, 'owner','admin','staff','accountant'));
create policy food_activity_sales_update on public.food_activity_sales
  for update to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));
create policy food_activity_sales_delete on public.food_activity_sales
  for delete to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'));

-- ---------------------------------------------------------------------
-- Staff operations. The old using(true) update/delete policies relied
-- on *_enforce_* triggers (rewritten in 0045); the policies themselves
-- now scope writes to the row's resort.

drop policy if exists staff_shifts_admin_select on public.staff_shifts;
drop policy if exists staff_shifts_own_read on public.staff_shifts;
drop policy if exists staff_shifts_admin_insert on public.staff_shifts;
drop policy if exists staff_shifts_admin_update on public.staff_shifts;
drop policy if exists staff_shifts_admin_delete on public.staff_shifts;
create policy staff_shifts_read on public.staff_shifts
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin')
         or staff_id = auth.uid());
create policy staff_shifts_insert on public.staff_shifts
  for insert to authenticated
  with check (public.has_resort_role(property_id, true, 'owner','admin'));
create policy staff_shifts_update on public.staff_shifts
  for update to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));
create policy staff_shifts_delete on public.staff_shifts
  for delete to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'));

drop policy if exists tasks_admin_select on public.tasks;
drop policy if exists tasks_own_read on public.tasks;
drop policy if exists tasks_admin_insert on public.tasks;
drop policy if exists tasks_update on public.tasks;
drop policy if exists tasks_admin_delete on public.tasks;
create policy tasks_read on public.tasks
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin')
         or assignee_id = auth.uid());
create policy tasks_insert on public.tasks
  for insert to authenticated
  with check (public.has_resort_role(property_id, true, 'owner','admin'));
-- The assignee's column limits stay in tasks_enforce_write.
create policy tasks_update on public.tasks
  for update to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin')
         or assignee_id = auth.uid())
  with check (public.has_resort_role(property_id, true, 'owner','admin')
              or assignee_id = auth.uid());
create policy tasks_delete on public.tasks
  for delete to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'));

drop policy if exists leave_requests_admin_select on public.leave_requests;
drop policy if exists leave_requests_own_read on public.leave_requests;
drop policy if exists leave_requests_own_insert on public.leave_requests;
drop policy if exists leave_requests_admin_update on public.leave_requests;
create policy leave_requests_read on public.leave_requests
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin')
         or staff_id = auth.uid());
create policy leave_requests_insert on public.leave_requests
  for insert to authenticated
  with check (staff_id = auth.uid()
              and status = 'pending'
              and decided_by is null
              and decided_at is null
              and public.has_resort_role(property_id, true, 'owner','admin','staff','accountant'));
create policy leave_requests_update on public.leave_requests
  for update to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

drop policy if exists attendance_records_admin_select on public.attendance_records;
drop policy if exists attendance_records_own_read on public.attendance_records;
drop policy if exists attendance_records_own_insert on public.attendance_records;
create policy attendance_records_read on public.attendance_records
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin')
         or staff_id = auth.uid());
create policy attendance_records_insert on public.attendance_records
  for insert to authenticated
  with check (staff_id = auth.uid()
              and work_date = (now() at time zone 'Asia/Kolkata')::date
              and check_out_at is null
              and public.has_resort_role(property_id, true, 'owner','admin','staff','accountant'));

-- ---------------------------------------------------------------------
-- audit_log: resort events only; platform events (property_id null)
-- are read through platform functions.

drop policy if exists audit_log_read on public.audit_log;
create policy audit_log_read on public.audit_log
  for select to authenticated
  using (property_id is not null
         and public.has_resort_role(property_id, false, 'owner','admin','staff','accountant'));

-- ---------------------------------------------------------------------
-- iCal sync.

drop policy if exists ical_feeds_admin on public.ical_feeds;
create policy ical_feeds_read on public.ical_feeds
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin'));
create policy ical_feeds_write on public.ical_feeds
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

drop policy if exists ical_export_tokens_admin on public.ical_export_tokens;
create policy ical_export_tokens_read on public.ical_export_tokens
  for select to authenticated
  using (public.has_resort_role(property_id, false, 'owner','admin'));
create policy ical_export_tokens_write on public.ical_export_tokens
  for all to authenticated
  using (public.has_resort_role(property_id, true, 'owner','admin'))
  with check (public.has_resort_role(property_id, true, 'owner','admin'));

-- ---------------------------------------------------------------------
-- profiles stay global. Policies here never select from profiles
-- directly (that recursed): role comparisons go through the security
-- definer helpers current_role() and is_platform_admin().
-- profiles_review_author_read is kept unchanged.

drop policy if exists profiles_select_self on public.profiles;
drop policy if exists profiles_update_self on public.profiles;
drop policy if exists profiles_admin_select on public.profiles;
drop policy if exists profiles_admin_insert on public.profiles;
drop policy if exists profiles_admin_update on public.profiles;
drop policy if exists profiles_admin_delete on public.profiles;

create policy profiles_read_self on public.profiles
  for select to authenticated
  using (id = auth.uid());

-- A resort member may read a guest's profile only when the guest has a
-- reservation at that resort.
create policy profiles_read_resort_guest on public.profiles
  for select to authenticated
  using (exists (select 1 from public.reservations r
                  where r.customer_id = profiles.id
                    and public.has_resort_role(r.property_id, false,
                          'owner','admin','staff','accountant')));

-- Members of the same resort (as far as resort_members_read lets the
-- caller see that resort's roster).
create policy profiles_read_colleague on public.profiles
  for select to authenticated
  using (exists (select 1 from public.resort_members a
                   join public.resort_members b using (property_id)
                  where a.user_id = auth.uid() and b.user_id = profiles.id));

-- Self-update may not change either role column. current_role() and
-- is_platform_admin() read the stored row, so the new values must
-- match what is already there.
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid()
              and role = public.current_role()
              and (platform_role = 'platform_admin') = public.is_platform_admin());

-- ---------------------------------------------------------------------
-- outbox: rows derive their resort from the reservation, like the
-- derivable tables in 0043, so outbox_read can see rows the (not yet
-- rewritten) enqueue functions insert without property_id. Backfill
-- first with user triggers disabled (same reasoning as 0043), then
-- attach the trigger.

alter table public.outbox disable trigger user;
update public.outbox o
   set property_id = r.property_id
  from public.reservations r
 where r.id = o.reservation_id
   and o.property_id is null;
alter table public.outbox enable trigger user;

create trigger outbox_fill_property
  before insert or update on public.outbox
  for each row execute function public.fill_property_id('reservations', 'reservation_id');

-- ---------------------------------------------------------------------
-- properties.status is platform-controlled: properties_update lets a
-- resort's owner/admin edit their resort, but not suspend, archive or
-- reactivate it. No authenticated caller (migrations, admin SQL) is
-- allowed through.

create function public.properties_guard_status()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status is distinct from old.status
     and auth.uid() is not null
     and not public.is_platform_admin() then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;
  return new;
end;
$$;

create trigger properties_guard_status
  before update on public.properties
  for each row execute function public.properties_guard_status();
