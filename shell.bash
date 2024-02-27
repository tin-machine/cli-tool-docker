#!/bin/bash

PATH=$PATH:~/.rd/bin

nerdctl \
  run \
    --privileged \
    --network host \
    --volume $HOME:$HOME \
    --user 0:0 \
    -it \
      cli-tool-docker sh -c \
        "hostname localhost && \
        useradd \
          --uid $(id -u) \
          --gid $(id -g) \
	        --home $HOME \
	        --shell /usr/bin/fish \
	        $USER 2> /dev/null && \
        echo '${USER} ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/user && \
        chmod 440 /etc/sudoers.d/user && \
	      su - $USER"

# メモ
# ホスト名を/etc/hostsに追記しようとすると「読み込み専用のファイルシステムです」というエラーが出る
# (containerdの仕様かも)このためホスト名はlocalhostにしている。
# ホスト名の名前解決ははsudoする際に必要になる。
# /etc/sudoers.d配下のファイルは
# - ファイル名にドットを含んではいけない(意図しないファイルを読み込むのを防ぐため)
# - 440である必要がある
