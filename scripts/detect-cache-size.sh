#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# Picks a max-cached-store-size when the user leaves the input on "auto".
#
# The GC cap only bounds the *store*, but the cache archive cache-nix-action
# builds from it is staged uncompressed on the workspace filesystem (see the
# README's Cache size section) — a filesystem this action never grows, and one
# that shrinks further as the job's own build/test steps run after this point.
# A cap sized for a roomy hosted runner can leave a small or already-busy
# runner with no room to stage that archive, failing the cache save outright.
#
# Heuristic: a quarter of the workspace filesystem's *currently* free space
# (the earliest and only reliable signal this step has — later usage by the
# job's own build steps can't be known yet), clamped to [1G, 8G]. 8G matches
# the previous fixed default (generous enough that a typical full build's
# store survives GC and gets cached); 1G matches cache-nix-action's own
# smallest documented example. A quarter leaves headroom for the archive
# write itself plus whatever the rest of the job still consumes.

if [ "$#" -lt 1 ]; then
    echo "usage: detect-cache-size.sh <max-cached-store-size input>" >&2
    exit 1
fi
input="$1"

if [ "$input" != "auto" ]; then
    # Explicit override, including "" (disables garbage collection entirely) -
    # pass through unchanged.
    printf 'value=%s\n' "$input" >>"$GITHUB_OUTPUT"
    exit 0
fi

workspace="${GITHUB_WORKSPACE:-.}"
floor_gib=1
ceiling_gib=8

avail_kib="$(df --output=avail -k "$workspace" 2>/dev/null | tail -n1 | tr -d ' ')"
if [ -z "$avail_kib" ] || ! [ "$avail_kib" -gt 0 ] 2>/dev/null; then
    # Couldn't read free space (unsupported df flags, unusual mount) - fall back
    # to the old fixed default rather than guessing.
    printf 'value=%sG\n' "$ceiling_gib" >>"$GITHUB_OUTPUT"
    exit 0
fi

avail_gib=$((avail_kib / 1024 / 1024))
target_gib=$((avail_gib / 4))

if [ "$target_gib" -lt "$floor_gib" ]; then
    target_gib="$floor_gib"
elif [ "$target_gib" -gt "$ceiling_gib" ]; then
    target_gib="$ceiling_gib"
fi

printf 'value=%sG\n' "$target_gib" >>"$GITHUB_OUTPUT"
