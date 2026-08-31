-- Local development data only. Never loaded in a deployed environment.

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data,
                        raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token,
                        email_change_token_new, email_change)
select
  u.id, '00000000-0000-0000-0000-000000000000', 'authenticated',
  'authenticated', u.email, crypt('password123', gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('full_name', u.full_name),
  now(), now(),
  -- GoTrue scans these into non-nullable Go strings; NULL breaks sign-in
  -- with "Database error querying schema" (confirmation_token Scan error).
  '', '', '', ''
from (values
  ('10000000-0000-0000-0000-000000000001'::uuid,'super@pasala.test','Super Admin'),
  ('10000000-0000-0000-0000-000000000002'::uuid,'admin@pasala.test','Asha Admin'),
  ('10000000-0000-0000-0000-000000000003'::uuid,'staff@pasala.test','Sita Staff'),
  ('10000000-0000-0000-0000-000000000004'::uuid,'accounts@pasala.test','Anil Accounts'),
  ('10000000-0000-0000-0000-000000000005'::uuid,'ravi@example.com','Ravi Kumar'),
  ('10000000-0000-0000-0000-000000000006'::uuid,'meera@example.com','Meera Nair')
) as u(id, email, full_name);

insert into auth.identities (id, provider_id, user_id, identity_data, provider,
                             last_sign_in_at, created_at, updated_at)
select
  gen_random_uuid(), u.id::text, u.id,
  jsonb_build_object('sub', u.id::text, 'email', u.email),
  'email', now(), now(), now()
from (values
  ('10000000-0000-0000-0000-000000000001'::uuid,'super@pasala.test'),
  ('10000000-0000-0000-0000-000000000002'::uuid,'admin@pasala.test'),
  ('10000000-0000-0000-0000-000000000003'::uuid,'staff@pasala.test'),
  ('10000000-0000-0000-0000-000000000004'::uuid,'accounts@pasala.test'),
  ('10000000-0000-0000-0000-000000000005'::uuid,'ravi@example.com'),
  ('10000000-0000-0000-0000-000000000006'::uuid,'meera@example.com')
) as u(id, email);

-- The signup trigger created customer profiles; promote the staff accounts.
update public.profiles set role = 'super_admin'
  where id = '10000000-0000-0000-0000-000000000001';
update public.profiles set role = 'admin'
  where id = '10000000-0000-0000-0000-000000000002';
update public.profiles set role = 'staff'
  where id = '10000000-0000-0000-0000-000000000003';
update public.profiles set role = 'accountant'
  where id = '10000000-0000-0000-0000-000000000004';

insert into public.properties
  (id, name, slug, description, address, check_in_time, check_out_time, amenities)
values
  ('a0000000-0000-0000-0000-000000000001','Pasala Farm House','pasala-farm-house',
   'A boutique farmhouse resort with a private pool and themed cottages.',
   'Shamirpet, Hyderabad',
   '14:00','11:00', array['Pool','Wi-Fi','Barbecue','Parking','Garden']);

insert into public.slot_types (id, property_id, code, start_time, end_time)
values
  ('50000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
   'day','09:00','18:00'),
  ('50000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',
   'night','18:00','09:00');

insert into public.units
  (id, property_id, name, capacity_base, capacity_max, booking_mode)
values
  ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
   'Pasala Farm House', 20, 40, 'nightly');

-- base rate for the one whole-property unit
insert into public.rate_rules
  (unit_id, kind, label, price, extra_guest_price, cleaning_fee, priority)
values
  ('b0000000-0000-0000-0000-000000000001','base','Weekday',18000,1000,2500,0);

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
  ('b0000000-0000-0000-0000-000000000001',
   public.build_period('b0000000-0000-0000-0000-000000000001',
                       current_date + 7, current_date + 9),
   'booking','confirmed','10000000-0000-0000-0000-000000000005',2,'app');

insert into public.reservations
  (unit_id, period, kind, status, block_reason, source)
values
  ('b0000000-0000-0000-0000-000000000001',
   public.build_period('b0000000-0000-0000-0000-000000000001',
                       current_date + 14, current_date + 16),
   'block','confirmed','Deep cleaning','admin');
