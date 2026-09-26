// Outbox (P7), staff and owner: messages the sender handled without a
// provider key show under "Dry run" with the reason, staff can read them,
// and an owner can send one again, which queues it afresh.
//
// Own fixture (support/kit.ts): a resort with its owner and a staff
// member, and a guest's confirmed booking, whose insert queues the
// booking's messages the way every booking does (0017's trigger: email
// confirmation and payment receipt pending; SMS and WhatsApp skipped, the
// guest has no phone).
//
// The dry run itself: the outbox-dispatch function claims every due
// message of every resort (claim_outbox_batch), so running it here would
// also handle the real resort's queue. Instead this spec does, for its own
// resort's rows only, exactly what the function does without RESEND_API_KEY:
// the claim's attempt bookkeeping, then complete_outbox_message(...,
// 'dry_run', ...) -- the same database function the dispatcher calls.

import { expect, test, type Page } from '@playwright/test';
import { runSql } from '../fixtures/db.ts';
import { goTo, login } from '../support/index.ts';
import {
  TODAY,
  createFixtures,
  kitUser,
  lit,
  removeFixtures,
  sqlValue,
  type KitResort,
} from '../support/kit.ts';
import { expectLine, expectNoLine } from '../support/screen.ts';

const owner = kitUser(0xd0, 1, 'owner.outbox', 'Omar OutboxOwner');
const staff = kitUser(0xd0, 2, 'staff.outbox', 'Stella OutboxStaff');
const guest = kitUser(0xd0, 3, 'guest.outbox', 'Greta OutboxGuest');

const unitId = 'e2e5d000-0000-4000-8000-000000000011';
const bookingId = 'e2e5d000-0000-4000-8000-000000000021';
const resort: KitResort = {
  id: 'e2e5d000-0000-4000-8000-000000000001',
  slug: 'e2e-outbox',
  name: 'E2E Outbox Resort',
  units: [{ id: unitId, name: 'Outbox Villa', nightlyRate: 5000 }],
  team: { owner, staff },
};

const DRY_RUN_REASON = 'RESEND_API_KEY is not set';

test.describe.configure({ mode: 'serial' });

test.beforeAll(() => {
  removeFixtures([resort.slug], [owner, staff, guest]);
  createFixtures([owner, staff, guest], [resort]);
  const period = `public.build_period(${lit(unitId)}, ${TODAY} + 20, ${TODAY} + 22)`;
  runSql(`
begin;
insert into public.reservations
  (id, unit_id, period, kind, status, customer_id, guests, quote, source, created_by)
values
  (${lit(bookingId)}, ${lit(unitId)}, ${period}, 'booking', 'confirmed', ${lit(guest.id)}, 2,
   public.get_quote(${lit(unitId)}, ${period}, 2), 'app', ${lit(guest.id)});

-- The dispatcher's dry run, for this resort's due email only.
update public.outbox
   set attempts = attempts + 1, last_attempt_at = now(), next_attempt_at = now() + interval '5 minutes'
 where property_id = ${lit(resort.id)} and status = 'pending' and channel = 'email';
select public.complete_outbox_message(id, 'dry_run', ${lit(DRY_RUN_REASON)})
  from public.outbox
 where property_id = ${lit(resort.id)} and status = 'pending' and channel = 'email';
commit;
`);
});
test.afterAll(() => removeFixtures([resort.slug], [owner, staff, guest]));

async function openOutbox(page: Page): Promise<void> {
  await goTo(page, '/admin/outbox');
  await expect(page.getByRole('heading', { name: 'Outbox' })).toBeVisible();
}

test('staff see the dry-run messages with the reason, but cannot send them again', async ({ page }) => {
  await login(page, staff);
  await openOutbox(page);

  await expectLine(page, 'Dry run (2)');
  await expectLine(page, 'Skipped (2)');
  const row = await expectLine(page, `${guest.email} Email · booking_confirmation`);
  expect(row).toContain(DRY_RUN_REASON);
  await expectLine(page, `${guest.email} Email · payment_success`);
  await expect(page.getByRole('button', { name: 'Send again' })).toHaveCount(0);
});

test('the owner sends a dry-run message again, and it is queued afresh', async ({ page }) => {
  await login(page, owner);
  await openOutbox(page);

  await expectLine(page, 'Dry run (2)');
  await expect(page.getByRole('button', { name: 'Send again' })).toHaveCount(2);
  await page.getByRole('button', { name: 'Send again' }).first().click();

  await expectLine(page, 'Queued to send again.');
  await expectLine(page, 'Pending (1)');
  await expectLine(page, 'Dry run (1)');
  await expectNoLine(page, 'Dry run (2)');
  expect(
    sqlValue(`select count(*) from public.outbox
               where property_id = '${resort.id}' and status = 'pending' and attempts = 0`),
  ).toBe('1');
});
