#!/usr/bin/env bash
# Lets only the default branch write to the hestia cache. hestia reads a branch's own
# manifest before the default branch's, so once a pull request has written one, it never
# sees the default branch's newer paths again and rebuilds them.
set -euo pipefail
shopt -s inherit_errexit

source "$(dirname "${BASH_SOURCE[0]}")/lib/github-api.sh"

# The event payload of some triggers (e.g. schedule) may lack the repository.
default_branch=${DEFAULT_BRANCH:-$(github_api "" | jq -r .default_branch)}

if [ "$GITHUB_REF" = "refs/heads/$default_branch" ]; then
    echo "read-only=false" >> "$GITHUB_OUTPUT"
else
    echo "$GITHUB_REF isn't the default branch ($default_branch): hestia only reads from the cache"
    echo "read-only=true" >> "$GITHUB_OUTPUT"
fi
