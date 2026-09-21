-- ResortHub Supabase Seed Data Migration
-- Pre-populates 4 resorts across subscription tiers (Premium, Super, Basic, Free)
-- and populates demo accounts, units, reservations, food items, staff, and payments.

-- 1. Insert Subscription Plans
INSERT INTO subscription_plans (id, tier, name, price_monthly, features) VALUES
  ('11111111-1111-1111-1111-111111111111', 'premium', 'Premium Tier Plan', 299.00, '["Top Priority Discovery", "Unlimited Analytics", "Full Financial Auditing", "24/7 Priority Support"]'),
  ('22222222-2222-2222-2222-222222222222', 'super', 'Super Tier Plan', 149.00, '["Elevated Discovery", "Advanced Staff Ops", "Standard Reports", "Email Support"]'),
  ('33333333-3333-3333-3333-333333333333', 'basic', 'Basic Tier Plan', 49.00, '["Standard Discovery", "Basic Booking", "Core Reporting"]'),
  ('44444444-4444-4444-4444-444444444444', 'free', 'Free Tier Plan', 0.00, '["Basic Listing", "Manual Confirmation Only"]')
ON CONFLICT (tier) DO NOTHING;

-- 2. Insert Resorts across all 4 tiers with distinct geographic locations
INSERT INTO resorts (id, name, slug, description, address, city, state, country, latitude, longitude, contact_email, contact_phone, subscription_tier, status, image_urls, amenities) VALUES
  (
    'a1111111-1111-1111-1111-111111111111',
    'Grand Palms Beach Resort',
    'grand-palms',
    'Ultra-luxury 5-star beachfront paradise featuring private infinity pools, wellness spa, and gourmet dining.',
    '100 Oceanfront Boulevard, Calangute',
    'Goa',
    'Goa',
    'India',
    15.5497,
    73.7536,
    'contact@grandpalms.com',
    '+91 98765 43210',
    'premium',
    'active',
    '["https://images.unsplash.com/photo-1566073771259-6a8506099945", "https://images.unsplash.com/photo-1582719508461-905c673771fd"]',
    '["Private Beach", "Infinity Pool", "Luxury Spa", "Gourmet Restaurant", "Free High-Speed Wi-Fi", "Airport Shuttle"]'
  ),
  (
    'b2222222-2222-2222-2222-222222222222',
    'Highland Mist Mountain Resort',
    'highland-mist',
    'Serene hillside retreat nestled in lush tea plantations with scenic mountain panoramas and bonfire nights.',
    '45 Estate Road, Munnar',
    'Munnar',
    'Kerala',
    'India',
    10.0889,
    77.0595,
    'info@highlandmist.com',
    '+91 98765 43211',
    'super',
    'active',
    '["https://images.unsplash.com/photo-1540555700478-4be289fbecef"]',
    '["Mountain View", "Tea Garden Walks", "Fireplace Lounge", "Restaurant", "Wi-Fi"]'
  ),
  (
    'c3333333-3333-3333-3333-333333333333',
    'Lakeside Eco Lodge',
    'lakeside-eco',
    'Tranquil lakeside eco-resort with wooden cottages, kayaking, organic dining, and bird watching.',
    '12 Vembanad Lake Trail, Kumarakom',
    'Kumarakom',
    'Kerala',
    'India',
    9.6175,
    76.4301,
    'hello@lakesideeco.com',
    '+91 98765 43212',
    'basic',
    'active',
    '["https://images.unsplash.com/photo-1571896349842-33c89424de2d"]',
    '["Lake View", "Kayaking", "Organic Dining", "Garden"]'
  ),
  (
    'd4444444-4444-4444-4444-444444444444',
    'Pine Valley Budget Cottages',
    'pine-valley',
    'Cozy budget-friendly wooden chalets surrounded by pine forests with essential amenities.',
    '88 Pine Woods Way, Manali',
    'Manali',
    'Himachal Pradesh',
    'India',
    32.2432,
    77.1892,
    'stay@pinevalley.com',
    '+91 98765 43213',
    'free',
    'active',
    '["https://images.unsplash.com/photo-1520250497591-112f2f40a3f4"]',
    '["Forest View", "Hot Water", "Parking", "Bonfire"]'
  )
ON CONFLICT (id) DO NOTHING;

-- 3. Insert Units for Grand Palms Resort
INSERT INTO units (id, resort_id, name, type, capacity, price_per_night, description, status, amenities) VALUES
  (
    'u1111111-1111-1111-1111-111111111111',
    'a1111111-1111-1111-1111-111111111111',
    'Ocean Villa 101',
    'villa',
    4,
    450.00,
    'Luxury beachfront villa with private plunge pool and direct ocean balcony access.',
    'available',
    '["King Bed", "Private Pool", "Ocean View", "Mini Bar", "Jacuzzi"]'
  ),
  (
    'u2222222-2222-2222-2222-222222222222',
    'a1111111-1111-1111-1111-111111111111',
    'Deluxe Garden Suite 202',
    'suite',
    2,
    250.00,
    'Spacious suite with lush tropical garden views and marble bath.',
    'available',
    '["Queen Bed", "Garden View", "Work Desk", "Balcony"]'
  )
ON CONFLICT (id) DO NOTHING;

-- 4. Insert Food Categories & Items for Grand Palms
INSERT INTO food_categories (id, resort_id, name) VALUES
  ('fc111111-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 'Seafood Specialties'),
  ('fc222222-2222-2222-2222-222222222222', 'a1111111-1111-1111-1111-111111111111', 'Beverages & Cocktails')
ON CONFLICT (id) DO NOTHING;

INSERT INTO food_items (id, resort_id, category_id, name, description, price, is_available) VALUES
  ('fi111111-1111-1111-1111-111111111111', 'a1111111-1111-1111-1111-111111111111', 'fc111111-1111-1111-1111-111111111111', 'Grilled Tiger Prawns', 'Marinated in Goan spices with garlic butter', 28.00, true),
  ('fi222222-2222-2222-2222-222222222222', 'a1111111-1111-1111-1111-111111111111', 'fc222222-2222-2222-2222-222222222222', 'Fresh Coconut Mojito', 'Refresher made with organic mint and coconut water', 12.00, true)
ON CONFLICT (id) DO NOTHING;
