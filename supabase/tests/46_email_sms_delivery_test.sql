-- P7: email and SMS delivery (0056_email_sms_delivery.sql). Sections are
-- added task by task; each relies on the state the earlier ones leave.
begin;
select plan(20);

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

select * from finish();
rollback;
