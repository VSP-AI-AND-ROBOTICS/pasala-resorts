-- notification_settings + enqueue_outbox_message's channel-disabled skip
-- path, added in 0028_notification_settings.sql. All three channels
-- default to ENABLED (an opt-out control) -- see that migration's header
-- for why defaulting to disabled would have been a real behaviour change
-- for every property that never visits the new Settings screen.
--
-- The migration backfills a row only for properties that existed AT
-- MIGRATION TIME -- a property created afterwards (like this file's own
-- fixture, inserted inside its own test transaction) gets no row at all
-- until someone actually saves the Settings screen. This file proves BOTH
-- that no-row case (the coalesce fallback in `enqueue_outbox_message`
-- defaults to enabled) and the explicit-row case (an owner turning a
-- channel off).

begin;
select plan(9);

select has_table('public', 'notification_settings', 'notification_settings table exists');

insert into public.properties (id, name, slug)
values ('a9100000-0000-0000-0000-000000000001', 'Notif Prop', 'notif-prop');

insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('b9100000-0000-0000-0000-000000000001',
        'a9100000-0000-0000-0000-000000000001', 'Notif Suite', 4, 6);

insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority)
values ('b9100000-0000-0000-0000-000000000001', 'base', 10000, 1500, 1500, 0);

insert into auth.users (id, email) values
  ('c9100000-0000-0000-0000-000000000001', 'notif-customer@example.com'),
  ('c9100000-0000-0000-0000-000000000002', 'notif-staff@example.com');

update public.profiles set full_name = 'Notif Customer', phone = '+919876500000'
  where id = 'c9100000-0000-0000-0000-000000000001';
update public.profiles set role = 'staff'
  where id = 'c9100000-0000-0000-0000-000000000002';

insert into public.resort_members (property_id, user_id, role) values
  ('a9100000-0000-0000-0000-000000000001','c9100000-0000-0000-0000-000000000002','staff');

select is(
  (select count(*)::int from public.notification_settings
    where property_id = 'a9100000-0000-0000-0000-000000000001'),
  0,
  'a property created after the migration has no settings row yet -- the '
  'backfill only covered properties that already existed'
);

-- === with no settings row at all, a confirmed booking still gets a ========
-- === deliverable sms for a customer WITH a phone -- the coalesce fallback =
-- === in enqueue_outbox_message defaults every channel to enabled ==========

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"c9100000-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$select public.create_hold('b9100000-0000-0000-0000-000000000001',
      '2026-08-03','2026-08-04', 4, null, 11500)$$,
  'a hold is created');

select set_config('app.notif_res1',
  (select id::text from public.reservations
    where unit_id = 'b9100000-0000-0000-0000-000000000001'
      and lower(period) >= '2026-08-03' and lower(period) < '2026-08-04'),
  true);

select lives_ok(
  $$select public.confirm_booking(current_setting('app.notif_res1')::uuid,
      'notif_ref_1', 11500)$$,
  'confirm_booking succeeds');

set local request.jwt.claims to
  '{"sub":"c9100000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select status::text from public.outbox
    where template = 'booking_confirmation_sms'
      and reservation_id = current_setting('app.notif_res1')::uuid),
  'pending',
  'sms is deliverable by default with no settings row at all -- the '
  'coalesce fallback treats a missing row as every channel enabled'
);

-- === once an owner saves Settings with sms explicitly off, the very next =
-- === booking confirmation skips it, with a reason distinct from "no ======
-- === phone on file" ===========================================================

reset role;
insert into public.notification_settings (property_id, sms_enabled)
values ('a9100000-0000-0000-0000-000000000001', false);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"c9100000-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$select public.create_hold('b9100000-0000-0000-0000-000000000001',
      '2026-09-10','2026-09-11', 4, null, 11500)$$,
  'a second hold is created after disabling sms');

select set_config('app.notif_res2',
  (select id::text from public.reservations
    where unit_id = 'b9100000-0000-0000-0000-000000000001'
      and lower(period) >= '2026-09-10' and lower(period) < '2026-09-11'),
  true);

select lives_ok(
  $$select public.confirm_booking(current_setting('app.notif_res2')::uuid,
      'notif_ref_2', 11500)$$,
  'confirm_booking succeeds for the second hold');

set local request.jwt.claims to
  '{"sub":"c9100000-0000-0000-0000-000000000002","role":"authenticated"}';

select is(
  (select status::text from public.outbox
    where template = 'booking_confirmation_sms'
      and reservation_id = current_setting('app.notif_res2')::uuid),
  'skipped',
  'sms is skipped once the channel is explicitly disabled, even with a phone on file'
);

select ok(
  (select last_error from public.outbox
    where template = 'booking_confirmation_sms'
      and reservation_id = current_setting('app.notif_res2')::uuid)
    like '%disabled%',
  'the skip reason names the disabled setting, not a missing phone'
);

reset role;
select * from finish();
rollback;
