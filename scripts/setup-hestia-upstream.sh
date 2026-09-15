#!/usr/bin/env bash
# Derives hestia's upstream-cache-key-names from NIX_CONFIG: the signing key
# names under trusted-public-keys/extra-trusted-public-keys are caches
# hestia's upstream-cache-filter can skip re-uploading, since they're
# already fetchable from wherever those keys are trusted. NIX_CONFIG carries
# both flake.nix's own nixConfig and devenv's recommended caches by the time
# this step runs (see setup-nixconfig.sh), so this needs no separate flake
# parsing of its own. cache.nixos.org-1 is always included since it's Nix's
# built-in default regardless of what NIX_CONFIG says.
set -euo pipefail

key_names="cache.nixos.org-1"

if [ -n "${NIX_CONFIG:-}" ]; then
    while IFS='=' read -r key value; do
        key="$(xargs <<< "$key")"
        case "$key" in
            trusted-public-keys | extra-trusted-public-keys)
                for token in $value; do
                    key_names+=" ${token%%:*}"
                done
                ;;
        esac
    done <<< "$NIX_CONFIG"
fi

key_names="$(tr ' ' '\n' <<< "$key_names" | awk 'NF && !seen[$0]++' | xargs)"

echo "key-names=$key_names" >> "$GITHUB_OUTPUT"
