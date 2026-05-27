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
    echo "[shell] Error: コンテナの起動に失敗しました" >&2
    exit 1
}

get_path_gid() {
    local path="$1"

    if stat -Lc '%g' "$path" >/dev/null 2>&1; then
        stat -Lc '%g' "$path"
    else
        stat -L -f '%g' "$path"
    fi
}

# コンテナ管理ツールを決定
if command -v docker >/dev/null 2>&1; then
    CONTAINER_CMD="docker"
elif command -v nerdctl >/dev/null 2>&1; then
    CONTAINER_CMD="sudo nerdctl"
else
    echo "[shell] Error: nerdctl も docker も見つかりません。" >&2
    exit 1
fi

# コンテナランタイムが起動しているかチェック
if ! $CONTAINER_CMD info >/dev/null 2>&1; then
    echo "[shell] Error: コンテナランタイムが起動していないか、正常に動作していません。"
    exit 10
fi

# 設定: 使用するコンテナ名とイメージ
CONTAINER_NAME="cli-tool-docker"

# アーキテクチャに応じてコンテナイメージを設定
ARCH=$(uname -s)
case "$ARCH" in
    Darwin)
        IMAGE_NAME="${CLI_TOOL_DOCKER_IMAGE:-cli-tool-docker}"
        ;;
    Linux)
        IMAGE_NAME="${CLI_TOOL_DOCKER_IMAGE:-ghcr.io/tin-machine/cli-tool-docker}"
        ;;
    *)
        echo "[shell] Error: 未対応のアーキテクチャ ($ARCH) です。" >&2
        exit 1
        ;;
esac

# mac（Darwin）の場合、イメージが存在しなければDockerfileからビルドする
if [ "$ARCH" = "Darwin" ]; then
    if ! $CONTAINER_CMD image inspect "$IMAGE_NAME:latest" >/dev/null 2>&1; then
        echo "[shell] mac向けのイメージ $IMAGE_NAME が見つからないため、Dockerfile からビルドします..."
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
    echo "[shell] コンテナが見つかりません。新しく起動します..."

    # ボリューム設定
    # /var/run/docker.sock をマウントしているのは、コンテナ内で更にコンテナを起動したいために設定しています
    # (但しRancher Desktopの場合、sudoアクセスが必要)
    VOLUME_OPTS=()
    DOCKER_GROUP_OPTS=()
    DOCKER_SOCK_GID=""
    if [ -S /var/run/docker.sock ]; then
        VOLUME_OPTS+=(--volume /var/run/docker.sock:/var/run/docker.sock)
        DOCKER_SOCK_GID="$(get_path_gid /var/run/docker.sock)"
        if [ -n "$DOCKER_SOCK_GID" ]; then
            DOCKER_GROUP_OPTS+=(--group-add "${DOCKER_SOCK_GID}")
        else
            echo "[shell] ⚠️ /var/run/docker.sock の GID を取得できませんでした。docker は権限不足になるかもしれません。" >&2
        fi
    else
        echo "[shell] ⚠️ /var/run/docker.sock が見つかりません。docker は使えないかもしれません。" >&2
    fi

    if [ -S /run/containerd/containerd.sock ]; then
        VOLUME_OPTS+=(--volume /run/containerd/containerd.sock:/run/containerd/containerd.sock)
    else
        echo "[shell] ⚠️ /run/containerd/containerd.sock が見つかりません。nerdctl は使えないかもしれません。" >&2
    fi

    if [ -d /var/lib/containerd ]; then
        VOLUME_OPTS+=(--volume /var/lib/containerd:/var/lib/containerd)
    else
        echo "[shell] ⚠️ /var/lib/containerd が見つかりません。nerdctl が正しく動作しない可能性があります。" >&2
    fi

    if [ -d /etc/containerd ]; then
        VOLUME_OPTS+=(--volume /etc/containerd:/etc/containerd:ro)
    else
        echo "[shell] /etc/containerd が見つかりません。" >&2
    fi

    INIT_OPT=()
    if [ "${CONTAINER_CMD##* }" = "nerdctl" ]; then
        INIT_OPT+=(--init)
    fi

    # Docker socket を bind mount する場合、必要なのは image 内の docker group GID ではなく
    # host 側 /var/run/docker.sock の数値 GID。entrypoint でこの GID の group を作業 user に付ける。
    # login / sshd / su / newgrp などのログイン系プログラムは、ユーザ認証後に glibc の initgroups(3) を呼びます。
    # が、コンテナの場合、fish -lとしてもinitgroups(3)は処理されず、親プロセスのGIDを引き継ぐのみです、このため親プロセス側で --group-add しています

    cat <<EOF
[shell] コンテナを起動します
  CONTAINER_CMD: $CONTAINER_CMD
  VOLUME_OPTS: ${VOLUME_OPTS[*]}
  HOME: $HOME
  whoami: $(whoami)
  id -u: $(id -u)
  id -g: $(id -g)
  IMAGE_NAME: $IMAGE_NAME
  DOCKER_SOCK_GID: ${DOCKER_SOCK_GID}
EOF

    $CONTAINER_CMD \
      run \
        -d \
        --name "$CONTAINER_NAME" \
        --user 0:0 \
        --network host \
        "${VOLUME_OPTS[@]}" \
        --ipc shareable \
        --volume "$HOME:$HOME" \
        --volume /etc/resolv.conf:/etc/resolv.conf \
        --env HOME="${HOME}" \
        --env UID="$(id -u)" \
        --env GID="$(id -g)" \
        --env USER="$(whoami)" \
        --env DOCKER_SOCK_GID="${DOCKER_SOCK_GID}" \
        -w "${HOME}" \
        --privileged \
        --group-add 20 \
        "${DOCKER_GROUP_OPTS[@]}" \
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
# $CONTAINER_CMD exec -it --security-opt seccomp=unconfined --env TERM="${TERMINAL}" --env LC_ALL="${LOCALE_LC_ALL}" --env TZ="${TIMEZONE}" --user "$(id -u):$(id -g)" --privileged "$CONTAINER_ID" "$SHELL_CMD" "$@"
# $CONTAINER_CMD exec -it --env TERM="${TERMINAL}" --env LC_ALL="${LOCALE_LC_ALL}" --env TZ="${TIMEZONE}" --privileged "$CONTAINER_ID" "$SHELL_CMD" "$@"
# $CONTAINER_CMD exec -it --env TERM="${TERMINAL}" --env LC_ALL="${LOCALE_LC_ALL}" --env TZ="${TIMEZONE}" --user "$(id -u):$(id -g)" --privileged "$CONTAINER_ID" "$SHELL_CMD" "$@"

# 下記はコンテナ内の setpriv --init-groups を使う（PAMに依存しない）
# --init-groups が /etc/group を元に supplementary groups を設定します（= dialout を有効にしシリアルコンソールにアクセスできるようにする）
# exec --user uid:gid で入ると supplementary groups が初期化されない
# root で exec → su / setpriv --init-groups で降りると、initgroups(3) が走って解決
$CONTAINER_CMD exec -it \
  --env TERM="${TERMINAL}" --env LC_ALL="${LOCALE_LC_ALL}" --env TZ="${TIMEZONE}" \
  --user 0:0 \
  "$CONTAINER_ID" bash -lc \
  'exec setpriv --reuid='"$(id -u)"' --regid='"$(id -g)"' --init-groups '"$SHELL_CMD"' "$@"' bash "$@"
