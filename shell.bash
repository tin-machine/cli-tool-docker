#!/bin/bash

# コンテナの起動を待機する関数
wait_for_container() {
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        CONTAINER_ID=$($CONTAINER_CMD ps --format "{{.ID}}\t{{.Image}}\t{{.Names}}\t{{.CreatedAt}}" | \
            grep "$CONTAINER_NAME" | \
            sort -k4 -r | \
            head -n 1 | \
            awk '{print $1}')
        if [ -n "$CONTAINER_ID" ]; then
            # コンテナが実際に応答可能か確認
            if $CONTAINER_CMD exec "$CONTAINER_ID" echo "ready" >/dev/null 2>&1; then
                return 0
            fi
        fi
        sleep 0.5
        attempt=$((attempt + 1))
    done
    echo "Error: コンテナの起動に失敗しました" >&2
    exit 1
}

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
case "$ARCH" in
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
        $CONTAINER_CMD build -t "$IMAGE_NAME:latest" "$SCRIPT_DIR"
    fi
fi

# 実行中のコンテナIDを取得（最新のものを選択）
CONTAINER_ID=$($CONTAINER_CMD ps --format "{{.ID}} {{.Image}} {{.Names}} {{.CreatedAt}}" | \
    grep "$CONTAINER_NAME" | \
    sort -k4 -r | \
    head -n 1 | \
    awk '{print $1}')


if [ -z "$CONTAINER_ID" ]; then
    echo "コンテナが見つかりません。新しく起動します..."

    # ボリューム設定
    # /var/run/docker.sock をマウントしているのは、コンテナ内で更にコンテナを起動したいために設定しています
    # (但しRancher Desktopの場合、sudoアクセスが必要)
    VOLUME_OPTS=(--volume /var/run/docker.sock:/var/run/docker.sock)
    if [ -S /run/containerd/containerd.sock ]; then
        VOLUME_OPTS+=(--volume /run/containerd/containerd.sock:/run/containerd/containerd.sock)
    else
        echo "⚠️ /run/containerd/containerd.sock が見つかりません。nerdctl は使えないかもしれません。" >&2
    fi

    if [ -d /var/lib/containerd ]; then
        VOLUME_OPTS+=(--volume /var/lib/containerd:/var/lib/containerd)
    else
        echo "⚠️ /var/lib/containerd が見つかりません。nerdctl が正しく動作しない可能性があります。" >&2
    fi

    if [ -d /etc/containerd ]; then
        VOLUME_OPTS+=(--volume /etc/containerd:/etc/containerd:ro)
    else
        echo " /etc/containerd が見つかりません。" >&2
    fi

    INIT_OPT=()
    if [ "$CONTAINER_CMD" = "nerdctl" ]; then
        INIT_OPT+=(--init)
    fi

    # docker in docker でコンテナを起動したい。この場合、必要な事として
    # - 起動したコンテナのプロセスがdockerグループに属している
    # - --group-add にコンテナ内のdockerグループのGIDを設定する(GIDは将来的に変わる可能性があります)
    #   - このため、一度、コンテナを起動、コンテナ内のdockerのGIDを取得しています
    #   - entrypoint.shで USER_NAME, UID, GID を必要としているのでダミーとして入れています
    # login / sshd / su / newgrp などのログイン系プログラムは、ユーザ認証後に glibc の initgroups(3) を呼びます。
    # が、コンテナの場合、fish -lとしてもinitgroups(3)は処理されず、親プロセスのGIDを引き継ぐのみです、このため親プロセス側で --group-add しています
    # DOCKER_SOCK_GID_INSIDE="$($CONTAINER_CMD run --rm --env USER_NAME='customuser' --env UID=1002 --env GID=1002 "$IMAGE_NAME:latest" awk -F ":" '/^docker:/{print $3}' /etc/group)"
    DOCKER_SOCK_GID_INSIDE="$($CONTAINER_CMD run --rm --env USER_NAME='customuser' --env UID=1002 --env GID=1002 "$IMAGE_NAME:latest" getent group docker | cut -d: -f3)"

    $CONTAINER_CMD \
      run \
        -d \
        --network host \
        "${VOLUME_OPTS[@]}" \
        --ipc shareable \
        --volume "$HOME:$HOME" \
        --env HOME="${HOME}" \
        --env UID="$(id -u)" \
        --env GID="$(id -g)" \
        --env USER_NAME="$(whoami)" \
        -w "${HOME}" \
        --group-add "${DOCKER_SOCK_GID_INSIDE}" \
        --privileged \
        "${INIT_OPT[@]}" \
        "$IMAGE_NAME:latest"

    # コンテナの起動を待機
    wait_for_container
fi

# 第一引数があればシェルコマンドとして使い、なければデフォルトはbash
if [ "$#" -ge 1 ]; then
    SHELL_CMD="$1"
    shift  # 最初の引数を取り除く
else
    SHELL_CMD="bash"
fi

# ロケール設定（デフォルトは ja_JP.UTF-8、環境変数があればそれを使用）
LOCALE_LC_ALL="${LC_ALL:-ja_JP.UTF-8}"

# タイムゾーン設定（デフォルトは Asia/Tokyo、環境変数があればそれを使用）
TIMEZONE="${TZ:-Asia/Tokyo}"

# TERM設定（デフォルトはscreen-256color-bce 、環境変数があればそれを使用）
TERMINAL="${TERM:-screen-256color-bce}"

# シェルを実行
$CONTAINER_CMD exec -it --env TERM="${TERMINAL}" --env LC_ALL="${LOCALE_LC_ALL}" --env TZ="${TIMEZONE}" --user "$(id -u):$(id -g)" "$CONTAINER_ID" "$SHELL_CMD" "$@"
# $CONTAINER_CMD exec -it --env TERM="${TERMINAL}" --env LC_ALL="${LOCALE_LC_ALL}" --env TZ="${TIMEZONE}" "$CONTAINER_ID" "$SHELL_CMD" "$@"
# $CONTAINER_CMD exec -it --env TERM="${TERMINAL}" --env LC_ALL="${LOCALE_LC_ALL}" --env TZ="${TIMEZONE}" --privileged "$CONTAINER_ID" "$SHELL_CMD" "$@"
