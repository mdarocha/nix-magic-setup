#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# Captures the Nix store contents after the build but BEFORE cache-nix-action's
# garbage-collection/save runs, recording each path's `ultimate` flag (true =
# built locally, false = substituted). This runs in the job's post phase, and is
# ordered to execute before cache-nix-action's own post step (see action.yml),
# so the derivation-level stats reflect the full built store rather than the
# post-GC one. Best-effort: never fail the job.

state_dir="${RUNNER_TEMP:-/tmp}/nix-magic-setup"
mkdir -p "$state_dir"

# `path-info --json` is an object on newer Nix and an array on older Nix;
# normalise both to `<path>\t<built|sub>` lines, excluding .drv files.
if ! nix --extra-experimental-features nix-command path-info --all --json 2>/dev/null \
    | jq -r '
        (if type == "object" then to_entries | map(.value + {path: .key}) else . end)
        | .[]
        | select((.path | endswith(".drv")) | not)
        | [.path, (if .ultimate then "built" else "sub" end)] | @tsv
      ' \
    | sort -u > "$state_dir/now.tsv"; then
    : > "$state_dir/now.tsv"
fi
