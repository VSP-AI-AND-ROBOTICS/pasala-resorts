-- Post-stay reviews. One review per reservation (enforced by the unique
-- constraint below, not just app-level convention), insertable only by the
-- reservation's own customer, and only once the stay has reached
-- `checked_out` -- a review is a retrospective on a completed stay, not a
-- pre-checkout survey. No update/delete policy: a submitted review is
-- immutable feedback, matching how reviews behave on every consumer
-- platform this app's users already know.
create table public.reviews (
  id                  uuid primary key default gen_random_uuid(),
  reservation_id      uuid not null unique references public.reservations(id) on delete cascade,
  customer_id         uuid not null references public.profiles(id),
  farmhouse_rating    int not null check (farmhouse_rating between 1 and 5),
  cleanliness_rating  int not null check (cleanliness_rating between 1 and 5),
  food_rating         int not null check (food_rating between 1 and 5),
  service_rating      int not null check (service_rating between 1 and 5),
  activities_rating   int not null check (activities_rating between 1 and 5),
  overall_rating      int not null check (overall_rating between 1 and 5),
  feedback            text not null default '',
  created_at          timestamptz not null default now()
);

grant select, insert on public.reviews to authenticated;

alter table public.reviews enable row level security;

-- Readable by staff-or-above (the Reports/owner side of the app) and the
-- reviewing customer themselves; there is no business need for one
-- customer to read another's review.
create policy reviews_read on public.reviews
  for select to authenticated
  using (public.is_staff_or_above() or customer_id = auth.uid());

create policy reviews_insert on public.reviews
  for insert to authenticated
  with check (
    customer_id = auth.uid()
    and exists (
      select 1 from public.reservations r
      where r.id = reservation_id
        and r.customer_id = auth.uid()
        and r.status = 'checked_out'
    )
  );
