# cli-tool-docker

通常、macなりLinuxでCLIの作業環境を作成すると環境を壊すリスクが恐ろしい。
コンテナイメージの形で利用すると、カジュアルにアップデートなり、新しいツールの検証ができる。
このため自分が良く使うコマンドを集めたコンテナイメージを作る事にした。

# コンテナのイメージのビルド方法

```
nerdctl build -t cli-tool-docker:latest ~/workspace/git/github.com/tin-machine/cli-tool-docker/
```

# 設定の背景

## manpageが使いたかったので unminimize した、
イメージのサイズは結構ふえる。

## neovim

#### コンパイルしている理由
rafi-config が使用する razy.vim が neovim 8以上である必要がある。

copilotも利用している( [github/copilot.vim: Neovim plugin for GitHub Copilot](https://github.com/github/copilot.vim) ) によるとNeovimであれば良いらしい。
Ubuntuの標準のneovimのバージョンが8になったら素のneovimでも大丈夫か試す。
(一方、Vimにはバージョンの縛りがある)

#### neovimのビルドオプション
[ここに説明がある](https://github.com/neovim/neovim/wiki/Building-Neovim#building)
- Release
- Debug
- RelWithDebInfo

# ログインするユーザの作成をどうするか?

これを行わないとコンテナに入った後、ファイルのuid:gidが実環境と異なってしまう。
ただ汎用的に使えるコンテナイメージにしたいのでユーザ名、uid、gidはDockerfileには含めたくない。
アプローチとしては2つある。

1. 汎用的なコンテナイメージを利用するDockerfileを別に作り、このDockerfileの中でuseraddする。
2. ワンライナーやシェルスクリプトでコンテナ起動後にuseraddしてsu - ユーザ名のようにユーザを変える。

作業用PCでのみ使用するので2の方法を試す。
下記のスクリプトでは一旦、 --user 0:0 とrootでログインし、useraddを行いfishを起動している。

```
#!/bin/bash

sudo nerdctl \
  --address /run/k3s/containerd/containerd.sock \
  --namespace k8s.io \
  run \
    --privileged \
    --network host \
    --volume $HOME:$HOME \
    --user 0:0 \
    -it \
      cli-tool-docker sh -c \
        "useradd \
          --uid $(id -u) \
          --gid $(id -g) \
	        --home $HOME \
	        --shell /usr/bin/fish \
	        $USER && \
	      su - $USER"
```

上記の検証中、下記のエラーが出ることがあった。
su - ユーザ名 -c fishというようにsu経由でコマンドを実行しようとするとエラーになる。
デフォルトシェルをfishとする(useradd のオプションに --shell /usr/bin/fish 付けて起動する)事で回避できた。

```
su - kaoru -c fish
warning: No TTY for interactive shell (tcgetpgrp failed)
setpgid: デバイスに対する不適切なioctlです
```
