// Persists the should-run decision (computed by scripts/setup-hestia-gc.sh
// and passed in as an input) as job state, so post.js can read it back once
// the rest of the job's own steps have finished. This is the same
// save-state/get-state mechanism @actions/core wraps, used directly here to
// avoid pulling in a dependency for one file read and one file write.
const fs = require('fs');

const shouldRun = process.env['INPUT_SHOULD-RUN'] || 'false';
fs.appendFileSync(process.env.GITHUB_STATE, `should-run=${shouldRun}\n`);
