-- Extends dashboard_summary() with the two new business ledgers, purely
-- additively -- every existing key keeps its exact old value and meaning,
-- and DashboardSummary.fromJson (lib/data/models/report.dart) already
-- null-coalesces any key it doesn't recognise to 0, so `/admin/dashboard`
-- needs no change to keep working unmodified. See
-- docs/superpowers/specs/2026-08-31-owner-super-admin-flow-design.md.
create or replace function public.dashboard_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_month_start date := date_trunc('month', v_today)::date;
  v_food_sales_today numeric;
  v_expenses_month numeric;
begin
  perform public.assert_staff();

  select coalesce(sum(gross), 0) into v_food_sales_today
  from public.report_food_sales(v_today, v_today);

  -- Expenses are admin/accountant/super_admin-only data (see
  -- 0027_expenses.sql) -- `dashboard_summary` is staff-or-above, so a plain
  -- staff member calling it must not trip `report_expenses`'s own tighter
  -- gate. Queried directly against the table instead, under this
  -- function's SECURITY DEFINER privileges, exactly like every other
  -- figure here -- the dashboard as a whole is already staff-gated by
  -- `assert_staff()` above, and net profit is deliberately shown to
  -- everyone who can see revenue, the same audience `today_revenue`/
  -- `month_revenue` already reach.
  select coalesce(sum(amount), 0) into v_expenses_month
  from public.expenses
  where expense_date between v_month_start and v_today;

  return jsonb_build_object(
    'today_revenue', coalesce((
      select sum(net) from public.report_revenue(v_today, v_today)), 0),
    'month_revenue', coalesce((
      select sum(net) from public.report_revenue(v_month_start, v_today)), 0),
    'occupancy_pct', coalesce((
      select round(avg(occupancy_pct), 1)
      from public.report_occupancy(v_month_start, v_today)), 0),
    'upcoming_arrivals', (
      select count(*)::int from public.reservations
      where kind = 'booking' and status = 'confirmed'
        and lower(period) >= now()
        and lower(period) < now() + interval '7 days'),
    'cancellations_this_month', (
      select count(*)::int from public.reservations
      where kind = 'booking' and status = 'cancelled'
        and cancelled_at >= v_month_start),
    'active_holds', (
      select count(*)::int from public.reservations
      where status = 'hold' and hold_expires_at > now()),
    'food_sales_today', v_food_sales_today,
    'expenses_month_total', v_expenses_month,
    'net_profit_month', coalesce((
      select sum(net) from public.report_revenue(v_month_start, v_today)), 0)
      - v_expenses_month
  );
end;
$$;

-- `create or replace` does not reset this function's ACL -- it was already
-- revoked from public/anon in 0015_reports.sql; repeated here for the same
-- belt-and-suspenders reason `cancel_booking` repeats its revoke in 0013/0016.
revoke execute on function public.dashboard_summary from public;
revoke execute on function public.dashboard_summary from anon;
