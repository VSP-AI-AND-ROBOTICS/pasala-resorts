-- Extends dashboard_summary() with in-house occupancy figures for the
-- Guest Stay Experience feature, purely additively -- every existing key
-- keeps its exact old value and meaning, matching 0030's own convention.
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
      - v_expenses_month,
    'checked_in_today', (
      select count(*)::int from public.reservations
      where kind = 'booking' and checked_in_at::date = v_today),
    'checked_out_today', (
      select count(*)::int from public.reservations
      where kind = 'booking' and checked_out_at::date = v_today),
    'currently_in_house', (
      select count(*)::int from public.reservations
      where kind = 'booking' and status = 'checked_in')
  );
end;
$$;

revoke execute on function public.dashboard_summary from public;
revoke execute on function public.dashboard_summary from anon;
