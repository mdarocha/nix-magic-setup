#!/usr/bin/env bash
# Decides whether this job owns running hestia's garbage collection: it must
# be on the default branch, and its own workflow file must be the one (and
# only one) declaring `concurrency: group: hestia-gc` - that's what a
# workflow author uses to both pick which job owns gc and get GitHub to
# serialize concurrent runs of it, which hestia gc itself is not safe
# against (see hestia-gc/post.js). The actual `hestia gc` invocation happens
# later, in hestia-gc's post step, so it runs after the rest of this job's
# own steps rather than blocking them.
#
# Every workflow file is checked for the group, not just the current one, so
# a second job accidentally declaring the same group is caught as a
# misconfiguration (ambiguous ownership) even on runs that aren't the owner.
set -euo pipefail

emit() {
    echo "should-run=$1" >> "$GITHUB_OUTPUT"
    exit 0
}

# Deliberately only matches the plain, unquoted `group: hestia-gc` mapping
# form (with an optional trailing comment) - the shape every example in this
# project's own docs uses. A quoted value or the `concurrency: hestia-gc`
# scalar shorthand won't be picked up.
group_pattern='^[[:space:]]*group:[[:space:]]*hestia-gc[[:space:]]*(#.*)?$'

mapfile -t owners < <(grep -El "$group_pattern" "${GITHUB_WORKSPACE}/.github/workflows/"*.y*ml 2>/dev/null || true)

if [ "${#owners[@]}" -gt 1 ]; then
    printed_owners="${owners[*]#"$GITHUB_WORKSPACE"/}"
    echo "::error::'concurrency: group: hestia-gc' is declared in more than one workflow file ($printed_owners). Only one job may own hestia gc - remove the group from the others."
    exit 1
fi

if [ "${GITHUB_REF:-}" != "refs/heads/${DEFAULT_BRANCH}" ]; then
    emit false
fi

if [ "${#owners[@]}" -eq 0 ]; then
    echo "::warning::No job declares 'concurrency: group: hestia-gc'; hestia gc won't run automatically on the default branch. Add it to the one job that should own periodic gc."
    emit false
fi

# GITHUB_WORKFLOW_REF is "<owner>/<repo>/<path>@<ref>"; strip both ends to
# get the workflow file's path relative to the repo root.
current_workflow="${GITHUB_WORKFLOW_REF#*/*/}"
current_workflow="${current_workflow%@*}"

if [ "${owners[0]}" != "${GITHUB_WORKSPACE}/${current_workflow}" ]; then
    echo "hestia-gc is owned by ${owners[0]#"$GITHUB_WORKSPACE"/}, not this workflow ($current_workflow); skipping"
    emit false
fi

echo "This job owns the hestia-gc concurrency group; hestia gc will run once this job's own steps finish"
emit true
