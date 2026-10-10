#!/usr/bin/env bash
# Runs `hestia gc` on the default branch, the only cache scope that outlives its branch.
# Overlapping gc runs race each other's pack deletes, so gc runs only when exactly one
# workflow job uses this action with hestia.
set -euo pipefail
shopt -s inherit_errexit

source "$(dirname "${BASH_SOURCE[0]}")/lib/github-api.sh"

skip() {
    echo "::warning::Skipping hestia gc: $1"
    exit 0
}

yq=(yq)
# Only mikefarah's yq; the Python yq wrapper takes a different syntax.
if ! type -P yq > /dev/null || ! yq --version | grep -q mikefarah; then
    yq=(nix --extra-experimental-features 'nix-command flakes' run nixpkgs#yq-go --)
fi

# Prints "<workflow path>:<job id>" for each job that uses this action with hestia.
hestia_jobs() {
    local workflow
    for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do
        if [ ! -f "$workflow" ]; then
            continue
        fi
        "${yq[@]}" -o=json "$workflow" | jq -r --arg file "$workflow" '
            .jobs // {} | to_entries[]
            | select(any(.value.steps[]?;
                (.uses // "" | contains("nix-magic-setup")) and .with["cache-action"] == "hestia"))
            | "\($file):\(.key)"
        '
    done
}

if [ -z "${HESTIA_BIN:-}" ]; then
    skip "hestia wasn't set up"
fi

# The event payload of some triggers (e.g. schedule) may lack the repository.
default_branch=${DEFAULT_BRANCH:-$(github_api "" | jq -r .default_branch)}
if [ "$GITHUB_REF" != "refs/heads/$default_branch" ]; then
    skip "not on the default branch ($default_branch)"
fi

cd "$GITHUB_WORKSPACE"
jobs=$(hestia_jobs)
if [ "$(grep -c . <<< "$jobs")" -gt 1 ]; then
    skip "more than one job uses hestia, so their gc runs could overlap: $(xargs <<< "$jobs")"
fi

"$HESTIA_BIN" gc
