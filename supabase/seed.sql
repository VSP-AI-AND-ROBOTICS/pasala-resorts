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

insert into public.properties
  (id, name, slug, description, address, check_in_time, check_out_time, amenities)
values
  ('a0000000-0000-0000-0000-000000000001','Pasala Farm House','pasala-farm-house',
   'A boutique farmhouse resort with a private pool and themed cottages.',
   '- Bommalaramaram Rd, Rangapuram, Telangana',
   '14:00','11:00', array['Pool','Wi-Fi','Barbecue','Parking','Spacious','Garden']);

insert into public.resort_members (property_id, user_id, role) values
  ('a0000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','owner'),
  ('a0000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','admin'),
  ('a0000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','staff'),
  ('a0000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000004','accountant');

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


-- Starter food menu and activity catalog for the Guest Stay Experience
-- feature (0032_food_ordering.sql / 0033_activity_booking.sql).
insert into public.food_categories (id, property_id, name, sort_order) values
  ('60000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Breakfast', 1),
  ('60000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Lunch', 2),
  ('60000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Dinner', 3),
  ('60000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Snacks', 4),
  ('60000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 'Beverages', 5);

insert into public.food_items (category_id, name, description, price) values
  ('60000000-0000-0000-0000-000000000001', 'South Indian Thali', 'Idli, dosa, sambar, chutney', 250),
  ('60000000-0000-0000-0000-000000000001', 'Bread Omelette', 'Two eggs, buttered toast', 150),
  ('60000000-0000-0000-0000-000000000002', 'Veg Thali', 'Rice, dal, two curries, roti', 300),
  ('60000000-0000-0000-0000-000000000002', 'Chicken Biryani', 'Hyderabadi style, raita included', 380),
  ('60000000-0000-0000-0000-000000000003', 'Barbecue Platter', 'Grilled chicken and vegetables', 550),
  ('60000000-0000-0000-0000-000000000003', 'Paneer Tikka Masala', 'With butter naan', 320),
  ('60000000-0000-0000-0000-000000000004', 'Masala Fries', null, 120),
  ('60000000-0000-0000-0000-000000000004', 'Pakora Platter', 'Mixed vegetable fritters', 150),
  ('60000000-0000-0000-0000-000000000005', 'Filter Coffee', null, 60),
  ('60000000-0000-0000-0000-000000000005', 'Fresh Lime Soda', null, 80);

insert into public.activities (id, property_id, name, description, price_per_person, capacity_per_slot) values
  ('62000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001',
   'Swimming', 'Private pool access', 0, 20),
  ('62000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001',
   'Bonfire', 'Evening bonfire with music', 500, 40),
  ('62000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001',
   'Badminton', 'Court and equipment', 100, 8),
  ('62000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001',
   'Cricket', 'Turf and equipment', 100, 22),
  ('62000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001',
   'Cycling', 'Guided farmhouse trail ride', 150, 10),
  ('62000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001',
   'Indoor Games', 'Carrom, chess, table tennis', 0, 12),
  ('62000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000001',
   'Nature Walk', 'Guided walk around the property', 0, 15);

-- 0049_subscriptions.sql starts every resort that already exists on
-- Enterprise, active, with no end date. The seed runs after the
-- migrations, so do the same for the seeded resort.
insert into public.resort_subscriptions (property_id, tier, status)
select id, 'enterprise', 'active' from public.properties
on conflict (property_id) do nothing;
