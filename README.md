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
- Reports in the job summary where each store path came from, and which cache was restored and saved
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
| `max-cached-store-size` | Max Nix store size cache-nix-action saves, e.g. `8G`; `auto` sizes it from free disk space. See [Cache size](#cache-size) | `auto` |

### Freeing runner storage

GitHub-hosted runners have limited disk space. The action runs [nothing-but-nix](https://github.com/wimpysworld/nothing-but-nix) before installing Nix.

- `free-up-all-storage: false` (default): safe cleanup that reclaims unallocated space without removing software.
- `free-up-all-storage: true`: aggressively deletes unneeded tools (Docker images, Android SDK, extra runtimes) on Ubuntu runners.

### Cache backend

- `cache-action: cache-nix-action` (default): saves the Nix store with [cache-nix-action](https://github.com/nix-community/cache-nix-action), one GitHub Actions cache entry per key.
- `cache-action: hestia`: uses [hestia](https://github.com/Mic92/hestia), a binary cache that stores build results as deduplicated packs in the GitHub Actions cache. It uploads less after a nixpkgs bump, makes fewer GitHub API calls, and rebuilds evicted paths instead of failing the job. [cache-shootout](https://github.com/Mic92/cache-shootout) benchmarks it against `cache-nix-action`.

### Cache size

With `cache-nix-action`, the store is garbage-collected down to `max-cached-store-size` (`nix store gc --max`) before saving. The limit applies to the uncompressed store; the saved archive is compressed, usually 2 to 4 times smaller. hestia ignores this input: it uploads only what the job built.

- `auto` (default): a quarter of the free space on the workspace disk, between `1G` and `8G`. cache-nix-action writes the cache archive to that disk before uploading it.
- A fixed size such as `6G` or `512M`.
- `""`: no GC, the whole store is saved.

The input is part of the cache key, so changing it starts a new cache.

### hestia garbage collection

hestia never evicts old entries, so the default branch's cache grows until it hits GitHub's 10 GB per-repository limit. The action prunes it with `hestia gc`, so you don't need a separate gc workflow:

- gc runs after a job on the default branch finishes, but only if no other job is still running on that branch, so two gc runs never overlap.
- Jobs on other branches and pull requests skip gc: their caches go away with the branch.
- gc needs `actions: write`. Without it, the job logs a warning and the cache isn't pruned.

Don't also copy hestia's scheduled [`gc.yml`](https://github.com/Mic92/hestia/blob/main/.github/workflows/gc.yml): it doesn't check for running jobs, so it can overlap with the action's gc.

### Cache stats

The job summary shows how many store paths came from the GitHub Actions cache, were substituted from binary caches, or were built locally, and lists the built ones. With `cache-nix-action` it also shows which cache was restored, whether a new one was saved, and how its size changed. Sizes come from the GitHub Actions cache API.

### Permissions

- `contents: read`: required to clone the repository.
- `actions: write`: lets `cache-nix-action` purge old entries and `hestia gc` delete stale ones. hestia also uses it to detect evicted entries upfront, and the cache stats to read cache sizes. Without it, caching still works but the cache is never pruned.

## Roadmap

- Comment on PRs with [nix-diff](https://github.com/Gabriella439/nix-diff)
- Show build times in the job summary
