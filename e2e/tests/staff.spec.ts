import { expect, test, type Page } from '@playwright/test';
import { resortA } from '../fixtures/world.ts';
import { createTask, deleteAllTasks } from '../support/tasks-api.ts';
import {
  clickTab,
  currentPath,
  fillField,
  goTo,
  landingPath,
  login,
  logout,
} from '../support/index.ts';

// Staff / Incharge (Resort A). Resort A has three units: Garden Cottage
// (a confirmed booking arriving today, not checked in -- so Available),
// Lake Villa (checked in yesterday -> tomorrow -- so Occupied), and Tree
// House (no booking -- Available). Only one staff member, Sam StaffA, so
// "send housekeeping" dispatches to Sam himself; he is both sender and
// assignee, which is exactly what the fixture world provides.
//
// Every test that changes a room's state or dispatches housekeeping resets
// it before finishing, so the suite leaves Resort A's rooms as it found
// them and each test stays independent of run order.

const staff = resortA.team.staff; // Sam StaffA
const treeHouse = resortA.units[2];
const gardenCottage = resortA.units[0];
const lakeVilla = resortA.units[1];

/** Task rows on /admin/tasks: one group per task, "<title> <assignee> <status>". */
const taskRow = (page: Page, title: string) =>
  page.getByRole('group', { name: new RegExp(`^${title} `) });

test.describe('Staff / Incharge (Resort A)', () => {
  // Tests here create tasks; remove them so each test starts with none at
  // Resort A. (The fixture teardown would delete any left over too.)
  test.afterAll(async () => {
    await deleteAllTasks(resortA.team.admin, resortA.id);
  });

  test('lands on /staff Today with the staff bottom bar', async ({ page }) => {
    expect(await login(page, staff)).toBe(landingPath.staff);
    await expect(page.getByRole('heading', { name: 'Today' })).toBeVisible();

    await clickTab(page, 'Today');
    await expect(page.getByRole('tab', { name: 'Rooms', exact: true })).toBeVisible();
    await expect(page.getByRole('tab', { name: 'Dashboard', exact: true })).toBeVisible();
    await expect(page.getByRole('tab', { name: 'Reports', exact: true })).toBeVisible();

    await logout(page);
  });

  test('room grid shows tiles and summary counts', async ({ page }) => {
    await login(page, staff);
    await goTo(page, '/staff/rooms');
    await expect(page.getByRole('heading', { name: 'Rooms' })).toBeVisible();

    // Summary chips: 2 Available (Garden Cottage, Tree House), 1 Occupied
    // (Lake Villa), 0 Cleaning, 0 Maintenance.
    await expect(page.getByRole('checkbox', { name: 'Available (2)', exact: true })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'Occupied (1)', exact: true })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'Cleaning (0)', exact: true })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'Maintenance (0)', exact: true })).toBeVisible();

    // One tile per unit, named by the room.
    await expect(page.getByRole('button', { name: new RegExp(`^${gardenCottage.name}`) })).toBeVisible();
    await expect(page.getByRole('button', { name: new RegExp(`^${lakeVilla.name}`) })).toBeVisible();
    await expect(page.getByRole('button', { name: new RegExp(`^${treeHouse.name}`) })).toBeVisible();

    await logout(page);
  });

  test('setting a room to Maintenance requires a reason', async ({ page }) => {
    await login(page, staff);
    await goTo(page, '/staff/rooms');

    await page.getByRole('button', { name: new RegExp(`^${treeHouse.name}`) }).click();
    // The sheet's ListTile subtitle ("Clean and ready" / "Out of order, with
    // a reason") joins the title in the accessible name.
    await page.getByRole('button', { name: /^Maintenance/ }).click();

    // Submitting the reason dialog with nothing entered is refused.
    await page.getByRole('button', { name: 'Mark Maintenance', exact: true }).click();
    await expect(page.getByText('Enter a reason', { exact: true })).toBeVisible();

    const reason = 'AC not cooling';
    await fillField(page.getByLabel('Reason'), reason);
    await page.getByRole('button', { name: 'Mark Maintenance', exact: true }).click();
    // Flutter's SnackBar text is announced via an aria-live region as well
    // as shown in its own span, so two elements carry this text; `.last()`
    // is the visible snackbar span.
    await expect(page.getByText(`${treeHouse.name} updated`, { exact: true }).last()).toBeVisible();

    // The tile now shows Maintenance with the reason, and the summary
    // chips moved one room from Available to Maintenance.
    await expect(
      page.getByRole('button', { name: new RegExp(`^${treeHouse.name}.*Maintenance.*${reason}`, 's') }),
    ).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'Available (1)', exact: true })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'Maintenance (1)', exact: true })).toBeVisible();

    // Clean up: put Tree House back to Available so the fixture world is
    // unchanged for the next run.
    await page.getByRole('button', { name: new RegExp(`^${treeHouse.name}`) }).click();
    await page.getByRole('button', { name: /^Available/ }).click();
    await expect(page.getByText(`${treeHouse.name} updated`, { exact: true }).last()).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'Available (2)', exact: true })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'Maintenance (0)', exact: true })).toBeVisible();

    await logout(page);
  });

  test("sending housekeeping shows up in the assignee's Assigned Work and clears the room on completion", async ({
    page,
  }) => {
    await login(page, staff);
    await goTo(page, '/staff/rooms');

    // Send housekeeping to Garden Cottage; Sam StaffA is the only
    // dispatchable staff member at Resort A, so he dispatches to himself.
    await page.getByRole('button', { name: new RegExp(`^${gardenCottage.name}`) }).click();
    await page.getByRole('button', { name: 'Send housekeeping', exact: true }).click();

    await expect(page.getByText(`Send housekeeping to ${gardenCottage.name}`, { exact: true })).toBeVisible();
    // The dropdown trigger's accessible name is just its label until a
    // choice is made; selecting opens a menu of `menuitem`s (not options).
    await page.getByRole('button', { name: 'Housekeeper', exact: true }).click();
    await page.getByRole('menuitem', { name: staff.fullName, exact: true }).click();
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expect(
      page.getByText(`Housekeeping sent to ${gardenCottage.name}`, { exact: true }).last(),
    ).toBeVisible();

    // Dispatching sets the room to "needs cleaning" -- its derived status
    // becomes Cleaning (not Available) while the task is open, alongside
    // the open-task line on the tile.
    await expect(
      page.getByRole('button', { name: new RegExp(`^${gardenCottage.name}.*Cleaning.*Housekeeping:.*Sam`, 's') }),
    ).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'Available (1)', exact: true })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'Cleaning (1)', exact: true })).toBeVisible();

    // As the assignee, Sam sees it in Assigned Work. The card's title, room
    // line and status dropdown merge into one accessible node (there is no
    // other focusable element inside the card to give them a boundary).
    await goTo(page, '/staff/tasks');
    await expect(page.getByRole('heading', { name: 'Assigned Work' })).toBeVisible();
    const taskCard = page.getByRole('button', {
      name: new RegExp(`^Clean ${gardenCottage.name}.*Room: ${gardenCottage.name}`, 's'),
    });
    await expect(taskCard).toBeVisible();

    // Mark it done via the status dropdown on that task's card.
    await taskCard.click();
    await page.getByRole('menuitem', { name: 'Done', exact: true }).click();

    // The room returns to Available server-side (tasks_housekeeping_done).
    await goTo(page, '/staff/rooms');
    await expect(page.getByRole('button', { name: new RegExp(`^${gardenCottage.name}.*Available`, 's') })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'Available (2)', exact: true })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'Cleaning (0)', exact: true })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'Occupied (1)', exact: true })).toBeVisible();
    await logout(page);

    // Delete the finished task, as the admin, so no row is left pointing at
    // the unit (afterAll repeats this in case the test failed before here).
    expect(await deleteAllTasks(resortA.team.admin, resortA.id)).toBe(1);
  });

  test('staff cannot reach /owner', async ({ page }) => {
    await login(page, staff);

    // NotFoundScreen is a bare `Text('Page not found')` with no semantics
    // role or aria-label at all, so the generic waitForFlutter (which waits
    // for a role/aria-label node) never resolves there -- check the router
    // path and the page text directly instead of using goTo/expectAt.
    await page.evaluate(() => {
      window.location.hash = '/owner';
    });
    await expect.poll(() => currentPath(page), { timeout: 15_000 }).toBe('/404');
    await expect(page.getByText('Page not found', { exact: true })).toBeVisible();

    // Back to a normal screen (with the app bar) to sign out through the UI.
    await goTo(page, '/staff');
    await logout(page);
  });

  // BUG lib/features/admin/tasks_screen.dart _delete: the confirm dialog's
  // buttons pop `Navigator.of(context)` with the *screen's* context. The
  // dialog is on the root navigator, but /admin/tasks lives in the router's
  // ShellRoute, so "Delete" pops the Tasks page off the shell navigator
  // instead of closing the dialog: the screen goes blank and the task is
  // never deleted. Remove test.fail once fixed.
  test.fail('an admin can delete a task from /admin/tasks', async ({ page }) => {
    const title = 'E2E delete me';
    await createTask(resortA.team.admin, resortA.id, staff, title);
    try {
      await login(page, resortA.team.admin);
      await goTo(page, '/admin/tasks');
      await taskRow(page, title).getByRole('button', { name: 'Show menu' }).click();
      await page.getByRole('menuitem', { name: 'Delete', exact: true }).click();
      await page.getByRole('button', { name: 'Delete', exact: true }).click();
      await expect(page.getByRole('heading', { name: 'Tasks' })).toBeVisible({ timeout: 5_000 });
      await expect(taskRow(page, title)).toHaveCount(0, { timeout: 5_000 });
    } finally {
      await deleteAllTasks(resortA.team.admin, resortA.id);
    }
  });
});
