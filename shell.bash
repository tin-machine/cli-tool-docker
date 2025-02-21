#!/bin/bash

# コンテナ管理ツールを決定
if command -v nerdctl >/dev/null 2>&1; then
    CONTAINER_CMD="sudo nerdctl"
elif command -v docker >/dev/null 2>&1; then
    CONTAINER_CMD="docker"
else
    echo "Error: nerdctl も docker も見つかりません。" >&2
    exit 1
fi

# 設定: 使用するコンテナ名とイメージ
CONTAINER_NAME="cli-tool-docker"
IMAGE_NAME="ghcr.io/tin-machine/cli-tool-docker"
SHELL_CMD="fish"

# 実行中のコンテナIDを取得
CONTAINER_ID=$($CONTAINER_CMD ps -q -f "name=${CONTAINER_NAME}" | head -n 1)

if [ -z "$CONTAINER_ID" ]; then
    echo "コンテナが見つかりません。新しく起動します..."
    stdbuf -oL $CONTAINER_CMD \
      run \
        --network host \
        --ipc shareable \
        --volume $HOME:$HOME \
        --env HOME=${HOME} \
        --env UID=$(id -u) \
        --env GID=$(id -g) \
        --env USER_NAME=$(whoami) \
        -w ${HOME} \
        --privileged \
        -d \
        $( [ "$CONTAINER_CMD" = "nerdctl" ] && echo "--init" ) \
        "$IMAGE_NAME:latest"

    # コンテナIDを再取得
    sleep 5
    CONTAINER_ID=$($CONTAINER_CMD ps -q -f "name=${CONTAINER_NAME}" | head -n 1)
fi

# シェルを実行
$CONTAINER_CMD exec -it --env TERM=${TERM} --user ${UID}:${GID} "$CONTAINER_ID" "$SHELL_CMD"
