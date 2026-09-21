-- ResortHub Supabase RLS Policies Migration
-- Enforces multi-tenant data isolation and role-based access control (RBAC)

-- Helper function to fetch current authenticated user's role
CREATE OR REPLACE FUNCTION auth_user_role()
RETURNS app_role AS $$
  SELECT role FROM profiles WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER;

-- Helper function to fetch current authenticated user's assigned resort_id
CREATE OR REPLACE FUNCTION auth_user_resort_id()
RETURNS UUID AS $$
  SELECT resort_id FROM profiles WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER;

-- Enable Row Level Security on all core tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE resorts ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE resort_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE units ENABLE ROW LEVEL SECURITY;
ALTER TABLE rate_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE ledger_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- 1. Profiles Policies
CREATE POLICY "Public profiles reading for authenticated users"
  ON profiles FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Users can update their own profile"
  ON profiles FOR UPDATE TO authenticated
  USING (id = auth.uid());

CREATE POLICY "Super Admins can manage all profiles"
  ON profiles FOR ALL TO authenticated
  USING (auth_user_role() = 'super_admin');

-- 2. Resorts Policies
CREATE POLICY "Anyone can view active resorts"
  ON resorts FOR SELECT
  USING (status = 'active' OR auth_user_role() = 'super_admin' OR id = auth_user_resort_id());

CREATE POLICY "Super Admins and assigned Admins can update resort"
  ON resorts FOR UPDATE TO authenticated
  USING (auth_user_role() = 'super_admin' OR (auth_user_role() = 'admin' AND id = auth_user_resort_id()));

CREATE POLICY "Super Admins can insert or delete resorts"
  ON resorts FOR ALL TO authenticated
  USING (auth_user_role() = 'super_admin');

-- 3. Subscription Plans Policies
CREATE POLICY "Anyone can view subscription plans"
  ON subscription_plans FOR SELECT TO authenticated, anon
  USING (true);

CREATE POLICY "Only Super Admins can manage subscription plans"
  ON subscription_plans FOR ALL TO authenticated
  USING (auth_user_role() = 'super_admin');

-- 4. Resort Subscriptions & Payments Policies
CREATE POLICY "Super Admin and assigned Admin can view subscriptions"
  ON resort_subscriptions FOR SELECT TO authenticated
  USING (auth_user_role() = 'super_admin' OR resort_id = auth_user_resort_id());

CREATE POLICY "Super Admin and assigned Admin can manage subscriptions"
  ON resort_subscriptions FOR ALL TO authenticated
  USING (auth_user_role() = 'super_admin' OR (auth_user_role() = 'admin' AND resort_id = auth_user_resort_id()));

CREATE POLICY "Super Admin and assigned Admin/Accountant can view subscription payments"
  ON subscription_payments FOR SELECT TO authenticated
  USING (auth_user_role() = 'super_admin' OR resort_id = auth_user_resort_id());

-- 5. Units & Rate Rules Policies
CREATE POLICY "Anyone can view units of active resorts"
  ON units FOR SELECT
  USING (true);

CREATE POLICY "Admin and Incharge can manage resort units"
  ON units FOR ALL TO authenticated
  USING (auth_user_role() = 'super_admin' OR (resort_id = auth_user_resort_id() AND auth_user_role() IN ('admin', 'incharge')));

CREATE POLICY "Anyone can view rate rules"
  ON rate_rules FOR SELECT USING (true);

CREATE POLICY "Admin can manage rate rules"
  ON rate_rules FOR ALL TO authenticated
  USING (auth_user_role() = 'super_admin' OR (resort_id = auth_user_resort_id() AND auth_user_role() = 'admin'));

-- 6. Reservations & Booking Payments Policies
CREATE POLICY "Customers can view their own reservations; Staff/Admins view resort reservations"
  ON reservations FOR SELECT TO authenticated
  USING (
    customer_id = auth.uid() OR
    auth_user_role() = 'super_admin' OR
    resort_id = auth_user_resort_id()
  );

CREATE POLICY "Customers can insert bookings; Admins can manage resort bookings"
  ON reservations FOR INSERT TO authenticated
  WITH CHECK (
    customer_id = auth.uid() OR
    auth_user_role() = 'super_admin' OR
    resort_id = auth_user_resort_id()
  );

CREATE POLICY "Staff/Admins can update resort bookings"
  ON reservations FOR UPDATE TO authenticated
  USING (auth_user_role() = 'super_admin' OR resort_id = auth_user_resort_id());

CREATE POLICY "Booking payments view permissions"
  ON booking_payments FOR SELECT TO authenticated
  USING (
    auth_user_role() = 'super_admin' OR
    resort_id = auth_user_resort_id() OR
    EXISTS (SELECT 1 FROM reservations r WHERE r.id = booking_payments.booking_id AND r.customer_id = auth.uid())
  );

CREATE POLICY "Booking payments creation permissions"
  ON booking_payments FOR INSERT TO authenticated
  WITH CHECK (
    auth_user_role() = 'super_admin' OR
    resort_id = auth_user_resort_id() OR
    EXISTS (SELECT 1 FROM reservations r WHERE r.id = booking_payments.booking_id AND r.customer_id = auth.uid())
  );

-- 7. Staff Operations Policies (Incharge scoped)
CREATE POLICY "Incharge, Admin, Super Admin can manage staff"
  ON staff_members FOR ALL TO authenticated
  USING (auth_user_role() = 'super_admin' OR (resort_id = auth_user_resort_id() AND auth_user_role() IN ('admin', 'incharge')));

CREATE POLICY "Incharge and assigned staff can manage tasks"
  ON staff_tasks FOR ALL TO authenticated
  USING (auth_user_role() = 'super_admin' OR (resort_id = auth_user_resort_id() AND auth_user_role() IN ('admin', 'incharge')));

CREATE POLICY "Incharge, Admin, Super Admin can view/manage attendance and schedules"
  ON attendance FOR ALL TO authenticated
  USING (auth_user_role() = 'super_admin' OR (resort_id = auth_user_resort_id() AND auth_user_role() IN ('admin', 'incharge')));

CREATE POLICY "Incharge, Admin, Super Admin can view/manage leave requests"
  ON leave_requests FOR ALL TO authenticated
  USING (auth_user_role() = 'super_admin' OR (resort_id = auth_user_resort_id() AND auth_user_role() IN ('admin', 'incharge')));

-- 8. Food, Maintenance, Services & Expenses Policies
CREATE POLICY "Food items viewable by all" ON food_items FOR SELECT USING (true);
CREATE POLICY "Food categories viewable by all" ON food_categories FOR SELECT USING (true);

CREATE POLICY "Incharge and Admin can manage food items and categories"
  ON food_items FOR ALL TO authenticated
  USING (auth_user_role() = 'super_admin' OR (resort_id = auth_user_resort_id() AND auth_user_role() IN ('admin', 'incharge')));

CREATE POLICY "Food orders viewable by resort staff and customer"
  ON food_orders FOR ALL TO authenticated
  USING (auth_user_role() = 'super_admin' OR resort_id = auth_user_resort_id());

CREATE POLICY "Maintenance logs and service requests manageable by Incharge/Admin"
  ON maintenance_logs FOR ALL TO authenticated
  USING (auth_user_role() = 'super_admin' OR (resort_id = auth_user_resort_id() AND auth_user_role() IN ('admin', 'incharge')));

CREATE POLICY "Expenses manageable by Accountant, Admin, Super Admin"
  ON expenses FOR ALL TO authenticated
  USING (auth_user_role() = 'super_admin' OR (resort_id = auth_user_resort_id() AND auth_user_role() IN ('admin', 'accountant')));

-- 9. Reviews Policies
CREATE POLICY "Anyone can view reviews" ON reviews FOR SELECT USING (true);
CREATE POLICY "Customers can add reviews" ON reviews FOR INSERT TO authenticated WITH CHECK (customer_id = auth.uid());

-- 10. Ledger Settlements & Audit Logs
CREATE POLICY "Super Admin and Accountant view ledger settlements"
  ON ledger_settlements FOR ALL TO authenticated
  USING (auth_user_role() = 'super_admin' OR (resort_id = auth_user_resort_id() AND auth_user_role() = 'accountant'));

CREATE POLICY "Super Admin views all audit logs; Admin views resort logs"
  ON audit_logs FOR SELECT TO authenticated
  USING (auth_user_role() = 'super_admin' OR resort_id = auth_user_resort_id());
