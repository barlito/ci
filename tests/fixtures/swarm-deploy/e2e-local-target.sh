#!/usr/bin/env bash
# Test-only: turns the reusable job's own runner into the deploy target (sshd, swarm, registry).
# Reachable only through the e2e-local-target input of the swarm workflows, restricted to barlito/ci.
set -euo pipefail

workspace=${GITHUB_WORKSPACE:?}
app=$workspace/tests/fixtures/app
registry=localhost:5000

setup() {
    : "${E2E_SSHD_HOST_KEY:?}" "${SSH_PRIVATE_KEY:?}" "${SERVER_PORT:?}" "${TAG:?}"
    umask 077
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    printf '%s\n' "$E2E_SSHD_HOST_KEY" > "$tmp/host_key"
    sudo install -m 600 -o root -g root "$tmp/host_key" /etc/ssh/e2e_host_key
    printf '%s\n' "$SSH_PRIVATE_KEY" > "$tmp/client_key"
    install -d -m 700 "$HOME/.ssh"
    ssh-keygen -y -f "$tmp/client_key" >> "$HOME/.ssh/authorized_keys"
    # sshd refuses locked accounts when PAM is off
    sudo usermod -p '*' "$(id -un)"
    sudo mkdir -p /run/sshd
    sudo /usr/sbin/sshd -f /dev/null -p "$SERVER_PORT" -h /etc/ssh/e2e_host_key \
        -o ListenAddress=127.0.0.1 -o PasswordAuthentication=no -o UsePAM=no \
        -o AllowUsers="$(id -un)" -o StrictModes=no -o PidFile=/run/e2e-sshd.pid

    cd "$workspace"
    for version in v1.0.0 v1.1.0; do
        git rev-parse -q --verify "refs/tags/$version" >/dev/null || git tag "$version"
    done

    docker run -d -p 5000:5000 --name registry registry:3@sha256:82f6ff4a7f982960c8aa51617fea3aabc485df6e55cce80d22deb1de36f1bc3c
    timeout 60 sh -c "until curl -fs --max-time 2 http://$registry/v2/ >/dev/null; do sleep 1; done"
    docker swarm init

    for version in v1.0.0 v1.1.0; do
        for target in app worker; do
            docker build -q --target "$target" --build-arg APP_VERSION="$version" -t "$registry/fixture-$target:$version" "$app"
            docker push -q "$registry/fixture-$target:$version"
        done
    done

    # Start from the other version so the deploy under test changes what is served
    seed=v1.0.0
    if [ "$TAG" = v1.0.0 ]; then seed=v1.1.0; fi
    (cd "$app" && TRACE_FILE=/dev/null TAG=$seed make deploy.prod)
}

evidence() {
    echo "E2E-EVIDENCE-BEGIN"
    cat trace.log 2>/dev/null || true
    echo "E2E-SERVED $(timeout 20 make -s -C "$app" fixture.http URL_PATH=health 2>&1 || echo unavailable)"
    echo "E2E-EVIDENCE-END"
}

"${1:?mode}"
