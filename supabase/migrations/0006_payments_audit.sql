create table public.payments (
  id             uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.reservations(id) on delete cascade,
  amount         numeric(12,2) not null check (amount > 0),
  kind           public.payment_kind not null default 'advance',
  status         public.payment_status not null default 'pending',
  gateway        text not null default 'mock',
  gateway_ref    text,
  raw            jsonb,
  created_at     timestamptz not null default now(),
  unique (gateway, gateway_ref)
);

create index payments_reservation_idx on public.payments(reservation_id);

grant select on public.payments to authenticated;
grant insert, update on public.payments to authenticated;

alter table public.payments enable row level security;

create policy payments_select on public.payments
  for select to authenticated
  using (
    public.is_staff_or_above()
    or exists (
      select 1 from public.reservations r
      where r.id = payments.reservation_id and r.customer_id = auth.uid())
  );

create policy payments_admin_write on public.payments
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create table public.audit_log (
  id        bigserial primary key,
  actor_id  uuid,
  entity    text not null,
  entity_id uuid not null,
  action    text not null,
  before    jsonb,
  after     jsonb,
  at        timestamptz not null default now()
);

create index audit_log_entity_idx on public.audit_log(entity, entity_id, at desc);

-- Read-only for staff. Rows are written by the SECURITY DEFINER trigger
-- below, running as the function owner, so no insert grant is needed.
grant select on public.audit_log to authenticated;

alter table public.audit_log enable row level security;

create policy audit_log_read on public.audit_log
  for select to authenticated using (public.is_staff_or_above());

-- One row per status transition. Phase 3 notification senders subscribe here.
create function public.record_reservation_transition()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.audit_log (actor_id, entity, entity_id, action, after)
    values (auth.uid(), 'reservation', new.id,
            'created:' || new.status::text, to_jsonb(new));
  elsif new.status is distinct from old.status then
    insert into public.audit_log
      (actor_id, entity, entity_id, action, before, after)
    values (auth.uid(), 'reservation', new.id,
            'status:' || old.status::text || '->' || new.status::text,
            to_jsonb(old), to_jsonb(new));
  end if;
  return new;
end;
$$;

create trigger reservations_audit
  after insert or update on public.reservations
  for each row execute function public.record_reservation_transition();
