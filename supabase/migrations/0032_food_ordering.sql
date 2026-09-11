-- Food ordering during a stay. `food_categories`/`food_items` are a plain
-- admin-managed catalog -- browsable by anyone signed in, not gated on
-- having an active stay, since a menu carries no sensitive information.
-- `food_orders`/`food_order_items` snapshot the item name and price at
-- order time (never re-priced later if the menu changes afterward), the
-- same "server prices, client never does" principle `get_quote` already
-- established -- `place_food_order` below is the only way a row is ever
-- created; there is no INSERT grant to `authenticated` on either table.
create type public.food_order_status as enum
  ('placed', 'accepted', 'preparing', 'ready', 'delivered', 'cancelled');

create table public.food_categories (
  id          uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  name        text not null,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);

create table public.food_items (
  id            uuid primary key default gen_random_uuid(),
  category_id   uuid not null references public.food_categories(id) on delete cascade,
  name          text not null,
  description   text,
  price         numeric(10,2) not null check (price >= 0),
  is_available  boolean not null default true,
  created_at    timestamptz not null default now()
);

create index food_items_category_idx on public.food_items(category_id);

grant select on public.food_categories, public.food_items to authenticated;
grant insert, update, delete on public.food_categories, public.food_items to authenticated;

alter table public.food_categories enable row level security;
alter table public.food_items enable row level security;

create policy food_categories_read on public.food_categories
  for select to authenticated using (true);
create policy food_categories_admin_write on public.food_categories
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy food_items_read on public.food_items
  for select to authenticated using (true);
create policy food_items_admin_write on public.food_items
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create table public.food_orders (
  id             uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.reservations(id) on delete cascade,
  status         public.food_order_status not null default 'placed',
  total          numeric(12,2) not null check (total >= 0),
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table public.food_order_items (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.food_orders(id) on delete cascade,
  food_item_id uuid not null references public.food_items(id),
  item_name   text not null,
  unit_price  numeric(10,2) not null check (unit_price >= 0),
  quantity    int not null check (quantity > 0),
  line_total  numeric(12,2) not null check (line_total >= 0)
);

create index food_orders_reservation_idx on public.food_orders(reservation_id);
create index food_order_items_order_idx on public.food_order_items(order_id);

-- Read-only to clients: the owning customer, or staff-or-above (kitchen).
-- No INSERT grant at all -- `place_food_order` (security definer) is the
-- only writer of a new order. Status changes (kitchen fulfilment) go
-- through a plain UPDATE, gated by `food_orders_admin_write` below.
grant select, update on public.food_orders to authenticated;
grant select on public.food_order_items to authenticated;

alter table public.food_orders enable row level security;
alter table public.food_order_items enable row level security;

create policy food_orders_read on public.food_orders
  for select to authenticated
  using (
    public.is_staff_or_above()
    or exists (
      select 1 from public.reservations r
      where r.id = reservation_id and r.customer_id = auth.uid()
    )
  );

-- Kitchen/front-desk fulfilment -- staff-or-above, not admin-only, since
-- kitchen staff need to move an order through its lifecycle day to day.
create policy food_orders_admin_write on public.food_orders
  for update to authenticated
  using (public.is_staff_or_above()) with check (public.is_staff_or_above());

create policy food_order_items_read on public.food_order_items
  for select to authenticated
  using (
    public.is_staff_or_above()
    or exists (
      select 1 from public.food_orders o
      join public.reservations r on r.id = o.reservation_id
      where o.id = order_id and r.customer_id = auth.uid()
    )
  );

-- `p_items` is `[{"food_item_id": uuid, "quantity": int}, ...]`. Every
-- price comes from `food_items.price` at the moment of the call -- the
-- client's own displayed price is never trusted, same reasoning as
-- `get_quote` pricing every rate-rule line server-side.
--
-- Gated on the reservation being `confirmed` or `checked_in` -- a
-- customer may start adding food as soon as their stay is paid for
-- (before arrival counts as "Add Extra Services"), through checked-in.
-- This is a deliberate, documented departure from folding food into the
-- booking's own upfront total: see this repo's plan/spec docs for why
-- `get_quote`/`confirm_booking` are never touched by this feature --
-- everything ordered here settles at checkout instead (0037's
-- `checkout_booking`).
create function public.place_food_order(
  p_reservation_id uuid,
  p_items          jsonb,
  p_notes          text default null
) returns public.food_orders
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_res   public.reservations;
  v_item  jsonb;
  v_food  public.food_items;
  v_qty   int;
  v_order public.food_orders;
  v_total numeric(12,2) := 0;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'P0008';
  end if;

  select * into v_res from public.reservations where id = p_reservation_id;
  if not found or v_res.customer_id is distinct from v_uid then
    raise exception 'not permitted' using errcode = 'P0008';
  end if;

  if v_res.status not in ('confirmed', 'checked_in') then
    raise exception 'this stay is not open for ordering' using errcode = 'P0009';
  end if;

  if jsonb_array_length(p_items) = 0 then
    raise exception 'an order needs at least one item' using errcode = 'P0003';
  end if;

  insert into public.food_orders (reservation_id, status, total, notes)
  values (p_reservation_id, 'placed', 0, p_notes)
  returning * into v_order;

  for v_item in select jsonb_array_elements(p_items) loop
    select * into v_food from public.food_items
    where id = (v_item ->> 'food_item_id')::uuid and is_available;
    if not found then
      raise exception 'menu item % is not available', v_item ->> 'food_item_id'
        using errcode = 'P0002';
    end if;

    v_qty := (v_item ->> 'quantity')::int;
    if v_qty is null or v_qty <= 0 then
      raise exception 'quantity must be positive' using errcode = 'P0003';
    end if;

    insert into public.food_order_items
      (order_id, food_item_id, item_name, unit_price, quantity, line_total)
    values
      (v_order.id, v_food.id, v_food.name, v_food.price, v_qty, v_food.price * v_qty);

    v_total := v_total + v_food.price * v_qty;
  end loop;

  update public.food_orders set total = v_total where id = v_order.id
  returning * into v_order;

  return v_order;
end;
$$;

grant execute on function public.place_food_order(uuid, jsonb, text) to authenticated;
revoke execute on function public.place_food_order(uuid, jsonb, text) from public;
revoke execute on function public.place_food_order(uuid, jsonb, text) from anon;

-- No demo menu is seeded here: migrations run before seed.sql during
-- `supabase db reset`, and the one demo property doesn't exist yet at this
-- point -- see seed.sql for the starter menu.
