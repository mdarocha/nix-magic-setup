#!/usr/bin/env bash
# Sizes the space nothing-but-nix leaves outside /nix, and resolves cache-nix-action's
# GC limit and keys. Runs before nothing-but-nix.
set -euo pipefail
shopt -s inherit_errexit

source "$(dirname "${BASH_SOURCE[0]}")/lib/github-api.sh"

# Minimum room for the job's own files on /; nothing-but-nix's default root-safe-haven.
readonly MIN_JOB_FILES_MIB=2048
# `auto` keeps the store to an eighth of the free space, between these bounds.
readonly AUTO_FREE_SPACE_DIVISOR=8
readonly AUTO_MIN_GIB=1
readonly AUTO_MAX_GIB=8
# zstd shrinks a Nix store 2-4x; plan for the worst case.
readonly ARCHIVE_COMPRESSION_RATIO=2
# @actions/cache doesn't save archives over 10 GiB.
readonly MAX_ARCHIVE_MIB=10240
# nothing-but-nix's default; it puts the job's TMPDIR on /mnt.
readonly SEPARATE_MNT_HAVEN_MIB=1024

free_mib() {
    df -Pk "$1" | awk 'NR == 2 { print int($4 / 1024) }'
}

filesystem() {
    df -P "$1" | awk 'NR == 2 { print $1 }'
}

# Prints cache-nix-action's gc-max-store-size $1 in MiB, or nothing if it doesn't GC.
store_limit_mib() {
    if ! [[ $1 =~ ^([0-9]+)([KMG]?)$ ]]; then
        return
    fi

    local n=${BASH_REMATCH[1]}
    case ${BASH_REMATCH[2]} in
        G) echo $((n * 1024)) ;;
        M) echo "$n" ;;
        K) echo $((n / 1024)) ;;
        *) echo $((n / 1024 / 1024)) ;;
    esac
}

auto_store_size() {
    local gib=$(($1 / 1024 / AUTO_FREE_SPACE_DIVISOR))

    if [ "$gib" -lt "$AUTO_MIN_GIB" ]; then
        gib=$AUTO_MIN_GIB
    elif [ "$gib" -gt "$AUTO_MAX_GIB" ]; then
        gib=$AUTO_MAX_GIB
    fi

    echo "${gib}G"
}

# Prints the largest cache under prefix $1 in MiB; nothing if the cache API can't be read.
largest_cache_mib() {
    local response
    if ! response=$(github_api /actions/caches --data-urlencode "key=$1" --data per_page=100 2> /dev/null); then
        return
    fi
    jq '[.actions_caches[].size_in_bytes] | (max // 0) / 1048576 | ceil' <<< "$response"
}

# Prints the MiB cache-nix-action needs in $RUNNER_TEMP to restore and save its archive.
# hestia streams to the cache and needs none.
archive_mib() {
    local store_size=$1 key_prefix=$2 limit largest archive

    if [ "$CACHE_ACTION" != cache-nix-action ]; then
        echo 0
        return
    fi

    limit=$(store_limit_mib "$store_size")
    archive=$MAX_ARCHIVE_MIB
    if [ -n "$limit" ]; then
        archive=$((limit / ARCHIVE_COMPRESSION_RATIO))
    fi

    # GC stops at live paths, so a real archive can outgrow the limit.
    largest=$(largest_cache_mib "$key_prefix")
    if [ -z "$largest" ]; then
        echo "::notice::Couldn't read the Actions cache API, so the space for the cache archive is estimated from the store size alone" >&2
    elif [ "$largest" -gt "$archive" ]; then
        archive=$largest
    fi

    if [ "$archive" -gt "$MAX_ARCHIVE_MIB" ]; then
        archive=$MAX_ARCHIVE_MIB
    fi
    echo "$archive"
}

key_prefix="nix-$RUNNER_OS-"
temp_free=$(free_mib "$RUNNER_TEMP")

store_size=$MAX_STORE_SIZE
if [ "$store_size" = auto ]; then
    store_size=$(auto_store_size "$temp_free")
fi

workspace_mib=$({ du -sk "$GITHUB_WORKSPACE" 2> /dev/null || true; } | awk '{ print int($1 / 1024) }')
# Builds may write as much again as the checkout holds.
job_files=$((workspace_mib > MIN_JOB_FILES_MIB ? workspace_mib : MIN_JOB_FILES_MIB))
archive=$(archive_mib "$store_size" "$key_prefix")

# The Nix volume gets at least half the free space, even if the archive then doesn't fit.
reserve=$((job_files + archive))
if [ "$reserve" -gt $((temp_free / 2)) ]; then
    echo "::warning::Only $temp_free MiB free: leaving half of it on / for job files and the cache archive, which may need $reserve MiB"
    reserve=$((temp_free / 2))
fi

# nothing-but-nix fills /mnt down to mnt-safe-haven, then / down to root-safe-haven
# once it has purged software. On current runners /mnt is on /.
mnt_haven=$reserve
separate_mnt=""
if [ "$RUNNER_OS" = Linux ] && [ -d /mnt ] && [ "$(filesystem /mnt)" != "$(filesystem "$RUNNER_TEMP")" ]; then
    mnt_haven=$SEPARATE_MNT_HAVEN_MIB
    separate_mnt=", /mnt is separate with $(free_mib /mnt) MiB free"
fi

echo "Free space on $RUNNER_TEMP: $temp_free MiB$separate_mnt"
echo "Workspace: $workspace_mib MiB"
echo "Nix store GC limit: ${store_size:-none}"
echo "Space nothing-but-nix leaves on /: $reserve MiB (job files $job_files MiB, cache archive $archive MiB)"

{
    echo "root-safe-haven=$reserve"
    echo "mnt-safe-haven=$mnt_haven"
    echo "gc-max-store-size=$store_size"
    echo "key-prefix=$key_prefix"
    # The input, not the resolved size, so `auto` keeps one key across runners
    # with different free space, while changing the input starts a new cache.
    echo "primary-key=$key_prefix$MAX_STORE_SIZE-$FILES_HASH"
} >> "$GITHUB_OUTPUT"
