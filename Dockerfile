FROM ubuntu:24.04 AS neovim-build
# node
# typescript-language-server typescript typescript-deno-plugin は
# vim の LSPで使用
# vim で javascript を編集する際に deno
# などを使いたいが、nodejs14以上を要求するため、curlでレポジトリ追加
# curlの行をapt updateの行より上に持っていくと動作しなかった( 調査が必要 )
# vim-lsp は package.json か node_modules ディレクトリが無いと動作しない
# https://teratail.com/questions/371615
#
# RUN curl -sL https://deb.nodesource.com/setup_16.x | bash - && \
# 	apt -y install nodejs npm && \
# 	npm install -g markdownlint-cli typescript-language-server typescript typescript-deno-plugin
#
# neovim
# [github/copilot.vim: Neovim plugin for GitHub Copilot](https://github.com/github/copilot.vim) によるとNeovimであれば良いらしい。
#   素のneovimでも大丈夫か試す( Vimにはバージョンの縛りがある ) <- rafi-config が使用する razy.vim が neovim 8以上である必要がある。
# gettext はmakeの前にインストールされている必要がある
# 他ビルドに必要なUbuntuパッケージは
#   https://github.com/neovim/neovim/wiki/Building-Neovim#ubuntu--debian
#   https://github.com/neovim/neovim/wiki/Building-Neovim#debian-10-buster-example
# ビルドオプション
#  https://github.com/neovim/neovim/wiki/Building-Neovim#building
#	  Release
#   Debug
#	  RelWithDebInfo
#
# DCMAKE_INSTALL_PREFIX を付けている理由
# マルチステージビルドを行う際に、/usr/local配下にインストールすると、どのファイルをCPOYすべきか完全に把握しづらいため
# (/opt/neovim配下にまとまっているとCOPYで扱いやすい)
RUN apt-get update && apt-get -y install \
	git gettext shfmt ninja-build gettext cmake unzip curl luajit libluajit-5.1-dev && \
  git clone https://github.com/neovim/neovim.git && \
  cd neovim && git fetch origin && git checkout release-0.9 && \
 	make CMAKE_BUILD_TYPE=RelWithDebInfo CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=/opt/neovim" && \
 	make install

FROM ubuntu:24.04

ENV LC_ALL=ja_JP.UTF-8
ENV LANGUAGE=ja_JP.UTF-8
ENV LANG=ja_JP.UTF-8

# Neovimとその依存ファイルをコピー
COPY --from=neovim-build /opt/neovim /opt/neovim

# unminimizeしている理由としては、manページ、ロケールを追加したいため
# locale-gen は language-pack-ja, language-pack-ja-base の後に実行する
RUN yes | unminimize && \
	apt-get -y install \
	language-pack-ja-base \
	language-pack-ja && \
	locale-gen ja_JP.UTF-8 && \
	apt-get -y install \
	bat \
	cargo \
	curl \
	dnsutils \
	fd-find \
	fish \
	fzf \
	gh \
	git \
	golang \
	hugo \
	iputils-ping \
	jq \
	lv \
	mutt \
	mosh \
	newsboat \
	ripgrep \
	man-db \
	manpages-ja \
	manpages-ja-dev \
	net-tools \
	node-typescript \
	passwd \
	python3-full \
	python3-pip \
	python3-pynvim \
	ripgrep \
	ruby \
	screen \
	shellcheck \
	sudo \
	tmux \
	tig \
	trash-cli \
	tree \
	w3m-img \
	wget \
	yamllint \
	zoxide \
	make \
	cmake && \
 	cargo install stylua && \
  apt-get update && \
	apt-get -y upgrade

# RUN apt-get -y remove python3-pynvim && \
#  python3 -m pip install --break-system-packages pynvim

# neovimに必要なパッケージと gcc-11のシンボリックリンクを作成している
# 下記のエラーが出るため
#  Failed to source `/Users/jp30943/.local/share/nvim/lazy/vim-illuminate/plugin/illuminate.vim`
#
#  vim/_editor.lua:0: BufReadPost Autocommands for "*"..script nvim_exec2() called at BufReadPost Autocommands for "*":0../Users/jp30943/.local/share/nvim/lazy/vim-illuminate/plugin/illuminate.vim, line 45: Vim(lua):No C compiler found! "gcc -11" are not executable.
RUN	cd /usr/bin/ && ln -s gcc-13 gcc-11

# tmuxのビルド <- これはdocker内ではなくmacOS上でおこなう
# [Tmux でSixel – matoken's meme](https://matoken.org/blog/2023/11/06/tmux-in-sixel/)を試す。
# RUN apt -y install \
#  vlock build-essential git
# RUN \
#   apt -y build-dep tmux && \
#   git clone https://github.com/tmux/tmux && \
#   cd tmux && \
#   ./configure --enable-sixel --prefix=/usr/local && \
#   make

# RUN useradd -u 503 -g 20 jp30943 -d /Users/jp30943

# 下記を試す 。　これができれば公開できる
# ワンライナーで起動 <- useradd が root権限が必要だと思う。うまく動かなそう
# ~/.rd/bin/nerdctl run --privileged --network=host -h localhost -u 0:0 -v ~/:/Users/jp30943/ -w /Users/jp30943/ -it test2 sh -c "useradd -u 503 -g 20 jp30943 -d /Users/jp30943 && su jp30943 -c fish"
#
#
# 別のdockerfileを使う。指定するイメージは、私の作成したdockerイメージに変更する
#
# # FROM ubuntu:latest
#
# # 新しいユーザーを作成
# RUN useradd -u 1000 -m -s /bin/bash newuser
#
# # 以降のコマンドを新しいユーザーとして実行
# USER newuser
#
# # コンテナの作業ディレクトリを設定
# WORKDIR /home/newuser

# ビルド方法
# nerdctl build -t test2:latest ~/workspace/git/github.com/tin-machine/cli-tool-docker/ && nerdctl tag test2:latest test2:(date +%Y%m%d%H%M)

    # 下記のエラーが出る。 privileged を付けているがttyの割当に制限があるのかもしれない。
    # https://orebibou.com/ja/home/201901/20190115_001/
    # 書き方自体はあっているようだが。
    # su - jp30943 -c fish
    # warning: No TTY for interactive shell (tcgetpgrp failed)
    # setpgid: デバイスに対する不適切なioctlです
    #
    # dockerイメージを作るアプローチに切り替える
    #
    # いきなりsuしてるのが良くないのか? <- 一度rootでログインした後であればできる
    #  /bin/bash -c を経由して su を実行してはどうか

    # ~/.rd/bin/nerdctl run --privileged --network=host -h localhost -u 0:0 -v ~/:/Users/jp30943/ -w /Users/jp30943/ -it test2 sh -c "/usr/sbin/useradd -u 503 -g 20 jp30943 -d /Users/jp30943 ; fish"
    # ~/.rd/bin/nerdctl run --privileged --network=host -h localhost -u 0:0 -v ~/:/Users/jp30943/ -w /Users/jp30943/ -it test2 sh -c "/usr/sbin/useradd -u 503 -g 20 jp30943 -d /Users/jp30943 ; bash -c 'su - jp30943 -c fish'"
    # ~/.rd/bin/nerdctl run --privileged --network=host -h localhost -u 0:0 -v ~/:/Users/jp30943/ -w /Users/jp30943/ -it test2 sh -c "/usr/sbin/useradd -u 503 -g 20 jp30943 -d /Users/jp30943 ; bash -c 'su - jp30943 --command fish'"
    # ~/.rd/bin/nerdctl run --privileged --network=host -h localhost -u 0:0 -v ~/:/Users/jp30943/ -w /Users/jp30943/ -it test2 sh -c "/usr/sbin/useradd -u 503 -g 20 jp30943 -d /Users/jp30943 ; su --login jp30943 -c /usr/bin/fish "
    # できた
    # ~/.rd/bin/nerdctl run --privileged --network=host -h localhost -u 0:0 -v ~/:/Users/jp30943/ -w /Users/jp30943/ -it test2 sh -c "/usr/sbin/useradd -u 503 -g 20 jp30943 -d /Users/jp30943 -s /usr/bin/fish ; su --login jp30943"

# セキュリティチェックを導入したい
# https://tech.connehito.com/entry/2023/12/21/104631
