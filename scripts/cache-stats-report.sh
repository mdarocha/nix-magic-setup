#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# Renders the Nix cache summary to the GitHub Actions job summary. It reports:
#   - which cache was restored (primary vs a prefix match) and its size;
#   - what happened on save: a new cache uploaded (size + delta vs the restored
#     cache), skipped because a cache for the key already existed (whether from
#     an exact primary-key hit at restore, or a concurrent run that saved one
#     while this job was still building), or a warning if the save appears to
#     have failed;
#   - a per-derivation breakdown: how many store paths came from the GitHub
#     cache, upstream binary caches, or were built locally (listed when < 100).
#
# It runs in the job's post phase, ordered (see action.yml) to execute AFTER
# cache-nix-action's own save step, so the save outcome can be observed via the
# GitHub Actions Cache API - cache-nix-action exposes neither cache sizes nor
# the save decision as outputs. The built store, and whether a cache for the
# primary key already existed right before cache-nix-action's own save ran,
# are both captured separately in cache-stats-capture.sh, which runs just
# before that save. Everything here is best-effort: a failure must never fail
# the job, so the caller ignores the exit status.

script_dir="$(dirname "${BASH_SOURCE[0]}")"
source "$script_dir/lib/cache-api.sh"

state_dir="${RUNNER_TEMP:-/tmp}/nix-magic-setup"
summary_file="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

pre_file="$state_dir/pre-paths.txt"
post_file="$state_dir/post-paths.txt"
now_file="$state_dir/now.tsv"
meta_file="$state_dir/cache-meta.env"
pre_save_file="$state_dir/pre-save.env"

hit_primary=""; hit_first_match=""; primary_key=""; restored_key=""
if [ -f "$meta_file" ]; then
    # shellcheck source=/dev/null
    . "$meta_file"
    hit_primary="${CACHE_HIT_PRIMARY_KEY:-}"
    hit_first_match="${CACHE_HIT_FIRST_MATCH:-}"
    primary_key="${CACHE_PRIMARY_KEY:-}"
    restored_key="${CACHE_RESTORED_KEY:-}"
fi

primary_existed_pre_save="false"; primary_size_pre_save=""
if [ -f "$pre_save_file" ]; then
    # shellcheck source=/dev/null
    . "$pre_save_file"
    primary_existed_pre_save="${CACHE_PRIMARY_EXISTED_PRE_SAVE:-false}"
    primary_size_pre_save="${CACHE_PRIMARY_SIZE_PRE_SAVE:-}"
fi

api_available=false
[ -n "${NMS_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] && api_available=true

# --- Restore section ---------------------------------------------------------
restored_size="$(nms_cache_size_bytes "$restored_key")"

if [ "$hit_primary" = "true" ]; then
    restored_line="✅ Restored the **primary** cache (\`${restored_key}\`), size **$(nms_human_size "$restored_size")**."
elif [ "$hit_first_match" = "true" ]; then
    restored_line="♻️ Restored a **different** cache via prefix match (\`${restored_key}\`), size **$(nms_human_size "$restored_size")**."
else
    restored_line="❌ No cache restored — cold store."
fi

# --- Save section -------------------------------------------------------------
# cache-nix-action decides whether to save based on its OWN check, at save
# time, for whether a cache with the primary key already exists - independent
# of whether restore hit the primary key earlier in the job. So "restore
# missed the primary key" does not imply "this run saved a new cache": a
# concurrent run (e.g. another workflow triggered by the same push, evaluating
# the same flake.lock/*.nix state) can race to save that exact key first.
# `primary_existed_pre_save` (checked immediately before cache-nix-action's own
# save step) captures that race; comparing it against the current state below
# tells us what actually happened, without needing an output cache-nix-action
# doesn't provide.
if [ "$hit_primary" = "true" ]; then
    save_line="⏭️ Save skipped — exact primary-key hit at restore, the cache was already current."
elif [ "$api_available" != "true" ]; then
    save_line="⬆️ A new cache may be saved for \`${primary_key}\` (outcome unavailable — no Cache API access)."
elif [ "$primary_existed_pre_save" = "true" ]; then
    save_line="⏭️ Save skipped — a cache for \`${primary_key}\` already existed by save time (size **$(nms_human_size "$primary_size_pre_save")**), likely uploaded by a concurrent run."
else
    saved_size="$(nms_cache_size_bytes "$primary_key")"
    if [ -n "$saved_size" ]; then
        delta=""
        if [ -n "$restored_size" ]; then
            d=$(( saved_size - restored_size ))
            sign="+"; [ "$d" -lt 0 ] && sign="-"
            delta=" (${sign}$(nms_human_size "${d#-}") vs restored)"
        fi
        save_line="⬆️ Saved a new cache (\`${primary_key}\`), size **$(nms_human_size "$saved_size")**${delta}."
    else
        save_line="⚠️ No cache found for \`${primary_key}\` after save — it may have failed."
    fi
fi

# --- Per-derivation breakdown --------------------------------------------------
deriv_section=""
if [ -s "$now_file" ] && [ -f "$post_file" ]; then
    [ -f "$pre_file" ] || : > "$pre_file"
    workdir="$(mktemp -d)"
    trap 'rm -rf "$workdir"' EXIT
    tab="$(printf '\t')"

    cut -f1 "$now_file" > "$workdir/now.txt"
    comm -23 "$post_file" "$pre_file" | comm -12 - "$workdir/now.txt" > "$workdir/from-github.txt"
    comm -23 "$workdir/now.txt" "$post_file" > "$workdir/new.txt"
    join -t "$tab" "$workdir/new.txt" "$now_file" > "$workdir/new-flagged.tsv"
    awk -F'\t' '$2 == "built" { print $1 }' "$workdir/new-flagged.tsv" > "$workdir/built.txt"
    awk -F'\t' '$2 == "sub"   { print $1 }' "$workdir/new-flagged.tsv" > "$workdir/upstream.txt"

    github_count=$(wc -l < "$workdir/from-github.txt" | tr -d ' ')
    built_count=$(wc -l < "$workdir/built.txt" | tr -d ' ')
    upstream_count=$(wc -l < "$workdir/upstream.txt" | tr -d ' ')

    deriv_section="$(
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
            while IFS= read -r p; do echo "- \`$p\`"; done < <(sort "$workdir/built.txt")
            echo
            echo "</details>"
        else
            echo "> $built_count paths were built locally (too many to list individually)."
        fi
    )"
fi

# --- Emit --------------------------------------------------------------------
{
    echo "## ❄️ Nix cache"
    echo
    echo "$restored_line"
    echo
    echo "$save_line"
    if [ -n "$deriv_section" ]; then
        echo
        echo "$deriv_section"
    fi
    echo
} >> "$summary_file"
