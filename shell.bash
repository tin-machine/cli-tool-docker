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

# コンテナランタイムが起動しているかチェック
if ! $CONTAINER_CMD info >/dev/null 2>&1; then
    echo "Error: コンテナランタイムが起動していないか、正常に動作していません。"
    exit 10
fi

# 設定: 使用するコンテナ名とイメージ
CONTAINER_NAME="cli-tool-docker"

# アーキテクチャに応じてコンテナイメージを設定
ARCH=$(uname -s)
case $ARCH in
    Darwin)
        IMAGE_NAME="cli-tool-docker"
        ;;
    Linux)
        IMAGE_NAME="ghcr.io/tin-machine/cli-tool-docker"
        ;;
    *)
        echo "Error: 未対応のアーキテクチャ ($ARCH) です。" >&2
        exit 1
        ;;
esac

# mac（Darwin）の場合、イメージが存在しなければDockerfileからビルドする
if [ "$ARCH" = "Darwin" ]; then
    if ! $CONTAINER_CMD image inspect "$IMAGE_NAME:latest" >/dev/null 2>&1; then
        echo "mac向けのイメージ $IMAGE_NAME が見つからないため、Dockerfile からビルドします..."
        # スクリプトが置いてあるディレクトリを取得
        SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
        echo $SCRIPT_DIR
        $CONTAINER_CMD build -t "$IMAGE_NAME:latest" "$SCRIPT_DIR"
    fi
fi


# 実行中のコンテナIDを取得
CONTAINER_ID=$($CONTAINER_CMD ps | grep $CONTAINER_NAME | awk '{print $1}' | head -n 1)

if [ -z "$CONTAINER_ID" ]; then
    echo "コンテナが見つかりません。新しく起動します..."
    $CONTAINER_CMD \
      run \
        --rm \
        --network host \
        --volume /var/run/docker.sock:/var/run/docker.sock \
        --ipc shareable \
        --volume $HOME:$HOME \
        --env HOME=${HOME} \
        --env UID=$(id -u) \
        --env GID=$(id -g) \
        --env USER_NAME=$(whoami) \
        -w ${HOME} \
        --privileged \
        $( [ "$CONTAINER_CMD" = "nerdctl" ] && echo "--init" ) \
        "$IMAGE_NAME:latest"

    # コンテナIDを再取得
    sleep 5
    # CONTAINER_ID=$($CONTAINER_CMD ps -q -f "name=${CONTAINER_NAME}" | head -n 1)
    CONTAINER_ID=$($CONTAINER_CMD ps | grep $CONTAINER_NAME | awk '{print $1}' | head -n 1)
fi

# 第一引数があればシェルコマンドとして使い、なければデフォルトはbash
if [ "$#" -ge 1 ]; then
    SHELL_CMD="$1"
    shift  # 最初の引数を取り除く
else
    SHELL_CMD="bash"
fi

# シェルを実行
$CONTAINER_CMD exec -it --env TERM=${TERM} --user $(id -u):$(id -g) "$CONTAINER_ID" "$SHELL_CMD" "$@"
# $CONTAINER_CMD exec --privileged -it --env TERM=${TERM} "$CONTAINER_ID" "$SHELL_CMD" "$@"
