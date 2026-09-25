// `npm run fixtures:setup` / `npm run fixtures:teardown`: the same fixture
// world as a test run, by hand (e.g. to clean up after a run was killed).

import globalSetup from './global-setup.ts';
import globalTeardown from './global-teardown.ts';

const command = process.argv[2];
if (command === 'setup') {
  globalSetup();
  console.log('E2E fixtures created.');
} else if (command === 'teardown') {
  delete process.env.E2E_KEEP_FIXTURES;
  globalTeardown();
  console.log('E2E fixtures removed.');
} else {
  console.error('usage: cli.ts setup|teardown');
  process.exit(2);
}
