#!/usr/bin/env bash
# Shared helpers for querying the GitHub Actions Cache API. cache-nix-action
# doesn't expose cache sizes (or the save outcome) as step outputs, so the
# cache stats scripts fall back to querying the API directly wherever they
# need that information.

# Prints the largest size in bytes (across refs) of a cache with the given
# exact key, or nothing if unknown, not found, or there's no API access
# (missing token/repository). Never fails the caller.
nms_cache_size_bytes() {
    local key="$1"
    [ -n "$key" ] && [ -n "${NMS_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] || return 0
    local api="${GITHUB_API_URL:-https://api.github.com}"
    curl -sfSL \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${NMS_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${api}/repos/${GITHUB_REPOSITORY}/actions/caches?key=${key}" 2>/dev/null \
        | jq -r '[.actions_caches[]?.size_in_bytes] | (max // empty)' 2>/dev/null || true
}

# Renders a byte count as a human-readable IEC size, or "unknown" if empty.
nms_human_size() {
    local b="${1:-}"
    [ -n "$b" ] || { printf 'unknown'; return; }
    numfmt --to=iec-i --suffix=B --format='%.1f' "$b" 2>/dev/null || printf '%s B' "$b"
}
