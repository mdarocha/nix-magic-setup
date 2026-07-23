#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# Captures the Nix store contents after the build but BEFORE cache-nix-action's
# garbage-collection/save runs, recording each path's `ultimate` flag (true =
# built locally, false = substituted). This runs in the job's post phase, and is
# ordered to execute before cache-nix-action's own post step (see action.yml),
# so the derivation-level stats reflect the full built store rather than the
# post-GC one. Best-effort: never fail the job.
#
# It also checks, at this same point, whether a cache for CACHE_PRIMARY_KEY
# already exists - i.e. immediately before cache-nix-action's own save step
# runs. cache-nix-action performs the same check internally to decide whether
# to upload a new cache, but doesn't expose that decision as an output. Doing
# our own check right beforehand lets the report distinguish "this run's save
# genuinely uploaded a new cache" from "a cache for this key already existed
# by save time" (e.g. a concurrent workflow run with the same flake.lock/*.nix
# state raced to save it first).

script_dir="$(dirname "${BASH_SOURCE[0]}")"
source "$script_dir/lib/cache-api.sh"

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

pre_save_size="$(nms_cache_size_bytes "${CACHE_PRIMARY_KEY:-}")"
existed=false
[ -n "$pre_save_size" ] && existed=true
{
    printf 'CACHE_PRIMARY_EXISTED_PRE_SAVE=%s\n' "$existed"
    printf 'CACHE_PRIMARY_SIZE_PRE_SAVE=%s\n' "$pre_save_size"
} > "$state_dir/pre-save.env"
