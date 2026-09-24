-- dashboard_summary()'s three additive in-house keys, added in
-- 0038_stay_dashboard_summary.sql.

begin;
select plan(4);

insert into public.properties (id, name, slug)
values ('aaaaaaaa-0000-0000-0000-000000000038','P38','p38');
insert into public.units (id, property_id, name, capacity_base, capacity_max)
values ('bbbbbbbb-0000-0000-0000-000000000038',
        'aaaaaaaa-0000-0000-0000-000000000038','U38', 4, 6);

-- The seeded staff role is a membership at the seed resort only; give
-- them the same role at this file's property.
insert into public.resort_members (property_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000038','10000000-0000-0000-0000-000000000003','staff');

insert into public.reservations (id, unit_id, period, kind, status, customer_id, checked_in_at)
values ('97a00000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000038',
   public.build_period('bbbbbbbb-0000-0000-0000-000000000038', current_date+1, current_date+2),
   'booking', 'checked_in', '10000000-0000-0000-0000-000000000005', now() - interval '2 days');

insert into public.reservations (id, unit_id, period, kind, status, customer_id,
    checked_in_at, checked_out_at)
values ('97a00000-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000038',
   public.build_period('bbbbbbbb-0000-0000-0000-000000000038', current_date-3, current_date-1),
   'booking', 'checked_out', '10000000-0000-0000-0000-000000000006',
   now() - interval '2 days', now());

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}';

select is(
  ((public.dashboard_summary('aaaaaaaa-0000-0000-0000-000000000038')) ->> 'currently_in_house')::int,
  1,
  'currently_in_house counts the one checked_in reservation'
);

select is(
  ((public.dashboard_summary('aaaaaaaa-0000-0000-0000-000000000038')) ->> 'checked_out_today')::int,
  1,
  'checked_out_today counts the reservation checked out just now'
);

select is(
  ((public.dashboard_summary('aaaaaaaa-0000-0000-0000-000000000038')) ->> 'checked_in_today')::int,
  0,
  'checked_in_today is zero when the only checked_in row arrived earlier than today'
);

select ok(
  (public.dashboard_summary('aaaaaaaa-0000-0000-0000-000000000038')) ? 'today_revenue'
    and (public.dashboard_summary('aaaaaaaa-0000-0000-0000-000000000038')) ? 'food_sales_today',
  'every pre-existing dashboard_summary key is still present'
);

reset role;
select * from finish();
rollback;
