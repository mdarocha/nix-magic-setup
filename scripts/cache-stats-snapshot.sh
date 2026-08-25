#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# Records the set of valid Nix store paths at a point in time, so the post-run
# report can attribute each derivation to a source. Two snapshots are taken:
#   pre  - after Nix is installed but *before* the cache is restored. This is the
#          baseline toolchain (fetched from upstream during install); it's
#          treated as noise and excluded from the report.
#   post - immediately *after* the cache is restored, so (post - pre) is exactly
#          what the GitHub Actions cache provided.
# The report itself takes a third look at the store in the post step, after the
# build has run, to find what the build added on top of this.

phase="${1:?usage: cache-stats-snapshot.sh <pre|post>}"

state_dir="${RUNNER_TEMP:-/tmp}/nix-magic-setup"
mkdir -p "$state_dir"

store_paths() {
    # Exclude .drv files: they're instantiated locally during evaluation, never
    # "built" or "substituted", so counting them would only add noise. We report
    # on realised outputs and their dependencies.
    nix --extra-experimental-features nix-command path-info --all 2>/dev/null \
        | awk '!/\.drv$/' | sort -u
}

case "$phase" in
    pre)
        store_paths > "$state_dir/pre-paths.txt"
        ;;
    post)
        store_paths > "$state_dir/post-paths.txt"
        # Stash the cache restore result so the report can show it alongside the
        # derivation-level breakdown.
        {
            printf 'CACHE_HIT_PRIMARY_KEY=%s\n' "${CACHE_HIT_PRIMARY_KEY:-}"
            printf 'CACHE_HIT_FIRST_MATCH=%s\n' "${CACHE_HIT_FIRST_MATCH:-}"
            printf 'CACHE_PRIMARY_KEY=%s\n' "${CACHE_PRIMARY_KEY:-}"
            printf 'CACHE_RESTORED_KEY=%s\n' "${CACHE_RESTORED_KEY:-}"
        } > "$state_dir/cache-meta.env"
        ;;
    *)
        echo "cache-stats-snapshot.sh: unknown phase '$phase'" >&2
        exit 1
        ;;
esac
