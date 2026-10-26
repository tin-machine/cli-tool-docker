#!/bin/bash
set -e
export SHELL=/usr/bin/fish

# sshd はリモート command と SFTP を login shell の -c 引数として渡す。
if [ "$#" -gt 0 ]; then
    exec /bin/bash "$@"
fi

# SSH の対話端末だけを常用 tmux session に接続する。
if [ -n "${SSH_TTY:-}" ]; then
    exec tmux new-session -A -s workspace
fi

exec /usr/bin/fish -l
