-- Food and on-site activity sales -- a business ledger the app has never
-- tracked. Front-desk staff log a sale at the counter; only an admin may
-- correct or remove one. See
-- docs/superpowers/specs/2026-08-31-owner-super-admin-flow-design.md.
--
-- Deliberately NOT modelled: a menu/catalog of sellable items (this is a
-- free-text log, not a POS), per-item tax, or multi-currency -- all out of
-- scope for this slice.
create type public.sale_category as enum ('food', 'activity');

create table public.food_activity_sales (
  id             uuid primary key default gen_random_uuid(),
  property_id    uuid not null references public.properties(id) on delete cascade,
  sale_date      date not null default (now() at time zone 'Asia/Kolkata')::date,
  category       public.sale_category not null,
  item_name      text not null,
  quantity       int not null default 1 check (quantity > 0),
  unit_price     numeric(10,2) not null check (unit_price >= 0),
  amount         numeric(12,2) not null check (amount >= 0),
  payment_method text,
  notes          text,
  recorded_by    uuid not null default auth.uid() references public.profiles(id),
  created_at     timestamptz not null default now()
);

create index food_activity_sales_property_date_idx
  on public.food_activity_sales(property_id, sale_date);

grant select, insert, update, delete on public.food_activity_sales to authenticated;

alter table public.food_activity_sales enable row level security;

-- Front-desk staff log and see the sales log; only an admin may correct or
-- remove an entry once recorded.
create policy food_activity_sales_read on public.food_activity_sales
  for select to authenticated
  using (public.is_staff_or_above());

create policy food_activity_sales_insert on public.food_activity_sales
  for insert to authenticated
  with check (public.is_staff_or_above());

create policy food_activity_sales_admin_write on public.food_activity_sales
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy food_activity_sales_admin_delete on public.food_activity_sales
  for delete to authenticated
  using (public.is_admin());

-- Per-day, per-category totals over a date range, mirroring
-- `report_revenue`'s property-timezone-safe date handling (0015_reports.sql)
-- even though `sale_date` is already a plain date -- consistent with every
-- other report RPC, and future-proof if this ever gains a timestamp.
create function public.report_food_sales(
  p_from        date,
  p_to          date,
  p_property_id uuid default null
) returns table (
  day         date,
  category    public.sale_category,
  items_sold  int,
  gross       numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_staff();

  return query
  select
    s.sale_date,
    s.category,
    sum(s.quantity)::int,
    sum(s.amount)
  from public.food_activity_sales s
  where s.sale_date between p_from and p_to
    and (p_property_id is null or s.property_id = p_property_id)
  group by 1, 2
  order by 1, 2;
end;
$$;

grant execute on function public.report_food_sales to authenticated;
revoke execute on function public.report_food_sales from public;
revoke execute on function public.report_food_sales from anon;
