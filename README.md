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
- Automagically setting up environments from `.envrc` using [aldoborrero/direnv-nix-action](https://github.com/aldoborrero/direnv-nix-action)
- Commenting with [mdarocha/comment-flake-lock-changelog](https://github.com/mdarocha/comment-flake-lock-changelog) when a PR updates `flake.lock`

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
      - uses: mdarocha/nix-magic-setup@v1.0.0
      - run: nix flake check
```

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
- Automatically set up Nix config according to `nixConfig` flake keys
