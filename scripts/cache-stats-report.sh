#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# Renders a per-derivation cache breakdown to the GitHub Actions job summary:
# how many store paths were restored from the GitHub Actions cache, substituted
# from upstream binary caches, or built locally during this run. Built paths are
# listed individually when there are fewer than 100 of them.
#
# Runs in the job's post phase (via pyTooling/Actions/with-post-step), after the
# workflow's build steps, so it can compare the store against the snapshots
# taken during setup. Everything here is best-effort: a failure must never fail
# the job, so the caller ignores the exit status.

state_dir="${RUNNER_TEMP:-/tmp}/nix-magic-setup"
summary_file="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

pre_file="$state_dir/pre-paths.txt"
post_file="$state_dir/post-paths.txt"
meta_file="$state_dir/cache-meta.env"

if [ ! -f "$post_file" ]; then
    echo "nix-magic-setup: no store snapshot found, skipping cache stats."
    exit 0
fi
[ -f "$pre_file" ] || : > "$pre_file"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

tab="$(printf '\t')"

# Current store contents with each path's `ultimate` flag. Nix sets
# ultimate=true for paths built locally and false for paths pulled from a binary
# cache, which is exactly the built-vs-substituted distinction we need.
# `path-info --json` is an object on newer Nix and an array on older Nix;
# normalise both to `<path>\t<built|sub>` lines.
if ! nix --extra-experimental-features nix-command path-info --all --json 2>/dev/null \
    | jq -r '
        (if type == "object" then to_entries | map(.value + {path: .key}) else . end)
        | .[]
        | select((.path | endswith(".drv")) | not)
        | [.path, (if .ultimate then "built" else "sub" end)] | @tsv
      ' \
    | sort -u > "$workdir/now.tsv"; then
    echo "nix-magic-setup: could not query the Nix store, skipping cache stats."
    exit 0
fi
cut -f1 "$workdir/now.tsv" > "$workdir/now.txt"

# What the GitHub Actions cache provided and is still present: (post - pre) ∩ now
comm -23 "$post_file" "$pre_file" | comm -12 - "$workdir/now.txt" > "$workdir/from-github.txt"

# What the build added on top of the restored store: now - post
comm -23 "$workdir/now.txt" "$post_file" > "$workdir/new.txt"

# Split the new paths into built-locally vs substituted-from-upstream using the
# ultimate flag captured above.
join -t "$tab" "$workdir/new.txt" "$workdir/now.tsv" > "$workdir/new-flagged.tsv"
awk -F'\t' '$2 == "built" { print $1 }' "$workdir/new-flagged.tsv" > "$workdir/built.txt"
awk -F'\t' '$2 == "sub"   { print $1 }' "$workdir/new-flagged.tsv" > "$workdir/upstream.txt"

github_count=$(wc -l < "$workdir/from-github.txt" | tr -d ' ')
built_count=$(wc -l < "$workdir/built.txt" | tr -d ' ')
upstream_count=$(wc -l < "$workdir/upstream.txt" | tr -d ' ')

# Cache restore status line.
cache_line=""
if [ -f "$meta_file" ]; then
    # shellcheck source=/dev/null
    . "$meta_file"
    if [ "${CACHE_HIT_PRIMARY_KEY:-}" = "true" ]; then
        cache_line="✅ GitHub Actions cache hit on the exact key (\`${CACHE_RESTORED_KEY:-}\`)."
    elif [ "${CACHE_HIT_FIRST_MATCH:-}" = "true" ]; then
        cache_line="♻️ GitHub Actions cache restored from a prefix match (\`${CACHE_RESTORED_KEY:-}\`)."
    else
        cache_line="❌ GitHub Actions cache miss — started from a cold store."
    fi
fi

{
    echo "## ❄️ Nix cache"
    echo
    if [ -n "$cache_line" ]; then
        echo "$cache_line"
        echo
    fi
    echo "Store paths by source for this run:"
    echo
    echo "| Source | Paths |"
    echo "| --- | ---: |"
    echo "| ♻️ Restored from GitHub Actions cache | $github_count |"
    echo "| ⬇️ Substituted from upstream caches | $upstream_count |"
    echo "| 🔨 Built locally (no cache) | $built_count |"
    echo

    if [ "$built_count" -eq 0 ]; then
        echo "Everything was served from a cache — nothing had to be built. 🎉"
    elif [ "$built_count" -lt 100 ]; then
        echo "<details>"
        echo "<summary>🔨 Built locally ($built_count)</summary>"
        echo
        while IFS= read -r p; do
            echo "- \`$p\`"
        done < <(sort "$workdir/built.txt")
        echo
        echo "</details>"
    else
        echo "> $built_count paths were built locally (too many to list individually)."
    fi
    echo
} >> "$summary_file"
