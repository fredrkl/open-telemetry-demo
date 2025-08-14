# Template Base

This repository is a template for my projects, containing the basic structure
and files I typically use as a starting point.

## Renovate setup

I use a global Renovate setup where I use the
[dependency-updater](https://github.com/fredrkl/depencency-updater) repository
to manage Renovate configuration across all my projects. Simply configure the
self-hosted GH Application and give it access to this repository.

The `renovate.json` file is used to onboard this repo.

## Semantic Release

This uses the
[semantic-release](https://github.com/cycjimmy/semantic-release-action) action.

## Gitmoji

This repository uses [gitmoji](https://gitmoji.dev/) for commit messages. Setup
the repo by running:

```bash
gitmoji -init
```

## Pre-commit hooks

This repository uses [pre-commit](https://pre-commit.com/) to manage git hooks.

To install the hooks, run:

```bash
pre-commit install
```

## Direnv for local development secret management

I use [direnv](https://direnv.net/) to manage local development secrets as
described in the [following blog
post](https://fredrkl.com/blog/local-developer-environment-setup/).

Remember to run `direnv allow` after cloning the repository to enable the
`.envrc` file.
