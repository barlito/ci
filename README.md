# ci

Reusable GitHub Actions workflows for Barlito projects: Docker release, Swarm deploy and rollback, image scan, compose check, PHP CI.

The workflows only do the generic plumbing (tag guard, SSH, registry login, image checks, concurrency, environment). Everything project-specific lives in `make` targets of the consumer repository: **make is the contract**, whatever the language.

## Usage

```yaml
jobs:
  deploy:
    uses: barlito/ci/.github/workflows/swarm-deploy.yaml@v1
```

`v1` is a floating major tag moved by `promote.yaml` to every non-prerelease `v1.x.y` release. Pin an exact version (`@v1.2.3`) only temporarily.

| Workflow | Caller trigger | Caller permissions |
|---|---|---|
| `docker-release.yaml` | `release: [published]` | `contents: read`, `packages: write` |
| `swarm-deploy.yaml` | `workflow_dispatch`, run with `--ref vX.Y.Z` | `contents: read`, `deployments: write` |
| `swarm-rollback.yaml` | `workflow_dispatch` on the default branch | `contents: read`, `deployments: write` |
| `image-scan.yaml` | any | `contents: read`, `security-events: write` |
| `docker-check.yaml` | `pull_request` | `contents: read` |
| `php-ci.yaml` | `pull_request`, `push` | `contents: read` |

A caller must grant at least the permissions of the workflow it calls, even when a step ends up skipped (the SARIF upload of `image-scan` on a private repository, for example).

## Consumer contract

Prerequisites:

- GitHub releases tagged `vX.Y.Z[-suffix]` on the default branch.
- A `Dockerfile` with named targets.
- A `docker-compose-prod.yml` that uses `${TAG}` for images and `<name>_${CONFIG_VERSION}` for Swarm configs. `CONFIG_VERSION` is computed and exported by the consumer `Makefile` (a hash of the config files, for example).

### Make targets

| Target | Required | Called by | Semantics |
|---|---|---|---|
| `deploy.prod` | yes | `swarm-deploy` (`full: true`) | Full `docker stack deploy`, idempotent, creates the stack on first deploy, never `stack rm`, fails if not converged |
| `deploy.update` | yes (may alias `deploy.prod` for a simple stack) | `swarm-deploy` (`full: false`) | Rolling image update: backup, drain, update, migrate, assert, smoke, prune as needed |
| `rollback` | if `swarm-rollback` is used | `swarm-rollback` | `TAG=` required, `RESTORE=` optional |
| `deploy.recover` | no | `swarm-deploy` and `swarm-rollback` when make fails, times out or is cancelled | Restore a sane state (rescale workers...); skipped if missing |
| `deploy.ci`, `docker.undeploy.ci` | PHP | `php-ci` | CI stack |

Environment guaranteed to make (including `deploy.recover`): `DOCKER_HOST=ssh://...`, `TAG`, `RESTORE` (`swarm-rollback` only, possibly empty), and the secrets listed in the `env-secrets` input.

Only secrets are exported to make, never variables: a value make needs (a host name for example) must be a secret listed in `env-secrets`. The allowlist is an export hygiene guarantee, not isolation: make runs in the same process tree as the job, which received every inherited secret.

`deploy.update` does not reapply environment variables nor networks: use a `full` deploy when they change.

PHP projects using the production rules of `php-make-rules` need castor: set `castor: true` on `swarm-deploy` and `swarm-rollback`.

### Variables and secrets

Set on the `production` environment of the consumer repository (repository level as a fallback):

| Kind | Name | Used by |
|---|---|---|
| variable | `SERVER_HOST` | deploy, rollback |
| secret | `SERVER_USERNAME`, `SERVER_PORT` | deploy, rollback |
| secret | `SERVER_HOST_KEY` (a `known_hosts` line of the server ed25519 key) | deploy, rollback |
| secret | `SSH_PRIVATE_KEY` | deploy, rollback |
| secret | `DOCKER_HUB_USERNAME`, `DOCKER_HUB_READ_ONLY_ACCESS_TOKEN` | deploy, rollback (always logged in, even with `images: ""`), php-ci |

`php-ci` has no environment: its `DOCKER_HUB_*` secrets must be set at repository level, otherwise the login is skipped.

The `production` environment deployment branch rule must allow the `v*` tags (deploy) and the default branch (rollback).

The release job has no environment: set `DOCKER_HUB_USERNAME` and `DOCKER_HUB_READ_WRITE_DELETE_ACCESS_TOKEN` at repository level for `docker-release`.

No server information is stored in this repository. Variables are printed in clear in the logs of public repositories, hence the server user, port and host key being secrets.

## Workflows

All of them take `secrets: inherit`; only the secrets named above are read.

### docker-release

Builds and pushes one image per target, tagged with the release tag. `latest` moves only for the highest stable tag of the repository, decided again right before it is moved. Runs are serialized per tag, so concurrent releases of different tags are all built.

| Input | Default | |
|---|---|---|
| `images` | required | JSON array of `{"name","target"}`, the first image is the main one |
| `context` | `.` | Build context |
| `dockerfile` | `Dockerfile` | Path relative to the repository root |
| `namespace` | `barlito` | Prepended to image names without a slash |
| `registry` | `docker.io` | |
| `cache` | `ghcr` | `ghcr`, `gha` or `none` |
| `platforms` | `linux/amd64` | |
| `build-args` | | Multiline `KEY=VALUE`, `APP_VERSION` is always added |
| `sbom`, `provenance` | `true` | |

Outputs: `tag`, and `digests` (JSON object mapping each target to its digest).

```yaml
name: release

on:
  release:
    types: [published]

permissions:
  contents: read
  packages: write

jobs:
  release:
    uses: barlito/ci/.github/workflows/docker-release.yaml@v1
    with:
      images: '[{"name":"my-app","target":"app"},{"name":"my-app-worker","target":"worker"}]'
    secrets: inherit
```

### swarm-deploy

Validates the tag and the images, opens an SSH connection to the server and runs `make deploy.update` (or `make deploy.prod` with `full: true`), then `make deploy.recover` in its own step when make fails, times out or is cancelled. `timeout-minutes` bounds the make step, the recovery step has its own 5 minutes.

| Input | Default | |
|---|---|---|
| `full` | `false` | Run `deploy.prod` instead of `deploy.update` |
| `environment` | `production` | GitHub environment of the job |
| `images` | | Space-separated image references without tag, each `<ref>:<TAG>` must exist |
| `env-secrets` | | Space-separated secret names exported to make |
| `castor` | `false` | Install castor before running make |
| `submodules` | `true` | |
| `working-directory` | `.` | Directory where make runs |
| `target` | | Overrides the make target |
| `require-tag` | `true` | `false` only accepted without images |
| `timeout-minutes` | `20` | Timeout of the make step |

```yaml
name: deploy

on:
  workflow_dispatch:
    inputs:
      re-deploy:
        type: boolean
        default: false

permissions:
  contents: read
  deployments: write

jobs:
  deploy:
    uses: barlito/ci/.github/workflows/swarm-deploy.yaml@v1
    with:
      full: ${{ inputs.re-deploy }}
      images: barlito/my-app barlito/my-app-worker
      env-secrets: DB_PASSWORD APP_SECRET
      castor: true
    secrets: inherit
```

The deploy job declares the `environment`, so GitHub records a Deployment (tag, commit, run, status) for each run. Only the secrets listed in `env-secrets` are exported to make.

Stacks without a build (`traefik-base`...) use `swarm-deploy` with `images: ""`, `require-tag: false` and a dedicated `target`, plus `docker-check`.

### swarm-rollback

Runs `make rollback TAG=<tag> [RESTORE=<restore>]`, only from the default branch. It shares its concurrency group with `swarm-deploy`.

Inputs: `tag` (required), `restore`, and the same `environment`, `images`, `env-secrets`, `castor`, `submodules`, `working-directory`, `target` and `timeout-minutes` as `swarm-deploy`.

```yaml
name: rollback

on:
  workflow_dispatch:
    inputs:
      tag:
        type: string
        required: true
      restore-database:
        type: boolean
        default: false

permissions:
  contents: read
  deployments: write

jobs:
  rollback:
    uses: barlito/ci/.github/workflows/swarm-rollback.yaml@v1
    with:
      tag: ${{ inputs.tag }}
      restore: ${{ inputs.restore-database && '1' || '' }}
      images: barlito/my-app barlito/my-app-worker
      env-secrets: DB_PASSWORD APP_SECRET
      castor: true
    secrets: inherit
```

### image-scan

Builds an image and scans it with Trivy. Findings go to code scanning (SARIF) on public repositories, and to the job summary and log.

| Input | Default | |
|---|---|---|
| `dockerfile` | `Dockerfile` | Path relative to the repository root |
| `target` | | Build target, empty builds the last stage |
| `context` | `.` | |
| `severity` | `CRITICAL,HIGH` | |
| `ignore-unfixed` | `true` | |
| `trivyignore` | `.trivyignore` | Ignore file relative to the repository root, honored when it exists (the path with `.yaml` appended is also tried) |
| `fail-on-findings` | `false` | |

### docker-check

Builds the given targets without pushing and validates each compose file on its own: override files that only make sense merged need `docker stack config -c a -c b` in the caller.

| Input | Default | |
|---|---|---|
| `dockerfile` | `Dockerfile` | Path relative to the repository root |
| `targets` | | Space-separated build targets, empty skips the build |
| `context` | `.` | |
| `compose-files` | `docker-compose-prod.yml` | Space-separated |
| `compose-env` | | Multiline `KEY=VALUE` dummy values for interpolation |

### php-ci

Starts the CI stack (`make deploy.ci`), runs every check then every test target, reports all failures, and always runs `make docker.undeploy.ci`.

| Input | Default | |
|---|---|---|
| `checks` | `cs_fixer.dry_run phpcs phpstan` | Space-separated make targets |
| `tests` | `phpunit` | Space-separated make targets |
| `castor` | `true` | |
| `cache-paths` | | Extra paths to cache, one per line |

## Development

```bash
make lint   # actionlint + shellcheck, zizmor, SHA pinning check (set GH_TOKEN for zizmor online audits)
```

- Third-party actions are pinned by full commit SHA with a version comment; Dependabot groups their updates weekly. The lint images are pinned by digest in the `Makefile`.
- Each workflow has a `test-<name>.yaml` that calls it locally (`uses: ./.github/workflows/<name>.yaml`) against a fixture in `tests/fixtures/`.
- `tests/fixtures/app` is a minimal app implementing the whole make contract. Each target records its call in `$TRACE_FILE` and fails when listed in `FAIL_TARGETS`.
