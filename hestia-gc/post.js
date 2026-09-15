// Runs after the rest of the job's own steps, once main.js decided (via
// scripts/setup-hestia-gc.sh) that this job owns the hestia-gc concurrency
// group. HESTIA_BIN is exported into the job's environment by the "Setup
// Nix Cache (hestia)" step earlier in this action.
//
// gc failures are reported but don't fail the job: this runs inside a
// build/deploy job rather than a dedicated gc job, and a cleanup hiccup
// shouldn't turn an otherwise-successful build red. It gets another chance
// on the next run that owns the group.
const { execFileSync } = require('child_process');

if (process.env['STATE_should-run'] !== 'true') {
  process.exit(0);
}

const hestiaBin = process.env.HESTIA_BIN;
if (!hestiaBin) {
  console.log(
    '::warning::hestia-gc: HESTIA_BIN is not set (the hestia cache step may have been skipped or failed); skipping gc'
  );
  process.exit(0);
}

try {
  execFileSync(hestiaBin, ['gc'], { stdio: 'inherit' });
} catch (err) {
  console.log(`::warning::hestia-gc: gc failed, will retry on the next run that owns it: ${err.message}`);
}
