# nix-magic-setup

[![GitHub Actions Marketplace](https://img.shields.io/badge/Marketplace-nix--magic--setup-blue?logo=github)](https://github.com/marketplace/actions/nix-magic-setup)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

One GitHub Action to install Nix, configure binary caches, cache store paths, and load development environments.

## Features

- Installs Nix using [cachix/install-nix-action](https://github.com/cachix/install-nix-action)
- Caches derivations with [nix-community/cache-nix-action](https://github.com/nix-community/cache-nix-action)
- Reports cache hit details and derivation sources (restored, substituted, or built locally) in the job summary
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
  actions: read # required to read cache metadata and manage cache entries

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
| `max-cached-store-size` | Max uncompressed Nix store size to cache (e.g. `8G`, `512M`). Empty string disables GC; `auto` dynamically sizes from free space | `auto` |

### Freeing runner storage

GitHub-hosted runners have limited disk space. The action runs [nothing-but-nix](https://github.com/wimpysworld/nothing-but-nix) before installing Nix.

- `free-up-all-storage: false` (default): safe cleanup that reclaims unallocated space without removing software.
- `free-up-all-storage: true`: aggressively deletes unneeded tools (Docker images, Android SDK, extra runtimes) on Ubuntu runners.

### Cache sizing

Before saving the cache, old store paths are garbage-collected down to `max-cached-store-size`.

- `auto` (default): targets 25% of available workspace disk space, clamped between `1G` and `8G`.
- Explicit size: set a fixed threshold such as `6G` or `512M`.
- Disable GC: pass `""` to save the whole store without pruning.

The limit applies to the uncompressed store (`nix store gc --max`). GitHub cache archives are compressed and usually 2–4× smaller.

### Cache stats

After the build, the action writes a summary to the GitHub Actions job summary:
- **Cache status:** details whether the primary cache matched or a fallback prefix was used.
- **Sizes:** restored size, saved size, and delta queried via the Actions Cache API.
- **Derivation breakdown:** store paths categorized as restored from cache, substituted from binary caches, or built locally.

### Permissions

- `contents: read`: required to clone the repository.
- `actions: read`: required by `cache-nix-action` to query and manage GitHub Actions cache entries.

## Roadmap

- Show build times in job summaries alongside cache stats
- Comment on PRs with [nix-diff](https://github.com/Gabriella439/nix-diff)
