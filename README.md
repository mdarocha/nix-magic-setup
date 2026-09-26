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

- `cache-action: cache-nix-action` (default): saves the Nix store with [cache-nix-action](https://github.com/nix-community/cache-nix-action), one GitHub Actions cache entry per key.
- `cache-action: hestia`: uses [hestia](https://github.com/Mic92/hestia), a binary cache that stores build results as deduplicated packs in the GitHub Actions cache. It uploads less after a nixpkgs bump, makes fewer GitHub API calls, and rebuilds evicted paths instead of failing the job. [cache-shootout](https://github.com/Mic92/cache-shootout) benchmarks it against `cache-nix-action`.

With `hestia`, paths signed by a cache Nix already trusts (`cache.nixos.org`, caches from `flake.nix`'s `nixConfig`, devenv's caches) are left to that cache and never uploaded. The action sets hestia's `github-token`, `upstream-cache-filter` and `upstream-cache-key-names`; use [Mic92/hestia](https://github.com/Mic92/hestia) directly if you need its other inputs.

### hestia garbage collection

hestia never evicts old entries, so its cache grows until it hits GitHub's 10 GB per-repository limit. To clean it up, add a job that runs only on the default branch to the `hestia-gc` concurrency group:

```yaml
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      actions: write # hestia gc deletes cache entries
    concurrency:
      group: hestia-gc
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v4
      - uses: mdarocha/nix-magic-setup@v1.1.0
        with:
          cache-action: hestia
      - run: nix flake check
```

That job runs `hestia gc` after its other steps. The group queues its runs, so two gc runs never overlap. The action reads every workflow in `.github/workflows` and fails if more than one job is in the group; a workflow-level `concurrency` puts all of that workflow's jobs in it.

Don't trigger that job on `pull_request`. A concurrency group queues every run that shares it, so PR builds would wait on each other and on the default branch.

Alternatively, copy hestia's scheduled [`gc.yml`](https://github.com/Mic92/hestia/blob/main/.github/workflows/gc.yml). It declares the same group, so no other job may use it.

### Permissions

- `contents: read`: required to clone the repository.
- `actions: read`: required to manage cache entries with `cache-nix-action`; optional with `hestia` (lets it detect evicted entries upfront).
- `actions: write`: required by the job that runs `hestia gc`.

## Roadmap

- Comment on PRs with [nix-diff](https://github.com/Gabriella439/nix-diff)
- Show stats like build times, cache hits vs. misses in GitHub Actions summaries
