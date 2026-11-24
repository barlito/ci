#!/usr/bin/env bash
# Dispatches a workflow_dispatch workflow on the PR branch, then asserts each case job failed with the expected log text.
# Usage: assert-failure-cases.sh <workflow-file> <max-wait-seconds> <case>::<expected log text>...
set -euo pipefail

workflow=$1
max_wait=$2
shift 2
: "${GH_REPO:?}" "${BRANCH:?}" "${GH_TOKEN:?}"

list_runs() {
    gh run list --workflow "$workflow" --branch "$BRANCH" --event workflow_dispatch --limit 50 --json databaseId --jq '.[].databaseId' 2>/dev/null || true
}

before=$(list_runs)
gh workflow run "$workflow" --ref "$BRANCH"

run_id=""
for _ in $(seq 1 36); do
    sleep 5
    run_id=$(comm -13 <(sort <<<"$before") <(list_runs | sort) | sort -n | tail -1)
    [ -n "$run_id" ] && break
done
[ -n "$run_id" ] || { echo "::error::dispatched run not found"; exit 1; }
echo "Dispatched run $run_id"

deadline=$((SECONDS + max_wait))
status=""
while [ "$SECONDS" -lt "$deadline" ]; do
    status=$(gh run view "$run_id" --json status --jq .status 2>/dev/null || true)
    [ "$status" = completed ] && break
    sleep 10
done
[ "$status" = completed ] || { echo "::error::run $run_id did not complete within ${max_wait}s"; exit 1; }

jobs=$(gh api --method GET "repos/$GH_REPO/actions/runs/$run_id/jobs" --paginate --jq '.jobs[] | [.id, .name, .conclusion] | @tsv')
failed=0
for spec in "$@"; do
    name=${spec%%::*}
    expected=${spec#*::}
    row=$(awk -F'\t' -v n="$name" '$2 == n || index($2, n " / ") == 1 { print; exit }' <<<"$jobs")
    if [ -z "$row" ]; then echo "::error::case $name not found"; failed=1; continue; fi
    id=$(cut -f1 <<<"$row")
    conclusion=$(cut -f3 <<<"$row")
    if [ "$conclusion" != failure ]; then echo "::error::case $name concluded $conclusion, expected failure"; failed=1; continue; fi
    if [ -n "$expected" ]; then
        log=$(gh api --allow-escape-sequences "repos/$GH_REPO/actions/jobs/$id/logs")
        if ! grep -qF -- "$expected" <<<"$log"; then
            echo "::error::case $name log lacks: $expected"
            failed=1
            continue
        fi
    fi
    echo "case $name failed as expected"
done
exit "$failed"
