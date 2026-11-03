#!/usr/bin/env bash
# Resolves the `steps` and `skip` inputs into one `<step>=true|false` output per step and
# checks `nix-distribution`, so a typo fails the job instead of silently running nothing.
set -euo pipefail
shopt -s inherit_errexit

readonly ALL_STEPS=(free-up-storage install-nix nix-config cache direnv)
readonly DISTRIBUTIONS=(nix determinate)

fail() {
    echo "::error::$1"
    exit 1
}

contains() {
    local needle=$1 item
    shift
    for item in "$@"; do
        if [ "$item" = "$needle" ]; then
            return 0
        fi
    done
    return 1
}

# Fails if any of the steps after the input name $1 isn't a known step.
check_steps() {
    local input=$1 step
    shift
    for step in "$@"; do
        if ! contains "$step" "${ALL_STEPS[@]}"; then
            fail "Unknown step '$step' in '$input', expected one of: ${ALL_STEPS[*]}"
        fi
    done
}

if ! contains "$NIX_DISTRIBUTION" "${DISTRIBUTIONS[@]}"; then
    fail "Unknown nix-distribution '$NIX_DISTRIBUTION', expected one of: ${DISTRIBUTIONS[*]}"
fi

# Lists are separated by newlines, commas or spaces.
read -ra selected <<< "$(tr ',\r\n' '   ' <<< "$STEPS")"
read -ra skipped <<< "$(tr ',\r\n' '   ' <<< "$SKIP")"
check_steps steps "${selected[@]}"
check_steps skip "${skipped[@]}"

if [ "${#selected[@]}" -eq 0 ]; then
    selected=("${ALL_STEPS[@]}")
fi

running=()
for step in "${ALL_STEPS[@]}"; do
    if contains "$step" "${selected[@]}" && ! contains "$step" "${skipped[@]}"; then
        running+=("$step")
        echo "$step=true" >> "$GITHUB_OUTPUT"
    else
        echo "$step=false" >> "$GITHUB_OUTPUT"
    fi
done

if [ "${#running[@]}" -eq 0 ]; then
    echo "::warning::Every step is skipped, so the action does nothing"
fi
echo "Running: ${running[*]:-nothing} (Nix distribution: $NIX_DISTRIBUTION)"
