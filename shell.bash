#!/bin/bash

exec 2> ~/error.log

# コンテナ管理ツールを決定
if command -v docker >/dev/null 2>&1; then
    CONTAINER_CMD="docker"
elif command -v nerdctl >/dev/null 2>&1; then
    CONTAINER_CMD="sudo nerdctl"
else
    echo "Error: nerdctl も docker も見つかりません。" >&2
    exit 1
fi

# 設定: 使用するコンテナ名とイメージ
CONTAINER_NAME="cli-tool-docker"
# IMAGE_NAME="ghcr.io/tin-machine/cli-tool-docker"
IMAGE_NAME="cli-tool-docker-mac"
SHELL_CMD="fish"

# 実行中のコンテナIDを取得
# CONTAINER_ID=$($CONTAINER_CMD ps -q -f "name=${CONTAINER_NAME}" | head -n 1)
CONTAINER_ID=$($CONTAINER_CMD ps | grep $CONTAINER_NAME | awk '{print $1}' | head -n 1)

if [ -z "$CONTAINER_ID" ]; then
    echo "コンテナが見つかりません。新しく起動します..."
    $CONTAINER_CMD \
      run \
        --rm \
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
    # CONTAINER_ID=$($CONTAINER_CMD ps -q -f "name=${CONTAINER_NAME}" | head -n 1)
    CONTAINER_ID=$($CONTAINER_CMD ps | grep $CONTAINER_NAME | awk '{print $1}' | head -n 1)
fi

# シェルを実行
$CONTAINER_CMD exec -it --env TERM=${TERM} --user $(id -u):$(id -g) "$CONTAINER_ID" "$SHELL_CMD"
# $CONTAINER_CMD exec --privileged -it --env TERM=${TERM} "$CONTAINER_ID" "$SHELL_CMD"
