-- tasks_enforce_write let only a signed-in owner/admin of the task's
-- resort delete a task or change its unit_id. That also refused:
--  * any delete or update with no end-user JWT (auth.uid() is null):
--    migrations, the service role and SQL tooling, even as postgres;
--  * the `on delete set null` of tasks.unit_id (0047), so a unit or a
--    resort with housekeeping history could not be deleted that way.
--
-- Copied from 0047 with two additions, checked before every end-user
-- rule (which are unchanged):
--  * no auth.uid(): allowed, and an update is stamped the way an admin's
--    is (updated_at, started_at, completed_at);
--  * pg_trigger_depth() > 1 and the only change is unit_id becoming null:
--    allowed. That is the foreign key's own set-null, fired from its
--    trigger when a unit is deleted -- not a caller editing the task. A
--    direct update runs at depth 1, so an assignee still cannot unlink a
--    task.
create or replace function public.tasks_enforce_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin boolean := public.has_resort_role(old.property_id, true, 'owner','admin');
  v_room_writer boolean := old.kind = 'housekeeping'
    and public.has_resort_role(old.property_id, true, 'owner','admin','staff');
  v_no_caller boolean := auth.uid() is null;
begin
  if TG_OP = 'DELETE' then
    if not v_admin and not v_no_caller then
      raise sqlstate '42501' using
        message = 'permission denied for table tasks',
        hint = 'only an administrator can delete a task';
    end if;
    return old;
  end if;

  if pg_trigger_depth() > 1
      and old.unit_id is not null and new.unit_id is null
      and (to_jsonb(new) - 'unit_id') = (to_jsonb(old) - 'unit_id') then
    return new;
  end if;

  if v_no_caller
      or (v_admin and public.has_resort_role(new.property_id, true, 'owner','admin')) then
    new.updated_at := clock_timestamp();
    if new.status = 'in_progress' and old.started_at is null then
      new.started_at := clock_timestamp();
    end if;
    if new.status = 'done' and old.completed_at is null then
      new.completed_at := clock_timestamp();
    end if;
    return new;
  end if;

  if new.assignee_id <> old.assignee_id then
    raise sqlstate '42501' using
      message = 'permission denied for table tasks',
      hint = 'only an administrator can reassign a task';
  end if;

  if new.id is distinct from old.id
      or new.title is distinct from old.title
      or new.description is distinct from old.description
      or new.created_by is distinct from old.created_by
      or new.created_at is distinct from old.created_at
      or new.property_id is distinct from old.property_id
      or new.kind is distinct from old.kind
      or new.unit_id is distinct from old.unit_id
      or new.started_at is distinct from old.started_at
      or new.completed_at is distinct from old.completed_at then
    raise sqlstate '42501' using
      message = 'permission denied for table tasks',
      hint = 'only an administrator can edit a task''s details';
  end if;

  if old.assignee_id <> auth.uid() and not v_room_writer then
    raise sqlstate '42501' using
      message = 'permission denied for table tasks',
      hint = 'you can only update the status of your own tasks';
  end if;

  new.updated_at := clock_timestamp();
  if new.status = 'in_progress' and old.started_at is null then
    new.started_at := clock_timestamp();
  end if;
  if new.status = 'done' and old.completed_at is null then
    new.completed_at := clock_timestamp();
  end if;
  return new;
end;
$$;
