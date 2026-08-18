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
- Reporting per-derivation cache stats to the GitHub Actions job summary — how many store paths
  were restored from the GitHub cache, substituted from upstream caches, or built locally
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
| `max-cached-store-size` | Maximum uncompressed Nix store size to keep in the cache (e.g. `8G`, `512M`); an empty string disables garbage collection; `auto` sizes it from the runner's free disk space. See [Cache size](#cache-size). | `auto`                 |
| `changelog-filter` | Shell command forwarded to [comment-flake-lock-changelog](https://github.com/mdarocha/comment-flake-lock-changelog)'s `build-filter`, to hide `flake.lock` changelog commits that don't affect your build output. See its [README](https://github.com/mdarocha/comment-flake-lock-changelog#build-filter). | `""`                 |

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

### Cache size

The Nix store is cached with [nix-community/cache-nix-action](https://github.com/nix-community/cache-nix-action).
Just before a new cache is saved, the action garbage-collects old store paths until the store is at or
below `max-cached-store-size`, so the cache doesn't grow without bound.

By default (`auto`) this is computed per-run, right after the [storage freeing](#freeing-up-storage)
step: a quarter of the workspace filesystem's free space at that point, clamped to `1G`–`8G`. A
generously-provisioned or already-tight runner gets a cap that reflects it, instead of every runner
sharing one fixed number regardless of how much room it actually has. `auto` runs on every job — pass
an explicit value (see below) to opt out and pin a fixed size instead.

A few things worth knowing when tuning this:

- **The limit is on the uncompressed store.** That's what the underlying garbage collector measures
  (`nix store gc --max`). The cache uploaded to GitHub is compressed and in practice ends up roughly
  2–4x smaller (e.g. a ~5.5 GiB store compresses to under ~2 GiB). There is no way to cap the
  compressed size directly, because garbage collection happens before compression — use that ratio as a
  rule of thumb. GitHub gives each repository 10 GiB of Actions cache and evicts least-recently-used
  entries beyond that, so a store of a handful of GiB leaves plenty of headroom.
- **Set the limit above what a full build produces.** Garbage collection only runs when the store
  exceeds the limit *and* the primary key didn't hit exactly. Keeping the ceiling comfortably above your
  build's store size means the freshly-built paths survive collection and actually get saved (and then
  restored fully warm on the next run) instead of being collected away and rebuilt every time. If `auto`
  computes something too tight for your build (a large build on a runner with little free disk), pin an
  explicit value instead.
- **Some commands don't create GC roots.** Notably `nix flake check` builds derivations without leaving
  a GC root, so their outputs count as garbage. They're kept in the cache only if they fit under this
  limit — another reason to keep it generous.
- **Disabling collection.** Set `max-cached-store-size` to an empty string to skip garbage collection
  entirely and cache the whole store. Only do this if you're confident the store stays comfortably under
  GitHub's cache limits.
- **The compressed archive is staged on the runner's workspace disk, not `/nix`.** `cache-nix-action`
  builds the `tar`+`zstd` archive under the Actions workspace/`RUNNER_TEMP` path before uploading it —
  a filesystem this action does *not* grow, even when `free-up-all-storage: true` carves out extra
  space for `/nix` itself. Standard GitHub-hosted runners start with only a few GiB free there, and
  other steps in the same job (Docker layers, VM-based tests, extra checkouts) eat into that same
  budget before the cache save runs — after `auto`'s measurement is taken, so a job that's unusually
  disk-hungry after this action runs can still exhaust it. If a save fails with `zstd: ... No space left
  on device` / `Could not save the new cache`, check the runner's free space at save time (e.g. `df -h /`
  right before this action's cache step) — a smaller cap can shrink the archive enough to fit, but it's
  not a substitute for giving the job more workspace headroom (running fewer disk-heavy steps before the
  save, or `free-up-all-storage: true`).
- **Changing this value busts the cache.** It's part of the cache's primary key, so a run whose resolved
  `max-cached-store-size` differs from the last one — including an `auto` value that lands on a
  different number because the runner had more or less free disk — always saves a fresh cache under the
  new target instead of reusing one collected under the old one.

```yaml
- uses: mdarocha/nix-magic-setup@v1.1.0
  with:
    max-cached-store-size: 6G
```

### Cache stats

After your build steps have run, the action writes a summary to the
[job summary](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/)
covering the whole cache lifecycle.

**Restore and save.** Which cache was restored — the exact **primary** cache or a **different**
prefix-matched one — and its size, followed by what happened on save: a new cache uploaded (with its
size and the delta versus the restored cache), the save skipped (either an exact primary-key hit at
restore, or a cache for that key already existing by save time — which happens when a concurrent run,
e.g. another workflow triggered by the same push, races to save the same key first), or a warning if no
cache turns up afterwards. Sizes come from the GitHub Actions Cache API, so the job needs `actions: read`
(already required by the [cache](#cache-size)).

**Per-derivation breakdown.** Where each Nix store path came from:

- **♻️ Restored from GitHub Actions cache** — paths the cache restored, so they didn't need to be
  fetched or built.
- **⬇️ Substituted from upstream caches** — paths pulled from binary caches (`cache.nixos.org`, Cachix,
  and any `extra-substituters` from your `flake.nix`) during the build.
- **🔨 Built locally** — paths that were built on the runner because no cache had them. When there are
  fewer than 200, they're listed individually so you can see exactly what wasn't cached.

The breakdown snapshots the store before and after the cache is restored, and classifies whatever the
build adds using Nix's own `ultimate` flag (set on locally-built paths). Reporting runs in the job's
post phase — after your build, and ordered around cache-nix-action's own save so it can observe the
outcome — which the action arranges via
[pyTooling/Actions/with-post-step](https://github.com/pyTooling/Actions), since a composite action
can't declare a post step of its own. No configuration is required; it reports automatically.

### Changelog filter

`changelog-filter` runs before the Nix store cache is restored, not after — deliberately. Determining
build relevance evaluates the changed input (e.g. `nixpkgs`) at various commits, and each one gets
imported into the Nix store fresh, uncached, so a wide-reaching range (a multi-day `nixpkgs` bump can
be thousands of commits) can use a meaningful amount of disk before it's done.
comment-flake-lock-changelog's `build-filter` always garbage-collects between builds, so it's only safe
to run here, before the cache is restored — running it after would risk collecting away the cache that
was just restored (a merely-*restored* store path isn't necessarily a GC root).

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
- Show build times in GitHub Actions summaries alongside the cache stats
