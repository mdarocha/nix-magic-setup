#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/check-trusted-context.sh"

# Install direnv if absent; the job must have Nix, from the install-nix step or the runner.
if ! command -v direnv &>/dev/null; then
    echo "direnv not found, installing via nix profile..."
    nix profile add nixpkgs#direnv
else
    echo "direnv already installed at $(command -v direnv)"
fi

# Allow the .envrc so direnv will export it.
direnv allow

# direnv export json emits a JSON object mapping every variable that the
# .envrc would add or change relative to the bare environment.
#
# PATH is handled specially: GitHub Actions reads $GITHUB_PATH line-by-line
# and prepends each entry to PATH for all subsequent steps, so we write
# the direnv PATH value there rather than $GITHUB_ENV.
#
# All other variables use the multiline-safe heredoc format so that values
# containing '=' or newlines are written correctly to $GITHUB_ENV.
# Each variable gets its own random delimiter to guarantee no collision with
# the value content.
envrc_json=$(direnv export json)

path_value=$(printf '%s' "$envrc_json" | jq -r 'if has("PATH") then .PATH else "" end')
if [ -n "$path_value" ]; then
    echo "Prepending direnv PATH to GITHUB_PATH"
    echo "$path_value" >> "$GITHUB_PATH"
fi

printf '%s' "$envrc_json" | jq -r 'to_entries[] | select(.key != "PATH") | [.key, .value] | @tsv' | \
while IFS=$'\t' read -r key value; do
    echo "Exporting: $key"
    delim="envrc_delim_$(openssl rand -hex 16)"
    printf '%s<<%s\n%s\n%s\n' "$key" "$delim" "$value" "$delim" >> "$GITHUB_ENV"
done
