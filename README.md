# nix-magic-setup
[![GitHub Actions Marketplace](https://img.shields.io/badge/Marketplace-nix--magic--setup-blue?logo=github)](https://github.com/marketplace/actions/nix-magic-setup)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

One action to install Nix, cache builds, and automate common flake workflows in GitHub Actions.

Managing Nix in GitHub Actions means wiring together multiple separate actions, getting cache
config right, and re-doing it for every new repo. nix-magic-setup bundles all of that into a
single drop-in action.

## Features

- Installing Nix using [cachix/install-nix-action](https://github.com/cachix/install-nix-action)
- Caching Nix derivations using [nix-community/cache-nix-action](https://github.com/nix-community/cache-nix-action)
- Automagically setting up environments from `.envrc` using direnv
- Commenting with [mdarocha/comment-flake-lock-changelog](https://github.com/mdarocha/comment-flake-lock-changelog) when a PR updates `flake.lock`
- Freeing up runner disk space before installing Nix using [wimpysworld/nothing-but-nix](https://github.com/wimpysworld/nothing-but-nix)
- Automatically setting `NIX_CONFIG` from your `flake.nix`'s `nixConfig`, so cache settings like
  `extra-substituters`/`extra-trusted-public-keys` don't need to be duplicated in the workflow
- Automatically adding [devenv](https://devenv.sh)'s recommended binary caches (including its
  bundled pre-commit hooks integration) to `NIX_CONFIG` when devenv is detected

## Example usage

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  actions: read
  pull-requests: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mdarocha/nix-magic-setup@v1.1.0
      - run: nix flake check
```

## Configuration

| Input             | Description                                                                                           | Default             |
|--------------------|-------------------------------------------------------------------------------------------------------|----------------------|
| `token`            | Github authentication token to use                                                                    | `${{ github.token }}` |
| `free-up-all-storage` | Aggressively free up all possible disk space on the runner before installing Nix, using [wimpysworld/nothing-but-nix](https://github.com/wimpysworld/nothing-but-nix) | `false`              |

### Freeing up storage

GitHub Actions runners only have a small amount of free disk space available, which can be
a problem for larger Nix builds. This action always runs
[wimpysworld/nothing-but-nix](https://github.com/wimpysworld/nothing-but-nix) before Nix is
installed to reclaim some disk space from Ubuntu runners. By default (`free-up-all-storage: false`)
it uses the `holster` protocol, which just claims free space without purging any pre-installed
software. Setting `free-up-all-storage` to `true` switches to the `rampage` protocol, aggressively
purging unneeded pre-installed software (like Docker images, browsers, and other language
runtimes) to make the most room possible for the Nix store. This only works on Ubuntu runners
and is skipped gracefully on other platforms.

```yaml
- uses: mdarocha/nix-magic-setup@v1.1.0
  with:
    free-up-all-storage: true
```

Whichever protocol is used, the action keeps a few GB free on the runner's `/` and `/mnt`
filesystems so that steps running *after* it can still write to the root disk (for example an
action that installs a CLI into `$HOME`) without hitting `no space left on device`.

## Permissions required

This action uses the workflows' `GITHUB_TOKEN` by default. Certain features require specific permissions to work.

They can be set using the [`permissions`](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#permissions) key in your workflow file.

Certain features also only work in the context of a cloned repository, so they require the `actions/checkout` action to be run before this one.

- `actions: read` - required by `cache-nix-action` to read GitHub Actions cache and purge old cache entries
- `pull-requests: write` - required by `comment-flake-lock-changelog` to comment on PRs
- `contents: read` - remember to add it when setting permissions, to make sure the actions has permissions required to clone the repo

## Roadmap

In the future, this action is planned to also:
- Comment on PRs with [nix-diff](https://github.com/Gabriella439/nix-diff)
- Show stats like build times, cache hits vs. misses in GitHub Actions summaries
