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
  actions: write # lets the cache prune stale entries

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
| `hestia-gc` | Run `hestia gc` after this job on the default branch; set it in exactly one job. See [hestia garbage collection](#hestia-garbage-collection) | `false` |

### Freeing runner storage

GitHub-hosted runners have limited disk space. The action runs [nothing-but-nix](https://github.com/wimpysworld/nothing-but-nix) before installing Nix.

- `free-up-all-storage: false` (default): safe cleanup that reclaims unallocated space without removing software.
- `free-up-all-storage: true`: aggressively deletes unneeded tools (Docker images, Android SDK, extra runtimes) on Ubuntu runners.

### Cache backend

- `cache-action: cache-nix-action` (default): saves the Nix store with [cache-nix-action](https://github.com/nix-community/cache-nix-action), one GitHub Actions cache entry per key.
- `cache-action: hestia`: uses [hestia](https://github.com/Mic92/hestia), a binary cache that stores build results as deduplicated packs in the GitHub Actions cache. It uploads less after a nixpkgs bump, makes fewer GitHub API calls, and rebuilds evicted paths instead of failing the job. [cache-shootout](https://github.com/Mic92/cache-shootout) benchmarks it against `cache-nix-action`.

### hestia garbage collection

hestia never evicts old entries, so the default branch's cache grows until it hits GitHub's 10 GB per-repository limit. Set `hestia-gc: true` in one job and the action prunes the cache with `hestia gc` after that job, so you don't need a separate gc workflow:

- gc only runs on the default branch. On other branches and pull requests it's skipped with a warning: their caches go away with the branch.
- Overlapping gc runs break the cache, so every hestia job checks `.github/workflows`. If no job sets `hestia-gc: true`, or more than one does, it logs a warning and gc doesn't run.
- gc needs `actions: write`. Without it, the job logs a warning and the cache isn't pruned.

For example:

```yaml
on:
  pull_request:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      actions: write # lets hestia gc delete stale cache entries
    steps:
      - uses: actions/checkout@v4
      - uses: mdarocha/nix-magic-setup@v1.1.0
        with:
          cache-action: hestia
          hestia-gc: true
      - run: nix flake check
```

Don't also copy hestia's scheduled [`gc.yml`](https://github.com/Mic92/hestia/blob/main/.github/workflows/gc.yml): the action doesn't know about it, so the two can overlap.

### Permissions

- `contents: read`: required to clone the repository.
- `actions: write`: lets `cache-nix-action` purge old entries and `hestia gc` delete stale ones. hestia also uses it to detect evicted entries upfront. Without it, caching still works but the cache is never pruned.

## Roadmap

- Comment on PRs with [nix-diff](https://github.com/Gabriella439/nix-diff)
- Show stats like build times, cache hits vs. misses in GitHub Actions summaries
