// Cleanup helper for tests/platform.spec.ts's "+ Add resort" flow.
//
// That flow creates a real resort through the UI. It is scoped to an exact
// slug (never a "e2e-%" prefix match), so cleaning it up here never touches
// another spec's -- or another agent's concurrent run's -- own e2e-
// fixtures, which are built from the same shared fixtures/world.ts.
//
// Persona: platform (REQ-08 platform console). Kept as its own file, per
// the instruction to isolate extra fixture-adjacent code from
// global-setup.ts/global-teardown.ts, which other specs' agents also edit.

import { runSql } from '../fixtures/db.ts';

const lit = (value: string): string => `'${value.replace(/'/g, "''")}'`;

/**
 * Deletes exactly the resorts whose slug is in [slugs] -- and every row
 * that references them (audit_log, resort_subscriptions, resort_members,
 * and any other resort-scoped table found via the catalog, the same
 * approach fixtures/sql.ts's teardownSql uses). Safe to call with a slug
 * that doesn't exist (e.g. the test's create step never got that far).
 */
export function deleteResortsBySlug(slugs: string[]): void {
  if (slugs.length === 0) return;
  const slugList = `array[${slugs.map(lit).join(',')}]`;
  runSql(`
do $platform_data$
declare
  v_props uuid[] := array(select id from public.properties where slug = any(${slugList}));
  v_tables text[];
  v_left   int;
  v_pass   int := 0;
  t        text;
begin
  if v_props = '{}' then
    return;
  end if;

  select coalesce(array_agg(format('public.%I', c.table_name)), '{}')
    into v_tables
    from information_schema.columns c
    join information_schema.tables tb
      on tb.table_schema = c.table_schema and tb.table_name = c.table_name
   where c.table_schema = 'public'
     and c.column_name = 'property_id'
     and tb.table_type = 'BASE TABLE';

  loop
    v_pass := v_pass + 1;
    v_left := 0;
    foreach t in array v_tables loop
      begin
        execute format('delete from %s where property_id = any($1)', t) using v_props;
      exception when foreign_key_violation then
        v_left := v_left + 1;
      end;
    end loop;
    exit when v_left = 0;
    if v_pass >= 20 then
      raise exception 'platform-data cleanup: resort rows still referenced after % passes', v_pass;
    end if;
  end loop;

  delete from public.audit_log where entity_id = any(v_props);
  delete from public.properties where id = any(v_props);
end
$platform_data$;
`);
}

/**
 * The slug `create_resort` derives from a resort name
 * (0049_subscriptions.sql: lowercase, runs of non-alphanumerics collapsed
 * to one "-", leading/trailing "-" trimmed). Used to predict the slug of a
 * resort the "+ Add resort" dialog is about to create, so it can be
 * cleaned up by exact slug afterwards without re-reading it from the UI.
 */
export function slugFor(name: string): string {
  const base = name
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return base || 'resort';
}
