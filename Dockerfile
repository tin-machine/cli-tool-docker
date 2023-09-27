FROM ubuntu:23.04
ENV LC_ALL=ja_JP.UTF-8
ENV LANGUAGE=ja_JP.UTF-8
ENV LANG=ja_JP.UTF-8

# locale-gen は language-pack-ja, language-pack-ja-base の後に実行する

# node
# typescript-language-server typescript typescript-deno-plugin は
# vim の LSPで使用
# vim で javascript を編集する際に deno
# などを使いたいが、nodejs14以上を要求するため、curlでレポジトリ追加
# curlの行をapt updateの行より上に持っていくと動作しなかった( 調査が必要 )
# vim-lsp は package.json か node_modules ディレクトリが無いと動作しない
# https://teratail.com/questions/371615

RUN yes | unminimize && \
    apt -y install \
        language-pack-ja-base \
	language-pack-ja && \
        locale-gen ja_JP.UTF-8 && \
    apt -y install \
	screen \
	fish \
	mutt \
	mosh \
	w3m-img \
        newsboat \
	lv \
	curl \
	wget \
	fzf \
	ripgrep \
	jq \
        trash-cli \
        ripgrep \
	man-db \
	manpages-ja \
	manpages-ja-dev \
        dnsutils \
        net-tools \
	iputils-ping \
        hugo \
	tree \
	docker \
	golang \
	ruby \
        python3-full \
	python3-pip \
	git \
        tig \
	gh \
	shellcheck \
	yamllint \
	zoxide \
	make \
	cmake \
	libtool \
	autoconf \
	bison \
	byacc \
	libtool \
	autotools-dev \
	automake \
	bison \
	pkg-config \
	libevent-dev \
	libncurses-dev \
	libevent-dev \
	libevent-2.1-7 \
	libncurses-dev \
	libssl-dev \
	libsixel-bin \
	libsixel-dev && \
    curl -sL https://deb.nodesource.com/setup_16.x | bash - && \
    apt -y install nodejs npm && \
    npm install -g markdownlint-cli typescript-language-server typescript typescript-deno-plugin

# neovim
# rafi/vim-config 
# gettext はmakeの前にインストールされている必要がある
# 他ビルドに必要なUbuntuパッケージは
#   https://github.com/neovim/neovim/wiki/Building-Neovim#ubuntu--debian
#   https://github.com/neovim/neovim/wiki/Building-Neovim#debian-10-buster-example
# ビルドオプション
#  https://github.com/neovim/neovim/wiki/Building-Neovim#building
#	  Release
#   Debug
#	  RelWithDebInfo
RUN apt -y install \
	gettext cargo shfmt ninja-build gettext cmake unzip curl \
	bat fd-find ripgrep zoxide && \
	cargo install stylua && \
    git clone https://github.com/neovim/neovim.git && \
    cd neovim && git fetch origin && git checkout release-0.9 && \
	make CMAKE_BUILD_TYPE=RelWithDebInfo && \
	make install && \
    apt -y remove python3-pynvim && \
    python3 -m pip install --break-system-packages pynvim

RUN apt update && \
    apt -y upgrade && \
    useradd -u 503 -g 20 jp30943 -d /Users/jp30943
