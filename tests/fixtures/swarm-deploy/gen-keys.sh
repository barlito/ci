#!/usr/bin/env bash
# Generates throwaway SSH material for the e2e local target and writes it as step outputs.
set -euo pipefail

host=${1:?host}
port=${2:?port}
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

ssh-keygen -q -t ed25519 -N '' -C e2e-client -f "$dir/client"
ssh-keygen -q -t ed25519 -N '' -C e2e-host -f "$dir/host"
ssh-keygen -q -t ed25519 -N '' -C e2e-other -f "$dir/other"

emit() {
    printf '%s<<EOF_E2E\n%s\nEOF_E2E\n' "$1" "$2" >> "${GITHUB_OUTPUT:?}"
}

emit client-key "$(cat "$dir/client")"
emit sshd-host-key "$(cat "$dir/host")"
emit host-key-line "[$host]:$port $(cut -d' ' -f1,2 "$dir/host.pub")"
emit wrong-host-key-line "[$host]:$port $(cut -d' ' -f1,2 "$dir/other.pub")"
