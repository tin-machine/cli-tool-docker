#!/bin/bash
set -euo pipefail

user_name="${USER_NAME:-}"
user_id="${CLI_USER_ID:-}"
group_id="${CLI_GROUP_ID:-}"
if [[ ! "$user_name" =~ ^[a-z_][a-z0-9_-]*$ ]] ||
   [[ ! "$user_id" =~ ^[1-9][0-9]*$ ]] ||
   [[ ! "$group_id" =~ ^[1-9][0-9]*$ ]]; then
    echo 'SSH sidecarのuser identityが不正です' >&2
    exit 2
fi
key_file=/run/workspace-ssh/authorized_keys
if [ ! -f "$key_file" ] || [ ! -s "$key_file" ]; then
    echo 'SSH公開鍵Secretがありません' >&2
    exit 2
fi
key_mode="$(stat -L -c %a "$key_file")"
key_owner="$(stat -L -c %u "$key_file")"
if [ "$key_owner" != 0 ] || { [ "$key_mode" != 444 ] && [ "$key_mode" != 400 ]; }; then
    echo 'SSH公開鍵Secretのowner/modeが不正です' >&2
    exit 2
fi
if [ ! -d /run/workspace-tmux ] || [ ! -d /work-state ]; then
    echo 'SSH sidecarの共有volumeがありません' >&2
    exit 2
fi

if group_entry="$(getent group "$group_id")"; then
    group_name="${group_entry%%:*}"
else
    group_name="$user_name"
    groupadd -g "$group_id" "$group_name"
fi
if getent passwd "$user_name" >/dev/null; then
    echo 'SSH sidecarのuser名が既存accountと衝突しています' >&2
    exit 2
fi
useradd_options=()
if getent passwd "$user_id" >/dev/null; then
    useradd_options=(-o)
fi
useradd "${useradd_options[@]}" -M -u "$user_id" -g "$group_name" -d /work-home -s /usr/local/bin/workspace-login "$user_name"
# Password and keyboard-interactive login are disabled below; an unlocked
# shadow account is needed for OpenSSH's public-key account check.
passwd -d "$user_name" >/dev/null

if [ -L /work-state/ssh ]; then
    echo 'SSH host key directoryがsymlinkです' >&2
    exit 2
fi
install -d -m 0700 -o root -g root /work-state/ssh
host_key=/work-state/ssh/ssh_host_ed25519_key
if [ -L "$host_key" ]; then
    echo 'SSH host keyがsymlinkです' >&2
    exit 2
fi
if [ -e "$host_key" ]; then
    if [ ! -f "$host_key" ] || [ "$(stat -c %u "$host_key")" != 0 ] || [ "$(stat -c %a "$host_key")" != 600 ]; then
        echo 'SSH host keyのowner/modeが不正です' >&2
        exit 2
    fi
else
    ssh-keygen -q -t ed25519 -N '' -f "$host_key"
fi
install -d -m 0755 /run/sshd
cat > /run/workspace-sshd_config <<EOF
Port 22
ListenAddress 0.0.0.0
HostKey $host_key
PidFile /run/workspace-sshd.pid
AuthorizedKeysFile none
# Kubernetes Secret projection roots are mode 1777, which StrictModes rejects.
# Read the fixed, read-only public-key file without accepting keys from HOME.
AuthorizedKeysCommand /usr/bin/cat $key_file
AuthorizedKeysCommandUser root
AuthenticationMethods publickey
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PermitRootLogin no
AllowUsers $user_name
UsePAM yes
StrictModes yes
PermitTunnel no
AllowTcpForwarding no
X11Forwarding no
SetEnv LANG=ja_JP.UTF-8
SetEnv LC_ALL=ja_JP.UTF-8
SetEnv TZ=Asia/Tokyo
SetEnv PATH=/opt/tmux/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
/usr/sbin/sshd -t -f /run/workspace-sshd_config
exec /usr/sbin/sshd -D -e -f /run/workspace-sshd_config
