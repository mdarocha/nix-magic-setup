#!/usr/bin/env bash
# Resolves cache-nix-action's GC limit and primary key.
set -euo pipefail

# `auto` keeps a quarter of the workspace disk free for staging the cache
# archive and for the job's own steps.
readonly AUTO_MIN_GIB=1
readonly AUTO_MAX_GIB=8

auto_store_size() {
    local free_kib gib
    free_kib=$(df -Pk "$GITHUB_WORKSPACE" | awk 'NR == 2 { print $4 }')
    gib=$((free_kib / 1024 / 1024 / 4))

    if [ "$gib" -lt "$AUTO_MIN_GIB" ]; then
        gib=$AUTO_MIN_GIB
    elif [ "$gib" -gt "$AUTO_MAX_GIB" ]; then
        gib=$AUTO_MAX_GIB
    fi

    echo "${gib}G"
}

store_size="$MAX_STORE_SIZE"
if [ "$store_size" = "auto" ]; then
    store_size=$(auto_store_size)
fi

echo "Nix store GC limit: ${store_size:-none}"
{
    echo "gc-max-store-size=$store_size"
    echo "primary-key=$PRIMARY_KEY"
} >> "$GITHUB_OUTPUT"
