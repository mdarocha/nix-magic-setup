#!/usr/bin/env bash
# Writes a Nix cache summary to the job summary: which cache was restored, what
# was saved, and where each store path came from. Called once per phase:
#
#   pre-restore   before cache-nix-action restores the store
#   post-restore  right after the restore
#   pre-save      post-job, before cache-nix-action's GC and save
#   report        post-job, after the save
#
# cache-nix-action doesn't output cache sizes or whether it saved, so both are
# read from the GitHub Actions Cache API.
set -Eeuo pipefail

phase="${1:?usage: cache-stats.sh <pre-restore|post-restore|pre-save|report>}"

# Stats are informational; never fail the job over them.
trap 'echo "::warning::Nix cache stats failed in the $phase phase"; exit 0' ERR

readonly MAX_LISTED_BUILT_PATHS=200

state_dir="${RUNNER_TEMP:-/tmp}/nix-magic-setup"
mkdir -p "$state_dir"

# .drv files are created by evaluation, never built or substituted.
store_paths() {
    nix --extra-experimental-features nix-command path-info --all 2> /dev/null \
        | awk '!/\.drv$/'
}

# Prints "<path>\t<built|substituted>" for every output path. `path-info
# --json` is an object on newer Nix and an array on older Nix.
store_path_origins() {
    nix --extra-experimental-features nix-command path-info --all --json 2> /dev/null \
        | jq -r '
            if type == "object" then to_entries | map(.value + {path: .key}) else . end
            | .[]
            | select(.path | endswith(".drv") | not)
            | [.path, (if .ultimate then "built" else "substituted" end)]
            | @tsv
        '
}

# Prints the size in bytes of the cache with exactly this key, or nothing if
# there's no such cache or no API access.
cache_size() {
    local key="$1" response
    if [ -z "$key" ] || [ -z "${NMS_TOKEN:-}" ]; then
        return 0
    fi

    response=$(curl -sfSL \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $NMS_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${GITHUB_API_URL:-https://api.github.com}/repos/$GITHUB_REPOSITORY/actions/caches?key=$key") || return 0
    jq -r --arg key "$key" '[.actions_caches[]? | select(.key == $key) | .size_in_bytes] | max // empty' <<< "$response"
}

human_size() {
    if [ -z "$1" ]; then
        echo "unknown size"
        return
    fi
    numfmt --to=iec-i --suffix=B --format='%.1f' "$1"
}

restore_line() {
    local size
    size=$(cache_size "$RESTORED_KEY")

    if [ "$HIT_PRIMARY_KEY" = "true" ]; then
        echo "✅ Restored the primary cache \`$RESTORED_KEY\` ($(human_size "$size"))."
    elif [ "$HIT_FIRST_MATCH" = "true" ]; then
        echo "♻️ Primary cache missed; restored \`$RESTORED_KEY\` ($(human_size "$size"))."
    else
        echo "❌ No cache restored."
    fi
}

# cache-nix-action skips the save whenever a cache for the primary key exists
# at save time, even if the restore missed it, e.g. when a concurrent run saved
# it first.
save_line() {
    if [ "$HIT_PRIMARY_KEY" = "true" ]; then
        echo "⏭️ Save skipped: the primary cache was already up to date."
        return
    fi

    if [ -z "${NMS_TOKEN:-}" ]; then
        echo "⬆️ Save outcome for \`$PRIMARY_KEY\` unknown: no Cache API access."
        return
    fi

    if [ -n "$PRIMARY_SIZE_BEFORE_SAVE" ]; then
        echo "⏭️ Save skipped: \`$PRIMARY_KEY\` ($(human_size "$PRIMARY_SIZE_BEFORE_SAVE")) already existed at save time, probably saved by a concurrent run."
        return
    fi

    local saved restored delta=""
    saved=$(cache_size "$PRIMARY_KEY")
    if [ -z "$saved" ]; then
        echo "⚠️ No cache found for \`$PRIMARY_KEY\` after the save; it may have failed."
        return
    fi

    restored=$(cache_size "$RESTORED_KEY")
    if [ -n "$restored" ]; then
        local diff=$((saved - restored)) sign="+"
        if [ "$diff" -lt 0 ]; then
            sign="-"
        fi
        delta=", ${sign}$(human_size "${diff#-}") vs. restored"
    fi
    echo "⬆️ Saved \`$PRIMARY_KEY\` ($(human_size "$saved")$delta)."
}

# Paths present before the restore belong to the Nix installation and aren't
# counted.
origins_section() {
    local built_list="$state_dir/built.txt" restored substituted built
    read -r restored substituted built < <(
        awk -F'\t' -v built_list="$built_list" '
            FILENAME == ARGV[1] { before_restore[$0]; next }
            FILENAME == ARGV[2] { after_restore[$0]; next }
            $1 in after_restore { if (!($1 in before_restore)) restored++; next }
            $2 == "built" { built++; print $1 > built_list; next }
            { substituted++ }
            END { print restored + 0, substituted + 0, built + 0 }
        ' "$state_dir/pre-restore.txt" "$state_dir/post-restore.txt" "$state_dir/pre-save.tsv"
    )

    echo "| Store paths | Count |"
    echo "| --- | ---: |"
    echo "| ♻️ Restored from the GitHub Actions cache | $restored |"
    echo "| ⬇️ Substituted from binary caches | $substituted |"
    echo "| 🔨 Built locally | $built |"
    echo

    if [ "$built" -eq 0 ]; then
        echo "Nothing was built locally."
    elif [ "$built" -lt "$MAX_LISTED_BUILT_PATHS" ]; then
        echo "<details><summary>Built locally ($built)</summary>"
        echo
        sort "$built_list" | while read -r path; do echo "- \`$path\`"; done
        echo
        echo "</details>"
    else
        echo "$built paths were built locally, too many to list."
    fi
}

# A missing state file means an earlier phase was skipped, e.g. because the
# cache step failed.
load_state() {
    local file
    for file in "$@"; do
        if [ ! -f "$state_dir/$file" ]; then
            echo "::warning::Nix cache stats skipped: $file wasn't recorded"
            exit 0
        fi
        # shellcheck source=/dev/null
        source "$state_dir/$file"
    done
}

case "$phase" in
    pre-restore)
        store_paths > "$state_dir/pre-restore.txt"
        ;;

    post-restore)
        store_paths > "$state_dir/post-restore.txt"
        {
            printf 'HIT_PRIMARY_KEY=%q\n' "$CACHE_HIT_PRIMARY_KEY"
            printf 'HIT_FIRST_MATCH=%q\n' "$CACHE_HIT_FIRST_MATCH"
            printf 'PRIMARY_KEY=%q\n' "$CACHE_PRIMARY_KEY"
            printf 'RESTORED_KEY=%q\n' "$CACHE_RESTORED_KEY"
        } > "$state_dir/restore.env"
        ;;

    pre-save)
        # Captured before cache-nix-action's GC deletes paths built by this job.
        store_path_origins > "$state_dir/pre-save.tsv"

        load_state restore.env
        size=""
        if [ "$HIT_PRIMARY_KEY" != "true" ]; then
            size=$(cache_size "$PRIMARY_KEY")
        fi
        printf 'PRIMARY_SIZE_BEFORE_SAVE=%q\n' "$size" > "$state_dir/save.env"
        ;;

    report)
        load_state restore.env save.env
        {
            echo "## ❄️ Nix cache"
            echo
            restore_line
            echo
            save_line
            echo
            origins_section
            echo
        } >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
        ;;

    *)
        echo "cache-stats.sh: unknown phase '$phase'" >&2
        exit 1
        ;;
esac
