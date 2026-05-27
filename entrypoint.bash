#!/bin/bash

echo '[entrypoint] 開始'
# デフォルトのUIDとGID（環境変数が無ければ id から取得）
USER_ID="${UID:-$(id -u)}"
GROUP_ID="${GID:-$(id -g)}"
USER_NAME="${USER_NAME:-${USER:-customuser}}"
HOME_DIR="$HOME"
GROUP_NAME="$USER_NAME"
DOCKER_SOCK_GID="${DOCKER_SOCK_GID:-}"

# ロケール設定（デフォルトは ja_JP.UTF-8、環境変数があればそれを使用）
LOCALE_LANG="${LANG:-ja_JP.UTF-8}"
LOCALE_LANGUAGE="${LANGUAGE:-ja_JP.UTF-8}"
LOCALE_LC_ALL="${LC_ALL:-ja_JP.UTF-8}"

# タイムゾーン設定（デフォルトは Asia/Tokyo、環境変数があればそれを使用）
TIMEZONE="${TZ:-Asia/Tokyo}"

# ロケール環境変数を設定
export LANG="$LOCALE_LANG"
export LANGUAGE="$LOCALE_LANGUAGE"
export LC_ALL="$LOCALE_LC_ALL"

# タイムゾーン環境変数を設定
export TZ="$TIMEZONE"

# アカウント操作が可能か判定（root かつ /etc/{passwd,group} に書き込みできるか）
CAN_MANAGE_ACCOUNTS=1
if [ "$(id -u)" -ne 0 ] || [ ! -w /etc/passwd ] || [ ! -w /etc/group ]; then
    CAN_MANAGE_ACCOUNTS=0
fi

# shell.bashから起動した場合、下記の情報はsudo nerdctl logs -f <コンテナID> で確認可能
cat <<EOF
[entrypoint] コンテナの調整をしています
  USER_ID: $USER_ID
  GROUP_ID: $GROUP_ID
  USER_NAME: $USER_NAME
  HOME_DIR: $HOME_DIR
  GROUP_NAME: $GROUP_NAME
  DOCKER_SOCK_GID: ${DOCKER_SOCK_GID}
  LOCALE_LANG: $LOCALE_LANG
  LOCALE_LANGUAGE: $LOCALE_LANGUAGE
  LOCALE_LC_ALL: $LOCALE_LC_ALL
  TIMEZONE: $TIMEZONE
  CAN_MANAGE_ACCOUNTS: $CAN_MANAGE_ACCOUNTS
EOF

add_user_to_gid_group() {
    local gid="$1"
    local base_group_name="$2"
    local target_group=""

    if [ -z "$gid" ]; then
        return
    fi
    if [[ ! "$gid" =~ ^[0-9]+$ ]]; then
        echo "[entrypoint] WARN: ${base_group_name} 用 GID が数値ではないためスキップします: ${gid}" >&2
        return
    fi

    target_group="$(getent group "$gid" | cut -d: -f1)"
    if [ -z "$target_group" ]; then
        target_group="$base_group_name"
        if getent group "$target_group" >/dev/null 2>&1; then
            target_group="${base_group_name}-${gid}"
        fi

        if ! groupadd -g "$gid" "$target_group" 2>/tmp/groupadd-"${base_group_name}".log; then
            echo "[entrypoint] WARN: ${base_group_name} group の作成に失敗しました: $(cat /tmp/groupadd-"${base_group_name}".log)" >&2
            return
        fi
    fi

    if ! usermod -a -G "$target_group" "${USER_NAME}" 2>/tmp/usermod-"${base_group_name}".log; then
        echo "[entrypoint] WARN: ${USER_NAME} の ${target_group} group 追加に失敗しました: $(cat /tmp/usermod-"${base_group_name}".log)" >&2
    fi
}

# グループ・ユーザー作成
if [ "$CAN_MANAGE_ACCOUNTS" -eq 1 ]; then
    existing_users="$(getent passwd "${USER_ID}" | cut -d: -f1 | tr '\n' ' ')"
    useradd_opts=()
    if [ -n "$existing_users" ] && ! id "${USER_NAME}" >/dev/null 2>&1; then
        echo "[entrypoint] WARN: UID ${USER_ID} は既に ${existing_users}に割り当て済みのため、${USER_NAME} を同じUIDのログイン名として追加します" >&2
        useradd_opts=(-o)
    fi

    existing_group="$(getent group "${GROUP_ID}" | cut -d: -f1)"
    if [ -n "$existing_group" ]; then
        GROUP_NAME="$existing_group"
    else
        if ! groupadd -g "${GROUP_ID}" "${USER_NAME}" 2>/tmp/groupadd.log; then
            echo "[entrypoint] WARN: groupadd に失敗しました: $(cat /tmp/groupadd.log)" >&2
            CAN_MANAGE_ACCOUNTS=0
        fi
    fi

    if [ "$CAN_MANAGE_ACCOUNTS" -eq 1 ] && ! id "${USER_NAME}" >/dev/null 2>&1; then
        if ! useradd "${useradd_opts[@]}" -M -s /bin/bash -u "${USER_ID}" -g "${GROUP_NAME}" -d "${HOME_DIR}" "${USER_NAME}" 2>/tmp/useradd.log; then
            echo "[entrypoint] WARN: useradd に失敗しました: $(cat /tmp/useradd.log)" >&2
            CAN_MANAGE_ACCOUNTS=0
        fi
    elif [ "$CAN_MANAGE_ACCOUNTS" -eq 1 ]; then
        current_uid="$(id -u "${USER_NAME}")"
        if [ "${current_uid}" != "${USER_ID}" ]; then
            echo "[entrypoint] WARN: ${USER_NAME} ユーザーは既に存在しますが UID が ${current_uid} のため、要求された UID ${USER_ID} には変更しません" >&2
        fi
    fi

    # シリアルポート用の dialout グループを付与（ユーザーが存在する場合のみ）
    if id "${USER_NAME}" >/dev/null 2>&1; then
        for admin_group in sudo admin; do
            if id -nG "${USER_NAME}" | tr ' ' '\n' | grep -qx "${admin_group}"; then
                if ! gpasswd -d "${USER_NAME}" "${admin_group}" 2>/tmp/gpasswd.log; then
                    echo "[entrypoint] WARN: ${admin_group} グループからの削除に失敗しました: $(cat /tmp/gpasswd.log)" >&2
                fi
            fi
        done

        if ! usermod -a -G dialout "${USER_NAME}" 2>/tmp/usermod.log; then
            echo "[entrypoint] WARN: dialout グループへの追加に失敗しました: $(cat /tmp/usermod.log)" >&2
        fi

        add_user_to_gid_group "$DOCKER_SOCK_GID" docker-host
    else
        echo "[entrypoint] WARN: ${USER_NAME} ユーザーが存在しないため、dialout 追加をスキップします" >&2
    fi
else
    echo "[entrypoint] WARN: /etc/passwd や /etc/group を変更できないため、ユーザー作成をスキップします" >&2
fi

# 所有権変更のヘルパー
maybe_chown() {
    local path="$1"
    if [ ! -e "$path" ]; then
        return
    fi
    if ! chown -R "${USER_ID}:${GROUP_ID}" "$path" 2>/tmp/chown.log; then
        echo "[entrypoint] WARN: ${path} の所有権変更に失敗しました: $(cat /tmp/chown.log)" >&2
    fi
}

if [ "$CAN_MANAGE_ACCOUNTS" -eq 1 ]; then
    maybe_chown /usr/local/aqua/
    maybe_chown /usr/local/lib/node_modules/
fi

# 指定したユーザーとしてコマンドを実行
# 引数が無ければ tail -F /dev/null を実行
if [ $# -eq 0 ]; then
    set -- tail -F /dev/null
fi

# 期待するユーザーが存在していれば gosu、無ければ現在のユーザーで実行
if id "${USER_NAME}" >/dev/null 2>&1; then
    exec gosu "${USER_NAME}" "$@"
fi

echo "[entrypoint] WARN: ${USER_NAME} ユーザーが存在しないため、現在のユーザーで実行します" >&2
exec "$@"
