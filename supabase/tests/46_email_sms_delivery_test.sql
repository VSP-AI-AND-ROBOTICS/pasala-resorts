-- P7: email and SMS delivery (0056_email_sms_delivery.sql). Sections are
-- added task by task; each relies on the state the earlier ones leave.
begin;
select plan(37);

-- === fixtures ===============================================================
-- The seed's confirmed booking queued outbox rows of its own; clear them
-- (inside this transaction) so every claim below sees only this file's rows.
delete from public.outbox;
delete from public.outbox_channel_status;

insert into auth.users (id, email) values
  ('d7000000-0000-0000-0000-0000000000a1','p7-a-owner@example.com'),
  ('d7000000-0000-0000-0000-0000000000a2','p7-a-admin@example.com'),
  ('d7000000-0000-0000-0000-0000000000a3','p7-a-staff@example.com'),
  ('d7000000-0000-0000-0000-0000000000a4','p7-a-acct@example.com'),
  ('d7000000-0000-0000-0000-0000000000b1','p7-b-owner@example.com'),
  ('d7000000-0000-0000-0000-0000000000c1','p7-asha@example.com'),
  ('d7000000-0000-0000-0000-0000000000c2','p7-bala@example.com');

-- Asha has a phone on file; Bala does not.
update public.profiles set full_name = 'Asha Rao', phone = '+91 98765 43210'
 where id = 'd7000000-0000-0000-0000-0000000000c1';
update public.profiles set full_name = 'Bala Iyer', phone = null
 where id = 'd7000000-0000-0000-0000-0000000000c2';

insert into public.properties (id, name, slug) values
  ('d7a00000-0000-4000-8000-000000000001','P7 Resort A','p7-a'),
  ('d7b00000-0000-4000-8000-000000000001','P7 Resort B','p7-b');

insert into public.resort_members (property_id, user_id, role) values
  ('d7a00000-0000-4000-8000-000000000001','d7000000-0000-0000-0000-0000000000a1','owner'),
  ('d7a00000-0000-4000-8000-000000000001','d7000000-0000-0000-0000-0000000000a2','admin'),
  ('d7a00000-0000-4000-8000-000000000001','d7000000-0000-0000-0000-0000000000a3','staff'),
  ('d7a00000-0000-4000-8000-000000000001','d7000000-0000-0000-0000-0000000000a4','accountant'),
  ('d7b00000-0000-4000-8000-000000000001','d7000000-0000-0000-0000-0000000000b1','owner');

insert into public.units (id, property_id, name, capacity_base, capacity_max) values
  ('d7a00000-0000-4000-8000-000000000011','d7a00000-0000-4000-8000-000000000001','Mango Cottage',2,4),
  ('d7b00000-0000-4000-8000-000000000011','d7b00000-0000-4000-8000-000000000001','Neem Villa',2,4);

-- Confirmed bookings queue their messages through the reservations trigger.
-- A (Asha, phone on file): booking_confirmation (email), booking_confirmation_sms,
--   booking_confirmation_whatsapp and payment_success (email) -- all pending.
-- B (Bala, no phone): the two emails pending; sms and whatsapp skipped.
insert into public.reservations (id, unit_id, period, kind, status, customer_id, guests) values
  ('d7a00000-0000-4000-8000-000000000021','d7a00000-0000-4000-8000-000000000011',
   tstzrange('2027-03-01 14:00+05:30','2027-03-02 11:00+05:30','[)'),
   'booking','confirmed','d7000000-0000-0000-0000-0000000000c1',2),
  ('d7b00000-0000-4000-8000-000000000021','d7b00000-0000-4000-8000-000000000011',
   tstzrange('2027-03-01 14:00+05:30','2027-03-02 11:00+05:30','[)'),
   'booking','confirmed','d7000000-0000-0000-0000-0000000000c2',2);

-- === Task 1: contract ========================================================
select is((select count(*)::int from public.outbox where status = 'pending'), 6,
  'fixture: six messages are pending (four for A, two for B)');

select enum_has_labels('public', 'outbox_status',
  array['pending','sent','failed','skipped','dry_run'],
  'outbox_status gains dry_run');

select has_column('public', 'outbox', 'next_attempt_at', 'outbox.next_attempt_at exists');
select col_not_null('public', 'outbox', 'next_attempt_at', 'next_attempt_at is required');
select has_column('public', 'outbox', 'last_attempt_at', 'outbox.last_attempt_at exists');
select has_column('public', 'outbox', 'provider_message_id', 'outbox.provider_message_id exists');

select has_table('public', 'outbox_channel_status', 'outbox_channel_status exists');
select ok((select relrowsecurity from pg_class
            where oid = 'public.outbox_channel_status'::regclass),
  'outbox_channel_status has RLS on');
select ok(not has_table_privilege('authenticated', 'public.outbox_channel_status', 'select')
      and not has_table_privilege('anon', 'public.outbox_channel_status', 'select'),
  'clients cannot read outbox_channel_status directly');

select has_function('public', 'claim_outbox_batch', array['integer'],
  'claim_outbox_batch(int) exists');
select has_function('public', 'complete_outbox_message', array['uuid','text','text','text'],
  'complete_outbox_message(uuid, text, text, text) exists');
select has_function('public', 'record_outbox_dispatch_run', array['jsonb'],
  'record_outbox_dispatch_run(jsonb) exists');
select has_function('public', 'outbox_delivery_status', array['uuid'],
  'outbox_delivery_status(uuid) exists');
select has_function('public', 'retry_outbox_message', array['uuid'],
  'retry_outbox_message(uuid) exists');
select has_function('public', 'outbox_template_context', array['uuid'],
  'outbox_template_context(uuid) exists');
select has_function('public', 'outbox_dispatch_post', array['text','text'],
  'outbox_dispatch_post(text, text) exists');
select has_function('public', 'outbox_dispatch_tick', array[]::name[],
  'outbox_dispatch_tick() exists');
select has_function('public', 'outbox_retry_delay', array['integer'],
  'outbox_retry_delay(int) exists');

-- Who may execute what: the dispatcher's three functions run only as
-- service_role, the app's two only as authenticated, the internals for
-- no client role at all.
select is(
  (select array_agg(fn || ':' || r order by fn, r)
     from unnest(array[
            'public.claim_outbox_batch(integer)',
            'public.complete_outbox_message(uuid,text,text,text)',
            'public.record_outbox_dispatch_run(jsonb)',
            'public.outbox_delivery_status(uuid)',
            'public.retry_outbox_message(uuid)',
            'public.outbox_template_context(uuid)',
            'public.outbox_dispatch_post(text,text)',
            'public.outbox_dispatch_tick()']) as fn,
          unnest(array['anon','authenticated','service_role']) as r
    where has_function_privilege(r, fn, 'execute')),
  array[
    'public.claim_outbox_batch(integer):service_role',
    'public.complete_outbox_message(uuid,text,text,text):service_role',
    'public.outbox_delivery_status(uuid):authenticated',
    'public.record_outbox_dispatch_run(jsonb):service_role',
    'public.retry_outbox_message(uuid):authenticated'],
  'execute grants: dispatcher functions for service_role, app functions for authenticated, internals for nobody');

select is(
  (select array_agg(p.proname::text order by p.proname)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('claim_outbox_batch','complete_outbox_message',
                        'record_outbox_dispatch_run','outbox_delivery_status',
                        'retry_outbox_message','outbox_template_context',
                        'outbox_dispatch_tick')
      and p.prosecdef
      and p.proconfig @> array['search_path=public, pg_temp']),
  array['claim_outbox_batch','complete_outbox_message','outbox_delivery_status',
        'outbox_dispatch_tick','outbox_template_context',
        'record_outbox_dispatch_run','retry_outbox_message'],
  'the seven new definer functions pin their search_path');

-- === Task 2: template context and claiming =====================================
select is(public.outbox_template_context('d7a00000-0000-4000-8000-000000000021') ->> 'guest_name',
  'Asha Rao', 'the template context names the guest');
select is(public.outbox_template_context('d7a00000-0000-4000-8000-000000000021') ->> 'property_name',
  'P7 Resort A', 'the template context names the resort');
select is(public.render_template('booking_confirmation', 'd7a00000-0000-4000-8000-000000000021') ->> 'subject',
  'Your stay at P7 Resort A is confirmed',
  'render_template still renders, through the shared context');
select throws_ok($$select public.outbox_template_context('d7a00000-0000-4000-8000-0000000000ff')$$,
  'P0002', null, 'an unknown reservation has no context');

-- A turns SMS off after its messages were queued.
insert into public.notification_settings (property_id, email_enabled, sms_enabled)
values ('d7a00000-0000-4000-8000-000000000001', true, false);

set local role authenticated;
set local request.jwt.claims to '{"sub":"d7000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select throws_ok($$select * from public.claim_outbox_batch(10)$$,
  '42501', null, 'a resort owner cannot claim outbox rows');
reset role;
set local request.jwt.claims to '';

set local role service_role;
create temp table p7_claim1 as select * from public.claim_outbox_batch(10);
reset role;

select is((select count(*)::int from p7_claim1), 4,
  'the claim returns the four due email rows (A''s SMS is off, WhatsApp is never claimed)');
select is((select count(*)::int from p7_claim1 where channel = 'whatsapp'), 0,
  'whatsapp rows are never claimed');
select is(
  (select status::text || ' / ' || last_error from public.outbox
    where template = 'booking_confirmation_sms'
      and property_id = 'd7a00000-0000-4000-8000-000000000001'),
  'skipped / sms notifications are disabled in this property''s settings',
  'a queued SMS whose channel was switched off is skipped at claim time');
select is((select status::text from public.outbox where template = 'booking_confirmation_whatsapp'
             and property_id = 'd7a00000-0000-4000-8000-000000000001'),
  'pending', 'the whatsapp row stays pending');
select is((select array_agg(distinct attempts) from p7_claim1), array[1],
  'each claimed row counts one attempt');
select is(
  (select count(*)::int from public.outbox o join p7_claim1 c on c.id = o.id
    where o.attempts = 1 and o.last_attempt_at = now()
      and o.next_attempt_at = now() + interval '5 minutes'),
  4, 'claimed rows are leased for five minutes');
select ok(
  (select bool_and(vars ->> 'property_name' is not null
                   and not vars ? 'customer_email'
                   and not vars ? 'customer_phone')
     from p7_claim1),
  'claimed rows carry template variables without contact details');
select is(
  (select vars ->> 'property_name' from p7_claim1
    where property_id = 'd7b00000-0000-4000-8000-000000000001' limit 1),
  'P7 Resort B', 'each row carries its own resort''s variables');

set local role service_role;
select is((select count(*)::int from public.claim_outbox_batch(10)), 0,
  'a second run in the same minute claims nothing (the rows are leased)');
reset role;

-- The lease on two A rows runs out; the one due longest comes first.
update public.outbox set next_attempt_at = now() - interval '2 minutes'
 where template = 'booking_confirmation' and property_id = 'd7a00000-0000-4000-8000-000000000001';
update public.outbox set next_attempt_at = now() - interval '1 minute'
 where template = 'payment_success' and property_id = 'd7a00000-0000-4000-8000-000000000001';

set local role service_role;
create temp table p7_claim2 as select * from public.claim_outbox_batch(1);
reset role;
select is((select template || ' #' || attempts from p7_claim2), 'booking_confirmation #2',
  'p_limit is honoured and the longest-due row comes first, on its second attempt');

-- A row that has used all five attempts is failed, not sent a sixth time.
update public.outbox set attempts = 5
 where template = 'payment_success' and property_id = 'd7a00000-0000-4000-8000-000000000001';
set local role service_role;
select is((select count(*)::int from public.claim_outbox_batch(10)), 0,
  'a row at the attempt limit is not claimed');
reset role;
select is(
  (select status::text from public.outbox
    where template = 'payment_success' and property_id = 'd7a00000-0000-4000-8000-000000000001'),
  'failed', 'a row at the attempt limit is failed');

select * from finish();
rollback;
