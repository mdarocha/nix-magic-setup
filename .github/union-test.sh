#!/usr/bin/env bash
# Throwaway: PR/base manifest union through nix-magic-setup's hestia wiring.
set -euo pipefail
phase="$1"

expr() {
  printf 'derivation { name = "nms-union-%s-%s"; system = "x86_64-linux"; builder = "/bin/sh"; args = ["-c" "echo %s-%s > $out"]; }' "$1" "$SALT" "$1" "$SALT"
}

expect_cached() {
  for name in "$@"; do
    log=$(nix build --impure --expr "$(expr "$name")" --max-jobs 0 --no-link --print-build-logs 2>&1) \
      || { echo "$log"; echo "FAIL: $name is not substitutable"; exit 1; }
    echo "$log" | grep -E "copying path '.*nms-union-$name-.*' from 'http://127.0.0.1" \
      || { echo "$log"; echo "FAIL: $name was not copied from hestia"; exit 1; }
    echo "OK: $name substituted from hestia"
  done
}

expect_absent() {
  for name in "$@"; do
    if nix build --impure --expr "$(expr "$name")" --max-jobs 0 --no-link >/dev/null 2>&1; then
      echo "FAIL: $name is visible but must not be"
      exit 1
    fi
    echo "OK: $name is not visible"
  done
}

build() { nix build --impure --expr "$(expr "$1")" --no-link --print-build-logs; echo "built $1"; }

echo "phase $phase, ref $GITHUB_REF"
case "$phase" in
  main1) build A ;;
  pr1) expect_cached A; expect_absent B; build B ;;
  main2) expect_cached A; expect_absent B; build C ;;
  pr2) expect_cached A B C; build D ;;
  *) echo "unknown phase $phase"; exit 1 ;;
esac
