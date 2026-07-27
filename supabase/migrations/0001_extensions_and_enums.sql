create extension if not exists btree_gist;
create extension if not exists pgcrypto;
create extension if not exists pg_cron;

create type public.user_role as enum
  ('customer','staff','admin','accountant','super_admin');

create type public.booking_mode as enum ('nightly','slot','both');

create type public.slot_code as enum ('day','night','full_day');

create type public.rate_kind as enum ('base','weekend','override');

create type public.reservation_kind as enum ('booking','block','ota');

create type public.reservation_status as enum
  ('hold','pending_payment','confirmed','cancelled');

create type public.payment_kind as enum ('advance','balance');

create type public.payment_status as enum
  ('pending','succeeded','failed','refunded');
