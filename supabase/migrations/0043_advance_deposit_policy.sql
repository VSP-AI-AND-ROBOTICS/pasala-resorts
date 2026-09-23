-- 0043_advance_deposit_policy.sql
-- Provides an RPC `compute_deposit_breakdown` to calculate standard 35% advance
-- deposits and remaining check-in balances, fully compatible with 0014's
-- `properties.advance_pct` and `confirm_booking` payment range verification.

comment on column public.properties.advance_pct is
  'Minimum percentage of quoted total required at booking time (e.g. 35%). Remaining balance is collected at check-in.';

create or replace function public.compute_deposit_breakdown(
  p_property_id uuid,
  p_total       numeric
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_pct numeric;
  v_advance numeric;
  v_due numeric;
begin
  select coalesce(advance_pct, 35) into v_pct
  from public.properties
  where id = p_property_id;

  if not found or v_pct is null then
    v_pct := 35;
  end if;

  v_advance := round(p_total * v_pct / 100.0, 2);
  v_due := round(p_total - v_advance, 2);

  return jsonb_build_object(
    'advance_pct', v_pct,
    'advance_amount', v_advance,
    'due_at_checkin', v_due,
    'total', p_total
  );
end;
$$;

grant execute on function public.compute_deposit_breakdown to authenticated;
grant execute on function public.compute_deposit_breakdown to anon;
