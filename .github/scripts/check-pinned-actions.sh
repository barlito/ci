#!/usr/bin/env bash
# Fails if a `uses:` reference is neither local (./...) nor pinned to a full commit SHA or image digest.
set -euo pipefail

if [ "$#" -eq 0 ]; then
    set -- .github/workflows
fi

status=0
while IFS= read -r match; do
    ref=$(sed -E 's/^[^:]+:[0-9]+:[[:space:]]*-?[[:space:]]*uses:[[:space:]]*//; s/[[:space:]]+#.*$//; s/["'\'']//g' <<<"$match")
    case "$ref" in
        ./*) continue ;;
        docker://*@sha256:*) continue ;;
    esac
    if ! grep -Eq '^[^@[:space:]]+@[0-9a-f]{40}$' <<<"$ref"; then
        echo "Unpinned reference: ${match}"
        status=1
    fi
done < <(grep -rnE '^[[:space:]]*-?[[:space:]]*uses:' "$@" --include='*.yaml' --include='*.yml' || true)

exit "$status"
