# nix-magic-setup
[![GitHub Actions Marketplace](https://img.shields.io/badge/Marketplace-nix--magic--setup-blue?logo=github)](https://github.com/marketplace/actions/nix-magic-setup)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

One action to install Nix, cache builds, and automate common flake workflows in GitHub Actions.

Managing Nix in GitHub Actions means wiring together multiple separate actions, getting cache
config right, and re-doing it for every new repo. nix-magic-setup bundles all of that into a
single drop-in action.

## Features

- Installs Nix using [cachix/install-nix-action](https://github.com/cachix/install-nix-action)
- Caches derivations with [nix-community/cache-nix-action](https://github.com/nix-community/cache-nix-action) or, optionally, [Mic92/hestia](https://github.com/Mic92/hestia)
- Automatically loads `.envrc` via direnv
- Frees runner disk space using [wimpysworld/nothing-but-nix](https://github.com/wimpysworld/nothing-but-nix)
- Applies `nixConfig` from `flake.nix` (e.g. `extra-substituters`, `extra-trusted-public-keys`) to `NIX_CONFIG`
- Configures [devenv](https://devenv.sh) binary caches automatically when detected

## Usage

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  actions: read # required to manage cache entries

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mdarocha/nix-magic-setup@v1.1.0
      - run: nix flake check
```

## Options

| Input | Description | Default |
| --- | --- | --- |
| `token` | GitHub authentication token | `${{ github.token }}` |
| `free-up-all-storage` | Aggressively reclaim runner disk space by removing pre-installed software (Ubuntu runners) | `false` |
| `cache-action` | Nix binary cache backend: `cache-nix-action` or `hestia` | `cache-nix-action` |

### Freeing runner storage

GitHub-hosted runners have limited disk space. The action runs [nothing-but-nix](https://github.com/wimpysworld/nothing-but-nix) before installing Nix.

- `free-up-all-storage: false` (default): safe cleanup that reclaims unallocated space without removing software.
- `free-up-all-storage: true`: aggressively deletes unneeded tools (Docker images, Android SDK, extra runtimes) on Ubuntu runners.

### Cache backend

- `cache-action: cache-nix-action` (default): caches the whole Nix store with [cache-nix-action](https://github.com/nix-community/cache-nix-action), one GitHub Actions cache entry per key.
- `cache-action: hestia`: uses [hestia](https://github.com/Mic92/hestia) instead, a binary-cache-shaped alternative that packs build results into a few large, content-deduplicated blobs. It uploads less on a nixpkgs bump, makes far fewer GitHub API calls, and evicted paths just trigger a rebuild rather than a failed job. See [cache-shootout](https://github.com/Mic92/cache-shootout) for benchmarks against `cache-nix-action`.

  Switching to `hestia` requires one extra step this action can't do for you: add a daily GC workflow to your repository (copy [`gc.yml`](https://github.com/Mic92/hestia/blob/main/.github/workflows/gc.yml) from the hestia repo) to stay within GitHub's 10 GB per-repo cache quota — `hestia` has no LRU eviction of its own.

  This action always turns on `upstream-cache-filter` and derives `upstream-cache-key-names` for you: it reads the trusted signing keys out of `NIX_CONFIG` (the union of `flake.nix`'s own `nixConfig`, the caches added when devenv is detected, and whatever the workflow set beforehand), adds the default `cache.nixos.org-1`, and passes the result to hestia. In practice this means any cache you've already told Nix to trust — nixpkgs, devenv, or an extra substituter from `flake.nix` — is treated as "upstream" and never re-uploaded into your GitHub Actions quota; only what actually gets built in your job is.

  `hestia` takes several other inputs this action doesn't expose (it only wires up `github-token` plus the two above); use the `Mic92/hestia` action directly instead of `nix-magic-setup` if you need to tune them. Worth knowing about:

  | Input | Default | What it does |
  | --- | --- | --- |
  | `filter-drv-closures` | `false` | Extend the upstream filter to registered derivation closures (matrix builds); requires `upstream-cache-filter`. |
  | `read-only` | `false` | Substitute from the cache but never write to it — for jobs that should only consume a central job's cache. |
  | `no-closure` | `false` | Cache only the paths a job built, not their runtime closure. |
  | `drain-timeout` | `300` | Seconds the post-job step waits for the final upload to finish. |

  These are situational rather than generally recommended — `read-only` for consumer-only jobs in a matrix, `no-closure` if you only care about caching your own outputs and are fine re-substituting their dependencies from upstream, `drain-timeout` only if jobs are timing out mid-upload.

### Permissions

- `contents: read`: required to clone the repository.
- `actions: read`: required to manage cache entries with `cache-nix-action`; optional with `hestia` (lets it detect evicted entries upfront).

## Roadmap

- Comment on PRs with [nix-diff](https://github.com/Gabriella439/nix-diff)
- Show stats like build times, cache hits vs. misses in GitHub Actions summaries
