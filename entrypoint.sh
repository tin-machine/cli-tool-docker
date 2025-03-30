#!/bin/bash

# デフォルトのUIDとGID
USER_ID=${UID:-503}
GROUP_ID=${GID:-1000}
USER_NAME=${USER_NAME:-customuser}
HOME_DIR=$HOME

# グループの作成
if ! getent group ${GROUP_ID} >/dev/null; then
    groupadd -g ${GROUP_ID} ${USER_NAME}
fi

# ユーザーの作成
if ! id -u ${USER_ID} >/dev/null 2>&1; then
    useradd -M -s /bin/bash -u ${USER_ID} -g ${GROUP_ID} -d ${HOME_DIR} ${USER_NAME}
fi

# 指定したユーザーとしてコマンドを実行
# 引数が無ければ tail -F /dev/null を実行
if [ $# -eq 0 ]; then
    set -- tail -F /dev/null
fi
exec stdbuf -oL gosu ${USER_NAME} "$@"
