begin;
select plan(4);

select has_table('public','properties','properties exists');
select has_table('public','units','units exists');
select has_table('public','slot_types','slot_types exists');

insert into public.properties (id, name, slug, check_in_time, check_out_time)
values ('aaaaaaaa-0000-0000-0000-000000000001','P1','p1','14:00','11:00');

-- anonymous browsing must work before signup
set local role anon;
select is(
  (select count(*)::int from public.properties),
  1,
  'anon can read active properties'
);

select * from finish();
rollback;
