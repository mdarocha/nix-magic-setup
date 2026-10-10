#!/usr/bin/env bash
# Resolves cache-nix-action's GC limit and cache keys.
set -euo pipefail

# `auto` keeps the store to a quarter of the workspace disk's free space:
# cache-nix-action writes the cache archive to that disk before uploading it.
readonly AUTO_FREE_SPACE_DIVISOR=4
readonly AUTO_MIN_GIB=1
readonly AUTO_MAX_GIB=8

auto_store_size() {
    local free_kib gib
    free_kib=$(df -Pk "$GITHUB_WORKSPACE" | awk 'NR == 2 { print $4 }')
    gib=$((free_kib / 1024 / 1024 / AUTO_FREE_SPACE_DIVISOR))

    if [ "$gib" -lt "$AUTO_MIN_GIB" ]; then
        gib=$AUTO_MIN_GIB
    elif [ "$gib" -gt "$AUTO_MAX_GIB" ]; then
        gib=$AUTO_MAX_GIB
    fi

    echo "${gib}G"
}

store_size=$MAX_STORE_SIZE
if [ "$store_size" = "auto" ]; then
    store_size=$(auto_store_size)
fi
echo "Nix store GC limit: ${store_size:-none}"

key_prefix="nix-$RUNNER_OS-"
{
    echo "gc-max-store-size=$store_size"
    echo "key-prefix=$key_prefix"
    # The input, not the resolved size, so `auto` keeps one key across runners
    # with different free space, while changing the input starts a new cache.
    echo "primary-key=$key_prefix$MAX_STORE_SIZE-$FILES_HASH"
} >> "$GITHUB_OUTPUT"
