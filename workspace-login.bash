#!/bin/bash
set -euo pipefail

# The SSH sidecar does not execute CLI commands itself. The tmux server and
# its fish panes run in the CLI container and use its home, tools and state.
if [ "$#" -ne 0 ] || [ -z "${SSH_TTY:-}" ]; then
    echo '対話TTYで ssh workspace を使用してください' >&2
    exit 2
fi

export TMUX_TMPDIR=/run/workspace-tmux
unset TMUX TMUX_PANE
tmux_socket=/run/workspace-tmux/workspace.sock
for _ in {1..20}; do
    if tmux -N -S "$tmux_socket" show-options -s >/dev/null 2>&1; then
        # -N prevents accidentally starting a server inside the SSH sidecar.
        exec tmux -N -S "$tmux_socket" new-session -A -s workspace 'fish -l'
    fi
    sleep 1
done
echo 'CLI workspaceのtmux sessionが起動していません' >&2
exit 1
