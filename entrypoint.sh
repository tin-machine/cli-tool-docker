#!/bin/bash

# デフォルトのUIDとGID
USER_ID="${UID:-503}"
GROUP_ID="${GID:-1000}"
USER_NAME="${USER_NAME:-customuser}"
HOME_DIR="$HOME"

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

# グループ・ユーザー作成
if [ "$CAN_MANAGE_ACCOUNTS" -eq 1 ]; then
    if ! getent group "${GROUP_ID}" >/dev/null; then
        if ! groupadd -g "${GROUP_ID}" "${USER_NAME}" 2>/tmp/groupadd.log; then
            echo "[entrypoint] WARN: groupadd に失敗しました: $(cat /tmp/groupadd.log)" >&2
            CAN_MANAGE_ACCOUNTS=0
        fi
    fi

    if [ "$CAN_MANAGE_ACCOUNTS" -eq 1 ] && ! id -u "${USER_ID}" >/dev/null 2>&1; then
        if ! useradd -M -s /bin/bash -u "${USER_ID}" -g "${GROUP_ID}" -d "${HOME_DIR}" "${USER_NAME}" 2>/tmp/useradd.log; then
            echo "[entrypoint] WARN: useradd に失敗しました: $(cat /tmp/useradd.log)" >&2
            CAN_MANAGE_ACCOUNTS=0
        fi
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
