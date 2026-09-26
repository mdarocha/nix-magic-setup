#!/usr/bin/env bash
# Treats every cache Nix already trusts as upstream, so hestia doesn't
# re-upload paths those caches can serve.
set -euo pipefail

trusted_keys=$(nix --extra-experimental-features nix-command config show trusted-public-keys)

key_names=()
for key in $trusted_keys; do
    key_names+=("${key%%:*}")
done

echo "key-names=${key_names[*]}" >> "$GITHUB_OUTPUT"
