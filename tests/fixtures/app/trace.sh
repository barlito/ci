#!/usr/bin/env sh
# Records a contract target call, then fails it if listed in FAIL_TARGETS.
set -eu

target="$1"
fixture_env=$(env | sed -n 's/^\(FIXTURE_[A-Z0-9_]*\)=.*/\1/p' | sort | paste -sd, -)
printf '%s TAG=%s RESTORE=%s DOCKER_HOST=%s FIXTURE_ENV=%s\n' \
    "$target" "${TAG:-}" "${RESTORE:-}" "${DOCKER_HOST:-}" "$fixture_env" >> "${TRACE_FILE:?}"

case " ${FAIL_TARGETS:-} " in
    *" $target "*) echo "Forced failure of $target" >&2; exit 1 ;;
esac
