#!/usr/bin/env bash
# Runs hestia gc, if scripts/setup-hestia-gc.sh decided this job owns it.
# Invoked as the post command of a pyTooling/Actions/with-post-step step
# (see action.yml), so this runs after the rest of the job's own steps -
# composite actions have no runs.post of their own to hook into directly.
set -euo pipefail

if [ "${HESTIA_GC_SHOULD_RUN:-}" != "true" ]; then
    exit 0
fi

if [ -z "${HESTIA_BIN:-}" ]; then
    echo "::warning::hestia-gc: HESTIA_BIN is not set (the hestia cache step may have been skipped or failed); skipping gc"
    exit 0
fi

echo "Running hestia gc"
if ! "$HESTIA_BIN" gc; then
    # Non-fatal: a gc hiccup shouldn't turn an otherwise-successful job red.
    # It gets another chance on the next run that owns the group.
    echo "::warning::hestia gc failed; will retry on the next run that owns it"
fi
