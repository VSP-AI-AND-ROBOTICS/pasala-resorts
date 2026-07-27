create table public.properties (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  slug           text not null unique,
  description    text,
  address        text,
  lat            double precision,
  lng            double precision,
  images         text[] not null default '{}',
  amenities      text[] not null default '{}',
  check_in_time  time not null default '14:00',
  check_out_time time not null default '11:00',
  timezone       text not null default 'Asia/Kolkata',
  is_active      boolean not null default true,
  created_at     timestamptz not null default now()
);

create table public.units (
  id             uuid primary key default gen_random_uuid(),
  property_id    uuid not null references public.properties(id) on delete cascade,
  name           text not null,
  description    text,
  images         text[] not null default '{}',
  capacity_base  int not null check (capacity_base > 0),
  capacity_max   int not null check (capacity_max > 0),
  booking_mode   public.booking_mode not null default 'nightly',
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  constraint units_capacity_order check (capacity_max >= capacity_base),
  unique (property_id, name)
);

create index units_property_idx on public.units(property_id);

create table public.slot_types (
  id          uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  code        public.slot_code not null,
  start_time  time not null,
  end_time    time not null,
  unique (property_id, code)
);

-- Table grants are required in addition to RLS. This project's Supabase
-- config does not auto-expose new tables to the Data API roles, so a table
-- with policies but no grant fails closed at the privilege layer with 42501
-- before RLS is ever evaluated. Every table in this plan needs its grant.
grant select on public.properties, public.units, public.slot_types
  to anon, authenticated;
grant insert, update, delete on public.properties, public.units,
  public.slot_types to authenticated;

alter table public.properties enable row level security;
alter table public.units      enable row level security;
alter table public.slot_types enable row level security;

create policy properties_read on public.properties
  for select to anon, authenticated
  using (is_active or public.is_staff_or_above());

create policy properties_write on public.properties
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy units_read on public.units
  for select to anon, authenticated
  using (is_active or public.is_staff_or_above());

create policy units_write on public.units
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy slot_types_read on public.slot_types
  for select to anon, authenticated using (true);

create policy slot_types_write on public.slot_types
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
