#!/usr/bin/env bash
# Writes a Nix cache summary to the job summary. Called once per phase:
#   start     before the cache setup; paths already there came with Nix and aren't counted
#   restored  after the cache setup; new paths came from cache-nix-action's restore
#   finish    post-job, before the cache's post steps (cache-nix-action GCs the store)
#   report    post-job, after the cache's post steps
set -euo pipefail
shopt -s inherit_errexit

source "$(dirname "${BASH_SOURCE[0]}")/lib/github-api.sh"

readonly MAX_LISTED_BUILT_PATHS=200

phase=${1:?usage: cache-stats.sh <start|restored|finish|report>}
state_dir="$RUNNER_TEMP/nix-magic-setup/cache-stats"
mkdir -p "$state_dir"

nix_cmd() {
    nix --extra-experimental-features nix-command "$@"
}

# .drv files come from evaluation; they're never built or substituted.
store_paths() {
    nix_cmd path-info --all | awk '!/\.drv$/'
}

# Prints "<path>\t<built|signed|unsigned>" for every store path. Newer Nix wants
# --json-format; older Nix lacks it and may print an array instead of an object.
store_path_origins() {
    { nix_cmd path-info --all --json --json-format 1 2> /dev/null || nix_cmd path-info --all --json; } \
        | jq -r '
            if type == "object" then to_entries | map(.value + {path: .key}) else . end
            | .[]
            | select(.path | endswith(".drv") | not)
            | [.path, if .ultimate then "built" elif (.signatures // []) != [] then "signed" else "unsigned" end]
            | @tsv
        '
}

# Prints the size in bytes of the cache with exactly key $1 (on ref $2, if given):
# nothing if there's no such cache, "unknown" if the API can't be read.
cache_size() {
    local response ref_filter=()
    if [ -n "${2:-}" ]; then
        ref_filter=(--data-urlencode "ref=$2")
    fi
    if ! response=$(github_api /actions/caches --data-urlencode "key=$1" "${ref_filter[@]}"); then
        echo unknown
        return
    fi
    jq -r --arg key "$1" '[.actions_caches[] | select(.key == $key) | .size_in_bytes] | max // empty' <<< "$response"
}

human_size() {
    case $1 in
        "" | unknown) echo "unknown size" ;;
        *) LC_ALL=C numfmt --to=iec-i --suffix=B --format='%.1f' "$1" ;;
    esac
}

# Records the named variables for later phases.
save_state() {
    local file=$1 name
    shift
    for name in "$@"; do
        printf '%s=%q\n' "$name" "${!name:-}"
    done > "$state_dir/$file"
}

# A missing file means an earlier phase failed or didn't run.
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

restore_line() {
    if [ "$HIT_PRIMARY_KEY" = true ]; then
        echo "✅ Restored the primary cache \`$RESTORED_KEY\` ($(human_size "$restored_size"))."
    elif [ "$HIT_FIRST_MATCH" = true ]; then
        echo "♻️ No cache for \`$PRIMARY_KEY\`; restored \`$RESTORED_KEY\` ($(human_size "$restored_size"))."
    else
        echo "❌ No cache restored."
    fi
}

# cache-nix-action saves only when the job succeeds and the primary key has no
# cache on this ref at save time; a concurrent run may have saved one.
save_line() {
    local unknown="❔ Save outcome unknown: the Actions cache API couldn't be read."

    if [ "$HIT_PRIMARY_KEY" = true ]; then
        echo "⏭️ Save skipped: the primary cache was already up to date."
    elif [ "$JOB_STATUS" != success ]; then
        echo "⏭️ Save skipped: the job didn't succeed."
    elif [ "$SIZE_BEFORE_SAVE" = unknown ]; then
        echo "$unknown"
    elif [ -n "$SIZE_BEFORE_SAVE" ]; then
        echo "⏭️ Save skipped: \`$PRIMARY_KEY\` ($(human_size "$SIZE_BEFORE_SAVE")) already existed on \`$GITHUB_REF\` at save time, probably saved by a concurrent run."
    else
        local saved
        saved=$(cache_size "$PRIMARY_KEY" "$GITHUB_REF")
        case $saved in
            unknown) echo "$unknown" ;;
            "") echo "⚠️ No cache found for \`$PRIMARY_KEY\` after the save; it may have failed." ;;
            *) echo "⬆️ Saved \`$PRIMARY_KEY\` ($(human_size "$saved")$(size_delta "$saved"))." ;;
        esac
    fi
}

size_delta() {
    local saved=$1 diff sign=+
    case $restored_size in
        "" | unknown) return ;;
    esac

    diff=$((saved - restored_size))
    if [ "$diff" -lt 0 ]; then
        sign=-
    fi
    echo ", $sign$(human_size "${diff#-}") vs. restored"
}

# hestia serves unsigned paths, while binary caches sign theirs.
origins_section() {
    local built_list="$state_dir/built.txt" hestia=0 counts from_cache substituted built
    if [ "$CACHE_ACTION" = hestia ]; then
        hestia=1
    fi

    counts=$(awk -F'\t' -v built_list="$built_list" -v hestia="$hestia" '
        FILENAME == ARGV[1] { installed[$0]; next }
        FILENAME == ARGV[2] { restored[$0]; next }
        $1 in installed { next }
        $1 in restored || ($2 == "unsigned" && hestia) { from_cache++; next }
        $2 == "built" { built++; print $1 > built_list; next }
        { substituted++ }
        END { print from_cache + 0, substituted + 0, built + 0 }
    ' "$state_dir/start.txt" "$state_dir/restored.txt" "$state_dir/origins.tsv")
    read -r from_cache substituted built <<< "$counts"

    echo "| Store paths | Count |"
    echo "| --- | ---: |"
    echo "| ♻️ From the GitHub Actions cache | $from_cache |"
    echo "| ⬇️ Substituted from binary caches | $substituted |"
    echo "| 🔨 Built locally | $built |"
    echo

    if [ "$built" -eq 0 ]; then
        echo "Nothing was built locally."
    elif [ "$built" -le "$MAX_LISTED_BUILT_PATHS" ]; then
        echo "<details><summary>Built locally ($built)</summary>"
        echo
        sort "$built_list" | while read -r path; do echo "- \`$path\`"; done
        echo
        echo "</details>"
    else
        echo "$built paths were built locally, too many to list."
    fi
}

case $phase in
    start)
        store_paths > "$state_dir/start.txt"
        ;;

    restored)
        store_paths > "$state_dir/restored.txt"
        save_state restore.env PRIMARY_KEY RESTORED_KEY HIT_PRIMARY_KEY HIT_FIRST_MATCH
        ;;

    finish)
        load_state restore.env
        store_path_origins > "$state_dir/origins.tsv"

        SIZE_BEFORE_SAVE=""
        if [ "$CACHE_ACTION" = cache-nix-action ] && [ "$HIT_PRIMARY_KEY" != true ]; then
            SIZE_BEFORE_SAVE=$(cache_size "$PRIMARY_KEY" "$GITHUB_REF")
        fi
        save_state save.env SIZE_BEFORE_SAVE
        ;;

    report)
        load_state restore.env save.env
        restored_size=""
        if [ -n "$RESTORED_KEY" ]; then
            restored_size=$(cache_size "$RESTORED_KEY")
        fi

        {
            echo "## ❄️ Nix cache ($CACHE_ACTION)"
            echo
            if [ "$CACHE_ACTION" = cache-nix-action ]; then
                restore_line
                echo
                save_line
                echo
            fi
            origins_section
            echo
        } >> "$GITHUB_STEP_SUMMARY"
        ;;

    *)
        echo "cache-stats.sh: unknown phase '$phase'" >&2
        exit 1
        ;;
esac
