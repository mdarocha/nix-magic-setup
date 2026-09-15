#!/usr/bin/env bash
# Runs hestia's garbage collection, but only when this job owns it: it must
# be on the default branch, and its own workflow file must be the one (and
# only one) declaring `concurrency: group: hestia-gc` - that's what a
# workflow author uses to both pick which job owns gc and get GitHub to
# serialize concurrent runs of it, which hestia gc itself is not safe
# against. gc runs right here, right after the cache step sets HESTIA_BIN -
# composite actions have no way to register a true post-job hook (that needs
# a node/docker action's `runs.post`), so this can't wait for the rest of
# the job's own steps the way hestia's own upload/drain does.
#
# Every workflow file is checked for the group, not just the current one, so
# a second job accidentally declaring the same group is caught as a
# misconfiguration (ambiguous ownership) even on runs that aren't the owner.
set -euo pipefail

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
    exit 0
fi

if [ "${#owners[@]}" -eq 0 ]; then
    echo "::warning::No job declares 'concurrency: group: hestia-gc'; hestia gc won't run automatically on the default branch. Add it to the one job that should own periodic gc."
    exit 0
fi

# GITHUB_WORKFLOW_REF is "<owner>/<repo>/<path>@<ref>"; strip both ends to
# get the workflow file's path relative to the repo root.
current_workflow="${GITHUB_WORKFLOW_REF#*/*/}"
current_workflow="${current_workflow%@*}"

if [ "${owners[0]}" != "${GITHUB_WORKSPACE}/${current_workflow}" ]; then
    echo "hestia-gc is owned by ${owners[0]#"$GITHUB_WORKSPACE"/}, not this workflow ($current_workflow); skipping"
    exit 0
fi

if [ -z "${HESTIA_BIN:-}" ]; then
    echo "::warning::hestia-gc: HESTIA_BIN is not set (the hestia cache step may have been skipped or failed); skipping gc"
    exit 0
fi

echo "This job owns the hestia-gc concurrency group; running hestia gc"
if ! "$HESTIA_BIN" gc; then
    # Non-fatal: this runs ahead of the job's own build/deploy steps, and a
    # gc hiccup shouldn't turn an otherwise-successful run red. It gets
    # another chance on the next run that owns the group.
    echo "::warning::hestia gc failed; will retry on the next run that owns it"
fi
