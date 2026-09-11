-- Business expense tracking -- financial data, so read access is tighter
-- than the food/activity sales log: admin, accountant, and super_admin
-- only, never plain staff. This mirrors why the `accountant` role exists at
-- all (README: "the accountant role exists specifically to read
-- financials"). See
-- docs/superpowers/specs/2026-08-31-owner-super-admin-flow-design.md.
create table public.expenses (
  id             uuid primary key default gen_random_uuid(),
  property_id    uuid not null references public.properties(id) on delete cascade,
  expense_date   date not null default (now() at time zone 'Asia/Kolkata')::date,
  category       text not null,
  description    text not null default '',
  amount         numeric(12,2) not null check (amount >= 0),
  paid_to        text,
  payment_method text,
  recorded_by    uuid not null default auth.uid() references public.profiles(id),
  created_at     timestamptz not null default now()
);

create index expenses_property_date_idx on public.expenses(property_id, expense_date);

grant select, insert, update, delete on public.expenses to authenticated;

alter table public.expenses enable row level security;

create policy expenses_read on public.expenses
  for select to authenticated
  using (public.current_role() in ('admin', 'accountant', 'super_admin'));

create policy expenses_admin_write on public.expenses
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Same shape and gating as `report_food_sales` -- staff-or-above at the
-- function-body level is intentionally NOT used here, since plain `staff`
-- must not see expenses; the inline role check matches `expenses_read`'s
-- own policy exactly.
create function public.report_expenses(
  p_from        date,
  p_to          date,
  p_property_id uuid default null
) returns table (
  day    date,
  category text,
  total  numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if public.current_role() not in ('admin', 'accountant', 'super_admin') then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  return query
  select
    e.expense_date,
    e.category,
    sum(e.amount)
  from public.expenses e
  where e.expense_date between p_from and p_to
    and (p_property_id is null or e.property_id = p_property_id)
  group by 1, 2
  order by 1, 2;
end;
$$;

grant execute on function public.report_expenses to authenticated;
revoke execute on function public.report_expenses from public;
revoke execute on function public.report_expenses from anon;
