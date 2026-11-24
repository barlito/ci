#!/usr/bin/env bash
# Records which contract secrets and tools are visible to make, next to the app fixture trace.
set -euo pipefail

exported=$(env | cut -d= -f1 | grep -E '^(SERVER_[A-Z_]+|SSH_PRIVATE_KEY|DOCKER_HUB_[A-Z_]+|github_token|SECRETS_JSON|ENV_SECRETS|OPTIONAL_ENV_SECRETS)$' | sort | paste -sd, - || true)
castor=no
if command -v castor >/dev/null; then castor=yes; fi
optional=""
for name in DOCKER_HUB_READ_ONLY_ACCESS_TOKEN E2E_OPT_MISSING; do
  if [ -n "${!name+x}" ]; then
    value=${!name}
    optional+="${optional:+,}$name:${#value}"
  fi
done
printf '%s exported=%s castor=%s%s\n' "$1" "$exported" "$castor" "${optional:+ optional=$optional}" >> "${TRACE_FILE:?}"
