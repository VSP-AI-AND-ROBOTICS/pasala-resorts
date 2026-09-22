-- The notification outbox. There is no email/SMS/WhatsApp provider
-- configured yet, so this file proves everything up to the moment of
-- sending -- and never past it: nothing here may ever observe
-- `status = 'sent'`.

begin;
select plan(29);

select has_table('public', 'outbox', 'outbox table exists');
select has_table('public', 'outbox_templates', 'outbox_templates table exists');

insert into public.properties (id, name, slug)
values ('a9000000-0000-0000-0000-000000000001', 'Outbox Prop', 'outbox-prop');

insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('b9000000-0000-0000-0000-000000000001',
        'a9000000-0000-0000-0000-000000000001', 'Garden Suite', 4, 6);

-- base 10000/night, +1500 per extra guest, 1500 cleaning -- the same
-- well-established fixture as 03_quote_test.sql, so one weekday night for
-- 4 guests (at capacity_base) totals the familiar 11500.
insert into public.rate_rules
  (unit_id, kind, price, extra_guest_price, cleaning_fee, priority)
values ('b9000000-0000-0000-0000-000000000001', 'base', 10000, 1500, 1500, 0);

insert into auth.users (id, email) values
  ('c9000000-0000-0000-0000-000000000001', 'outbox-priya@example.com'),
  ('c9000000-0000-0000-0000-000000000002', 'outbox-ravi@example.com'),
  ('c9000000-0000-0000-0000-000000000003', 'outbox-staff@example.com');

-- Customer 1 has a phone on file; customer 2 does not -- mirroring the
-- brief's own observation that most seeded customers have no phone. This
-- is what lets one file prove BOTH the deliverable-channel path (email
-- always, sms/whatsapp when a phone exists) and the skip path (sms/
-- whatsapp when it doesn't), from two realistic profiles rather than one.
update public.profiles set full_name = 'Priya Sharma', phone = '+919876543210'
  where id = 'c9000000-0000-0000-0000-000000000001';
update public.profiles set full_name = 'Ravi Menon'
  where id = 'c9000000-0000-0000-0000-000000000002';
update public.profiles set role = 'staff'
  where id = 'c9000000-0000-0000-0000-000000000003';

-- === business actions: booking_confirmation / payment_success / ===========
-- === cancellation, customer WITH a phone on file ===========================
--
-- outbox is staff-read-only with no "own reservation" carve-out (see the
-- RLS section near the bottom), so every content assertion below runs as
-- staff -- these business actions themselves still run as the owning
-- customer, exactly as a real booking would.

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"c9000000-0000-0000-0000-000000000001","role":"authenticated"}';

select lives_ok(
  $$select public.create_hold('b9000000-0000-0000-0000-000000000001',
      '2026-08-03','2026-08-04', 4, null, 11500)$$,
  'a hold is created for the outbox fixture');

select set_config('app.outbox_res1',
  (select id::text from public.reservations
    where unit_id = 'b9000000-0000-0000-0000-000000000001'
      and lower(period) >= '2026-08-03' and lower(period) < '2026-08-04'),
  true);

select lives_ok(
  $$select public.confirm_booking(current_setting('app.outbox_res1')::uuid,
      'outbox_ref_1', 11500)$$,
  'confirm_booking succeeds for the outbox fixture');

select lives_ok(
  $$select public.cancel_booking(current_setting('app.outbox_res1')::uuid,
      'change of plans')$$,
  'cancel_booking succeeds for the outbox fixture');

-- === the same booking_confirmation transition for a customer with NO ======
-- === phone on file: the sms/whatsapp channels must be SKIPPED, never ======
-- === enqueued with an empty recipient ======================================

set local request.jwt.claims to
  '{"sub":"c9000000-0000-0000-0000-000000000002","role":"authenticated"}';

select lives_ok(
  $$select public.create_hold('b9000000-0000-0000-0000-000000000001',
      '2026-09-10','2026-09-11', 4, null, 11500)$$,
  'a second hold is created for the customer with no phone on file');

select set_config('app.outbox_res2',
  (select id::text from public.reservations
    where unit_id = 'b9000000-0000-0000-0000-000000000001'
      and lower(period) >= '2026-09-10' and lower(period) < '2026-09-11'),
  true);

select lives_ok(
  $$select public.confirm_booking(current_setting('app.outbox_res2')::uuid,
      'outbox_ref_2', 11500)$$,
  'confirm_booking succeeds for the no-phone fixture');

-- === an abandoned hold that never confirmed does NOT enqueue a ============
-- === cancellation -- it was never a booking the guest was told about ======

select lives_ok(
  $$select public.create_hold('b9000000-0000-0000-0000-000000000001',
      '2026-10-20','2026-10-21', 4, null, 11500)$$,
  'a third hold is created, and never confirmed');

select set_config('app.outbox_res3',
  (select id::text from public.reservations
    where unit_id = 'b9000000-0000-0000-0000-000000000001'
      and lower(period) >= '2026-10-20' and lower(period) < '2026-10-21'),
  true);

select lives_ok(
  $$select public.cancel_booking(current_setting('app.outbox_res3')::uuid,
      'changed my mind')$$,
  'cancelling a still-on-hold reservation succeeds');

-- === RLS, part 1: a customer cannot read the outbox, not even for their ===
-- === own reservation ========================================================

select is(
  (select count(*)::int from public.outbox),
  0,
  'a customer cannot read the outbox -- RLS scopes it to staff-or-above '
  'only, with no "own reservation" carve-out');

-- === everything below reads/writes the outbox as staff =====================

set local request.jwt.claims to
  '{"sub":"c9000000-0000-0000-0000-000000000003","role":"authenticated"}';

select ok(
  (select count(*)::int from public.outbox) > 0,
  'staff can read the outbox');

select is(
  (select count(*)::int from public.outbox
    where template = 'booking_confirmation' and status = 'pending'
      and reservation_id = current_setting('app.outbox_res1')::uuid),
  1,
  'confirming a booking enqueues exactly one booking_confirmation row in '
  'pending');

select is(
  (select count(*)::int from public.outbox
    where template = 'payment_success' and status = 'pending'
      and reservation_id = current_setting('app.outbox_res1')::uuid),
  1,
  'confirming a booking also enqueues a payment_success row in pending');

-- Priya has a phone, so the sms/whatsapp variants of booking_confirmation
-- are deliverable too, not skipped.
select is(
  (select count(*)::int from public.outbox
    where template in ('booking_confirmation_sms', 'booking_confirmation_whatsapp')
      and status = 'pending'
      and reservation_id = current_setting('app.outbox_res1')::uuid),
  2,
  'a customer with a phone on file gets pending sms and whatsapp rows too');

select ok(
  (select body from public.outbox
    where template = 'booking_confirmation'
      and reservation_id = current_setting('app.outbox_res1')::uuid) like '%Priya Sharma%',
  'the rendered body contains the guest name');

select ok(
  (select body from public.outbox
    where template = 'booking_confirmation'
      and reservation_id = current_setting('app.outbox_res1')::uuid) like '%Garden Suite%',
  'the rendered body contains the unit name');

select ok(
  (select body from public.outbox
    where template = 'booking_confirmation'
      and reservation_id = current_setting('app.outbox_res1')::uuid) like '%03 Aug 2026%',
  'the rendered body contains the check-in date');

select ok(
  (select body from public.outbox
    where template = 'booking_confirmation'
      and reservation_id = current_setting('app.outbox_res1')::uuid) like '%04 Aug 2026%',
  'the rendered body contains the check-out date');

select is(
  (select count(*)::int from public.outbox
    where template = 'cancellation' and status = 'pending'
      and reservation_id = current_setting('app.outbox_res1')::uuid),
  1,
  'cancelling enqueues a cancellation row in pending');

select is(
  (select count(*)::int from public.outbox
    where reservation_id = current_setting('app.outbox_res3')::uuid),
  0,
  'THE FIX: cancelling a reservation that was still just a HOLD (never '
  'confirmed) enqueues nothing at all -- there was no booking to tell the '
  'guest was cancelled');

select is(
  (select count(*)::int from public.outbox
    where template = 'booking_confirmation' and status = 'pending'
      and reservation_id = current_setting('app.outbox_res2')::uuid),
  1,
  'the email channel is still enqueued and pending -- email always exists');

select is(
  (select status::text from public.outbox
    where template = 'booking_confirmation_sms'
      and reservation_id = current_setting('app.outbox_res2')::uuid),
  'skipped',
  'THE DESIGN POINT: sms is skipped, not enqueued as pending, when the '
  'customer has no phone');

select is(
  (select recipient from public.outbox
    where template = 'booking_confirmation_sms'
      and reservation_id = current_setting('app.outbox_res2')::uuid),
  'no phone on file',
  'the skipped row explains itself in the recipient column, not an empty '
  'string');

select ok(
  (select last_error from public.outbox
    where template = 'booking_confirmation_sms'
      and reservation_id = current_setting('app.outbox_res2')::uuid) is not null,
  'the skipped row records WHY it was skipped');

-- === global invariant: no row, for ANY reservation in this file, was ======
-- === ever enqueued with an empty recipient =================================

select is(
  (select count(*)::int from public.outbox where btrim(recipient) = ''),
  0,
  'no row is ever enqueued with an empty recipient');

-- Carried-forward fix (task 9 review -> task 11/12): `render_template`
-- coalesced `guest_name` but not `unit_name`/`property_name`, and
-- Postgres's `replace()` returns NULL if ANY of its arguments is NULL -- so
-- one NULL context value would have silently collapsed the ENTIRE rendered
-- body to NULL, not just left one token unreplaced. Every deliverable
-- (non-skipped) row in this file went through that substitution loop, so
-- this is a real, not vacuous, check that it never happened.
select is(
  (select count(*)::int from public.outbox
    where status = 'pending' and body is null),
  0,
  'THE FIX: a rendered (pending) outbox row''s body is never NULL');

-- === nothing in this phase may ever be marked sent =========================

select is(
  (select count(*)::int from public.outbox where status = 'sent'),
  0,
  'no row has ever been marked sent -- there is no delivery provider yet');

-- === nobody -- not even staff -- can write to the outbox directly; the ====
-- === SECURITY DEFINER trigger is the only writer ===========================

select throws_ok(
  $$insert into public.outbox
      (reservation_id, channel, recipient, template, status)
    values (current_setting('app.outbox_res1')::uuid, 'email',
            'hacker@example.com', 'booking_confirmation', 'pending')$$,
  '42501', null,
  'even staff cannot insert into the outbox directly -- only the trigger '
  'writes to it');

select throws_ok(
  $$update public.outbox set status = 'sent'
      where reservation_id = current_setting('app.outbox_res1')::uuid$$,
  '42501', null,
  'nobody can update outbox rows directly -- in particular nobody can '
  'mark one sent, since there is no client-side write path at all');

reset role;

select * from finish();
rollback;
