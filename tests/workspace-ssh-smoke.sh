#!/bin/bash
set -euo pipefail

image="${1:?image reference required}"
fixture="$(mktemp -d)"
container="workspace-ssh-smoke-$$"
cleanup() {
    docker rm -f "$container" >/dev/null 2>&1 || true
    # The host key directory is root-owned inside the container; CI runner cleanup owns the fixture.
    rm -rf "$fixture" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$fixture/home" "$fixture/state" "$fixture/keys"
ssh-keygen -q -t ed25519 -N '' -f "$fixture/client"
cp "$fixture/client.pub" "$fixture/keys/authorized_keys"
chmod 0444 "$fixture/keys/authorized_keys"
# Match Kubernetes Secret projection ownership without requiring runner sudo.
docker run --rm --entrypoint chown -v "$fixture/keys:/keys" "$image" 0:0 /keys/authorized_keys

workspace_env=(
    -e HOME=/work-home
    -e USER_NAME=workspace
    -e CLI_USER_ID="$(id -u)"
    -e CLI_GROUP_ID="$(id -g)"
    -e CLI_WORKSPACE_MODE=1
    -e CLI_WORKSPACE_SSH=1
    -e CODEX_HOME=/work-state/codex
    -v "$fixture/home:/work-home"
    -v "$fixture/state:/work-state"
)

# The SSH opt-in must fail closed without an authorized_keys Secret mount.
if docker run --rm "${workspace_env[@]}" "$image" >/dev/null 2>&1; then
    echo 'SSH started without authorized_keys' >&2
    exit 1
fi

docker run -d --name "$container" -p 127.0.0.1::22 \
    "${workspace_env[@]}" -v "$fixture/keys:/run/workspace-ssh:ro" \
    "$image" >/dev/null
port="$(docker port "$container" 22/tcp | sed -n 's/.*://p')"
test -n "$port"
ssh_options=(
    -i "$fixture/client"
    -p "$port"
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o UserKnownHostsFile="$fixture/known_hosts"
    -o ConnectTimeout=5
)

for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if ssh "${ssh_options[@]}" workspace@127.0.0.1 'test "$CODEX_HOME" = /work-state/codex && test "$(id -u)" = '"$(id -u)" >/dev/null 2>&1; then
        break
    fi
    if [ "$attempt" -eq 10 ]; then
        docker logs "$container" >&2
        exit 1
    fi
    sleep 1
done

# No remote command: the login shell must attach the named tmux session.
timeout 4 ssh -tt "${ssh_options[@]}" workspace@127.0.0.1 </dev/null >"$fixture/first.log" 2>&1 || test "$?" -eq 124
first_id="$(ssh "${ssh_options[@]}" workspace@127.0.0.1 'tmux display-message -p -t workspace "#{session_id}"')"
test -n "$first_id"
timeout 4 ssh -tt "${ssh_options[@]}" workspace@127.0.0.1 </dev/null >"$fixture/second.log" 2>&1 || test "$?" -eq 124
second_id="$(ssh "${ssh_options[@]}" workspace@127.0.0.1 'tmux display-message -p -t workspace "#{session_id}"')"
test "$first_id" = "$second_id"
ssh "${ssh_options[@]}" workspace@127.0.0.1 'tmux kill-session -t workspace'
