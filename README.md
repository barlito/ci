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

| Workflow | Caller trigger | Status |
|---|---|---|
| `docker-release.yaml` | `release: [published]` | planned |
| `swarm-deploy.yaml` | `workflow_dispatch`, run with `--ref vX.Y.Z` | planned |
| `swarm-rollback.yaml` | `workflow_dispatch` on the default branch | planned |
| `image-scan.yaml` | any | planned |
| `docker-check.yaml` | `pull_request` | planned |
| `php-ci.yaml` | `pull_request`, `push` | planned |

## Consumer contract

Prerequisites:

- GitHub releases tagged `vX.Y.Z[-suffix]` on the default branch.
- A `Dockerfile` with named targets.
- A `docker-compose-prod.yml` that uses `${TAG}` for images and `<name>_${CONFIG_VERSION}` for Swarm configs.

### Make targets

| Target | Required | Called by | Semantics |
|---|---|---|---|
| `deploy.prod` | yes | `swarm-deploy` (`full: true`) | Full `docker stack deploy`, idempotent, creates the stack on first deploy, never `stack rm`, fails if not converged |
| `deploy.update` | yes (may alias `deploy.prod` for a simple stack) | `swarm-deploy` (`full: false`) | Rolling image update: backup, drain, update, migrate, assert, smoke, prune as needed |
| `rollback` | if `swarm-rollback` is used | `swarm-rollback` | `TAG=` required, `RESTORE=` optional |
| `deploy.recover` | no | `swarm-deploy` on failure | Restore a sane state (rescale workers...); skipped if missing |
| `deploy.ci`, `docker.undeploy.ci` | PHP | `php-ci` | CI stack |

Environment guaranteed to make: `DOCKER_HOST=ssh://...`, `TAG`, and the secrets listed in the `env-secrets` input.

`deploy.update` does not reapply environment variables nor networks: use a `full` deploy when they change.

### Variables and secrets

Set on the `production` environment of the consumer repository (repository level as a fallback):

| Kind | Name | Used by |
|---|---|---|
| variable | `SERVER_HOST` | deploy, rollback |
| secret | `SERVER_USERNAME`, `SERVER_PORT` | deploy, rollback |
| secret | `SERVER_HOST_KEY` (a `known_hosts` line of the server ed25519 key) | deploy, rollback |
| secret | `SSH_PRIVATE_KEY` | deploy, rollback |
| secret | `DOCKER_HUB_USERNAME`, `DOCKER_HUB_READ_ONLY_ACCESS_TOKEN` | deploy, rollback |
| secret | `DOCKER_HUB_READ_WRITE_DELETE_ACCESS_TOKEN` | release only |

No server information is stored in this repository. Variables are printed in clear in the logs of public repositories, hence the server user, port and host key being secrets.

### Deploy caller

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
    secrets: inherit
```

The deploy job declares the `environment`, so GitHub records a Deployment (tag, commit, run, status) for each run. Only the secrets listed in `env-secrets` are exported to make.

Stacks without a build (`traefik-base`...) use `swarm-deploy` with `images: ""`, `require-tag: false` and a dedicated `target`, plus `docker-check`.

## Development

```bash
make lint   # actionlint + shellcheck, zizmor, SHA pinning check (set GH_TOKEN for zizmor online audits)
```

- Third-party actions are pinned by full commit SHA with a version comment; Dependabot groups their updates weekly. The lint images are pinned by digest in the `Makefile`.
- Each workflow has a `test-<name>.yaml` that calls it locally (`uses: ./.github/workflows/<name>.yaml`) against a fixture in `tests/fixtures/`.
- `tests/fixtures/app` is a minimal app implementing the whole make contract. Each target records its call in `$TRACE_FILE` and fails when listed in `FAIL_TARGETS`.
