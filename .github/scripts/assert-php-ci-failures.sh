#!/usr/bin/env bash
# Dispatches test-php-ci-failures on BRANCH and checks each case failed as expected.
set -euo pipefail

: "${REPO:?}" "${BRANCH:?}"
workflow=test-php-ci-failures.yaml

# workflow_dispatch only resolves workflows present on the default branch
default_branch=$(gh api "repos/$REPO" --jq .default_branch)
if ! gh api "repos/$REPO/contents/.github/workflows/$workflow?ref=$default_branch" >/dev/null 2>&1; then
  echo "::warning::$workflow is not on $default_branch yet, failure cases skipped"
  exit 0
fi

since=$(date -u +%Y-%m-%dT%H:%M:%SZ)

gh workflow run "$workflow" --repo "$REPO" --ref "$BRANCH"

run_id=""
for _ in $(seq 1 12); do
  sleep 5
  run_id=$(gh api "repos/$REPO/actions/workflows/$workflow/runs" -f event=workflow_dispatch -f branch="$BRANCH" -f created=">=$since" --jq '.workflow_runs[0].id // empty')
  [ -n "$run_id" ] && break
done
[ -n "$run_id" ] || { echo "::error::Dispatched run not found"; exit 1; }
echo "Run: https://github.com/$REPO/actions/runs/$run_id"

for _ in $(seq 1 60); do
  status=$(gh api "repos/$REPO/actions/runs/$run_id" --jq .status)
  [ "$status" = completed ] && break
  sleep 15
done
[ "$status" = completed ] || { echo "::error::Dispatched run did not complete in time"; exit 1; }

status=0
check_case() {
  local name=$1 expected=$2 job_id conclusion logs
  read -r job_id conclusion < <(gh api "repos/$REPO/actions/runs/$run_id/jobs" --paginate \
    --jq ".jobs[] | select(.name | startswith(\"$name /\")) | \"\(.id) \(.conclusion)\"")
  if [ "$conclusion" != failure ]; then
    echo "::error::$name concluded $conclusion, expected failure"; status=1; return
  fi
  logs=$(gh api --allow-escape-sequences "repos/$REPO/actions/jobs/$job_id/logs")
  for text in "$expected" "FIXTURE docker.undeploy.ci executed"; do
    if ! grep -qF "$text" <<<"$logs"; then
      echo "::error::$name logs lack: $text"; status=1; return
    fi
  done
  echo "$name: failed as expected"
}

check_case failing-check "Failed checks: check.fail"
check_case failing-test "Failed tests: test.fail"
exit "$status"
