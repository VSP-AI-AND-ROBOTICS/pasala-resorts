-- ========================================================
-- RESORTHUB LIVE SUPABASE DATABASE SCHEMA & REALTIME CONFIG
-- ========================================================

-- 1. Profiles Table (User Accounts across 5 roles)
CREATE TABLE IF NOT EXISTS public.profiles (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'customer',
  resort_id TEXT,
  phone TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Resorts Table
CREATE TABLE IF NOT EXISTS public.resorts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  description TEXT,
  address TEXT,
  city TEXT NOT NULL,
  state TEXT NOT NULL,
  country TEXT DEFAULT 'India',
  latitude NUMERIC(10,6),
  longitude NUMERIC(10,6),
  contact_email TEXT,
  contact_phone TEXT,
  subscription_tier TEXT NOT NULL DEFAULT 'free',
  status TEXT DEFAULT 'active',
  image_urls TEXT[],
  amenities TEXT[],
  rating NUMERIC(3,2) DEFAULT 4.5,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Resort Units Table (Rooms & Inventory)
CREATE TABLE IF NOT EXISTS public.units (
  id TEXT PRIMARY KEY,
  resort_id TEXT REFERENCES public.resorts(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'room',
  capacity INT NOT NULL DEFAULT 2,
  price_per_night NUMERIC(10,2) NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'available',
  amenities TEXT[],
  image_urls TEXT[],
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Reservations Table (Bookings)
CREATE TABLE IF NOT EXISTS public.reservations (
  id TEXT PRIMARY KEY,
  resort_id TEXT REFERENCES public.resorts(id) ON DELETE CASCADE,
  customer_id TEXT,
  unit_id TEXT NOT NULL,
  unit_name TEXT,
  guest_name TEXT NOT NULL,
  guest_email TEXT NOT NULL,
  guest_phone TEXT NOT NULL,
  guest_count INT DEFAULT 2,
  check_in DATE NOT NULL,
  check_out DATE NOT NULL,
  total_amount NUMERIC(10,2) NOT NULL,
  advance_amount NUMERIC(10,2) NOT NULL,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Booking Payments Table
CREATE TABLE IF NOT EXISTS public.booking_payments (
  id TEXT PRIMARY KEY,
  reservation_id TEXT REFERENCES public.reservations(id) ON DELETE CASCADE,
  resort_id TEXT REFERENCES public.resorts(id) ON DELETE CASCADE,
  amount NUMERIC(10,2) NOT NULL,
  status TEXT DEFAULT 'succeeded',
  transaction_ref TEXT UNIQUE NOT NULL,
  idempotency_key TEXT UNIQUE,
  payment_method TEXT DEFAULT 'card',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Staff Members Table
CREATE TABLE IF NOT EXISTS public.staff_members (
  id TEXT PRIMARY KEY,
  resort_id TEXT REFERENCES public.resorts(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  status TEXT DEFAULT 'active',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Staff Tasks Table
CREATE TABLE IF NOT EXISTS public.staff_tasks (
  id TEXT PRIMARY KEY,
  resort_id TEXT REFERENCES public.resorts(id) ON DELETE CASCADE,
  incharge_id TEXT,
  assigned_to_staff_id TEXT,
  title TEXT NOT NULL,
  description TEXT,
  priority TEXT DEFAULT 'medium',
  status TEXT DEFAULT 'pending',
  due_date TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Resort Expenses Table
CREATE TABLE IF NOT EXISTS public.expenses (
  id TEXT PRIMARY KEY,
  resort_id TEXT REFERENCES public.resorts(id) ON DELETE CASCADE,
  category TEXT NOT NULL,
  description TEXT NOT NULL,
  amount NUMERIC(10,2) NOT NULL,
  expense_date DATE DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ========================================================
-- ENABLE REALTIME WEBSOCKET SUBSCRIPTIONS
-- ========================================================
ALTER PUBLICATION supabase_realtime ADD TABLE public.reservations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.staff_tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE public.units;
