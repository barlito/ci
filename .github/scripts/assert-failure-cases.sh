#!/usr/bin/env bash
# Dispatches a workflow_dispatch workflow on the PR branch, then asserts each case job failed with the expected log text.
# Usage: assert-failure-cases.sh <workflow-file> <case>::<expected log text>...
set -euo pipefail

workflow=$1
shift
: "${GH_REPO:?}" "${BRANCH:?}" "${GH_TOKEN:?}"

started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
gh workflow run "$workflow" --ref "$BRANCH"

run_id=""
for _ in $(seq 1 24); do
    run_id=$(gh run list --workflow "$workflow" --branch "$BRANCH" --event workflow_dispatch --limit 10 \
        --json databaseId,createdAt --jq "[.[] | select(.createdAt >= \"$started\")] | last | .databaseId // empty")
    [ -n "$run_id" ] && break
    sleep 5
done
[ -n "$run_id" ] || { echo "::error::dispatched run not found"; exit 1; }
echo "Dispatched run $run_id"

for _ in $(seq 1 120); do
    [ "$(gh run view "$run_id" --json status --jq .status)" = completed ] && break
    sleep 10
done
[ "$(gh run view "$run_id" --json status --jq .status)" = completed ] || { echo "::error::run $run_id did not complete in time"; exit 1; }

jobs=$(gh api "repos/$GH_REPO/actions/runs/$run_id/jobs" --paginate --jq '.jobs[] | [.id, .name, .conclusion] | @tsv')
status=0
for spec in "$@"; do
    name=${spec%%::*}
    expected=${spec#*::}
    row=$(awk -F'\t' -v n="$name" '$2 == n || index($2, n " / ") == 1 { print; exit }' <<<"$jobs")
    if [ -z "$row" ]; then echo "::error::case $name not found"; status=1; continue; fi
    id=$(cut -f1 <<<"$row")
    conclusion=$(cut -f3 <<<"$row")
    if [ "$conclusion" != failure ]; then echo "::error::case $name concluded $conclusion, expected failure"; status=1; continue; fi
    if [ -n "$expected" ] && ! gh api "repos/$GH_REPO/actions/jobs/$id/logs" | grep -qF -- "$expected"; then
        echo "::error::case $name log lacks: $expected"
        status=1
        continue
    fi
    echo "case $name failed as expected"
done
exit "$status"
