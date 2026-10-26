#!/bin/bash
set -euo pipefail

cli_image="${1:?CLI image required}"
ssh_image="${2:?SSH sidecar image required}"
fixture="$(mktemp -d)"
cli_container="workspace-cli-smoke-$$"
ssh_container="workspace-ssh-smoke-$$"
cleanup() {
    local result=$?
    if [ "$result" -ne 0 ]; then
        docker logs --tail 100 "$cli_container" >&2 || true
        docker logs --tail 100 "$ssh_container" >&2 || true
    fi
    docker rm -f "$ssh_container" "$cli_container" >/dev/null 2>&1 || true
    docker run --rm --entrypoint chown -v "$fixture:/fixture" "$ssh_image" \
        -R "$(id -u):$(id -g)" /fixture >/dev/null 2>&1 || true
    rm -rf "$fixture" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$fixture/home" "$fixture/state/ssh" "$fixture/socket" "$fixture/keys"
mkdir -p "$fixture/home/.config/fish"
printf '%s\n' 'set -gx WORKSPACE_SMOKE_CONFIG loaded' > "$fixture/home/.config/fish/config.fish"
printf '%s\n' 'set -g status off' > "$fixture/home/.tmux.conf"
ssh-keygen -q -t ed25519 -N '' -f "$fixture/client"
cp "$fixture/client.pub" "$fixture/keys/authorized_keys"
chmod 0444 "$fixture/keys/authorized_keys"
# Kubernetes projects root-owned files beneath a mode 1777 volume root.
docker run --rm --entrypoint bash -v "$fixture/keys:/keys" "$ssh_image" \
    -c 'chown 0:0 /keys /keys/authorized_keys; chmod 1777 /keys'

identity=(
    -e USER_NAME=workspace
    -e CLI_USER_ID="$(id -u)"
    -e CLI_GROUP_ID="$(id -g)"
)
docker run -d --name "$cli_container" \
    "${identity[@]}" \
    -e HOME=/work-home \
    -e CLI_WORKSPACE_MODE=1 \
    -e CLI_WORKSPACE_TMUX=1 \
    -e CODEX_HOME=/work-state/codex \
    -v "$fixture/home:/work-home" \
    -v "$fixture/state:/work-state" \
    -v "$fixture/socket:/run/workspace-tmux" \
    "$cli_image" >/dev/null

# The sidecar must fail closed when the authorized_keys mount is absent.
if docker run --rm "${identity[@]}" \
    -v "$fixture/state/ssh:/work-state/ssh" \
    -v "$fixture/socket:/run/workspace-tmux" \
    "$ssh_image" >/dev/null 2>&1; then
    echo 'SSH started without authorized_keys' >&2
    exit 1
fi

docker run -d --name "$ssh_container" -p 127.0.0.1::22 \
    "${identity[@]}" \
    -v "$fixture/state/ssh:/work-state/ssh" \
    -v "$fixture/socket:/run/workspace-tmux" \
    -v "$fixture/keys:/run/workspace-ssh:ro" \
    "$ssh_image" >/dev/null
port="$(docker port "$ssh_container" 22/tcp | sed -n 's/.*://p')"
test -n "$port"
docker exec "$ssh_container" test ! -e /work-state/codex
if docker exec "$ssh_container" touch /run/workspace-ssh/write-probe 2>/dev/null; then
    echo 'SSH public-key mount must be read-only' >&2
    exit 1
fi
ssh_options=(
    -i "$fixture/client"
    -p "$port"
    -o BatchMode=yes
    -o IdentitiesOnly=yes
    -o StrictHostKeyChecking=accept-new
    -o UserKnownHostsFile="$fixture/known_hosts"
    -o ConnectTimeout=5
)

tmux_in_cli() {
    docker exec -u "$(id -u):$(id -g)" \
        "$cli_container" tmux -S /run/workspace-tmux/workspace.sock "$@"
}

for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if tmux_in_cli has-session -t workspace 2>/dev/null &&
       ssh-keyscan -T 2 -p "$port" 127.0.0.1 >/dev/null 2>&1; then
        break
    fi
    if [ "$attempt" -eq 10 ]; then
        docker logs "$cli_container" >&2
        docker logs "$ssh_container" >&2
        exit 1
    fi
    sleep 1
done
ssh-keygen -q -t ed25519 -N '' -f "$fixture/unknown-client"
if ssh -F /dev/null -i "$fixture/unknown-client" -p "$port" \
    -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$fixture/known_hosts" -o ConnectTimeout=5 \
    workspace@127.0.0.1 true \
    >"$fixture/unknown-client.log" 2>&1; then
    echo 'Unregistered SSH key was accepted' >&2
    exit 1
fi
if ! grep -q 'Permission denied (publickey)' "$fixture/unknown-client.log"; then
    cat "$fixture/unknown-client.log" >&2
    exit 1
fi
test "$(tmux_in_cli display-message -p -t workspace:0.0 '#{pane_current_command}')" = fish
test "$(tmux_in_cli show-options -gv status)" = off
test "$(tmux_in_cli show-environment -g CODEX_HOME)" = CODEX_HOME=/work-state/codex
first_id="$(tmux_in_cli display-message -p -t workspace '#{session_id}')"
printf '%s\n' /work-home /work-state/codex /work-state/pi loaded "$(id -u)" /work-home > "$fixture/expected"
# The expected output is assembled by fish, so its presence is not just input echo.
# shellcheck disable=SC2016 # Expand these variables in the remote fish pane.
probe_command='printf "%s\n" "$HOME" "$CODEX_HOME" "$PI_CODING_AGENT_DIR" "$WORKSPACE_SMOKE_CONFIG" (id -u) (pwd) > "$HOME/ssh-smoke"; cd "$HOME/.config"; and test -w "$PI_CODING_AGENT_DIR"; and printf "workspace-%s-ok\n" stdio'

for _ in 1 2; do
    python3 tests/ssh-pty-client.py "$probe_command" workspace-stdio-ok \
        ssh -tt "${ssh_options[@]}" workspace@127.0.0.1 &
    client_pid=$!
    attached=false
    for attempt in 1 2 3 4 5; do
        if [ -n "$(tmux_in_cli list-clients -t workspace -F '#{client_name}')" ]; then
            attached=true
            break
        fi
        sleep 1
    done
    if [ "$attached" != true ]; then
        docker logs "$ssh_container" >&2
        exit 1
    fi
    wait "$client_pid"
    cmp "$fixture/expected" "$fixture/home/ssh-smoke"
    rm "$fixture/home/ssh-smoke"
    test "$(tmux_in_cli display-message -p -t workspace '#{session_id}')" = "$first_id"
    # Reattach must preserve the pane's working directory after cd.
    printf '%s\n' /work-home /work-state/codex /work-state/pi loaded "$(id -u)" /work-home/.config > "$fixture/expected"
done

# Closing the last pane must allow the next login to create a CLI-side session.
tmux_in_cli kill-session -t '=workspace'
printf '%s\n' /work-home /work-state/codex /work-state/pi loaded "$(id -u)" /work-home > "$fixture/expected"
python3 tests/ssh-pty-client.py "$probe_command" workspace-stdio-ok \
    ssh -tt "${ssh_options[@]}" workspace@127.0.0.1
cmp "$fixture/expected" "$fixture/home/ssh-smoke"
test "$(tmux_in_cli display-message -p -t workspace '#{session_id}')" != "$first_id"
