begin;
select plan(3);

select has_extension('btree_gist');

select enum_has_labels(
  'public', 'reservation_status',
  array['hold','pending_payment','confirmed','cancelled']
);

select enum_has_labels(
  'public', 'user_role',
  array['customer','staff','admin','accountant','super_admin']
);

select * from finish();
rollback;
