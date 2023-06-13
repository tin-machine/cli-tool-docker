FROM ubuntu:23.04
ENV LC_ALL=ja_JP.UTF-8
ENV LANGUAGE=ja_JP.UTF-8
ENV LANG=ja_JP.UTF-8

RUN useradd -u 503 -g 20 jp30943 -d /Users/jp30943

RUN yes | unminimize

RUN apt update && apt -y upgrade &&   apt -y install   \
        language-pack-ja-base   language-pack-ja   \
	man-db manpages-ja manpages-ja-dev
RUN locale-gen ja_JP.UTF-8
RUN apt update && apt -y upgrade &&   apt -y install   \
	curl   wget   fish   lv   gh   mutt   mosh   \
	w3m-img   docker   golang   git   autoconf   \
	libtool   autotools-dev   automake   libevent-dev   \
	libncurses-dev   bison   libevent-dev   libevent-2.1-7   \
	libncurses-dev   make cmake  libtool   libssl-dev   bison   \
	byacc   libsixel-bin   libsixel-dev   screen   pkg-config   \
	fzf   python3-pip   python3-saneyaml   ruby   \
	shellcheck   ripgrep   zoxide   yamllint \
	jq \
        trash-cli \
        tig \
        ripgrep \
        dnsutils \
        newsboat \
        net-tools iputils-ping \
        hugo tree

# neovim
# rafi/vim-config 
RUN git clone --depth 1 https://github.com/neovim/neovim.git
# gettext はmakeの前にインストールされている必要がある
# 他ビルドに必要なUbuntuパッケージは https://github.com/neovim/neovim/wiki/Building-Neovim#ubuntu--debian
RUN apt update && apt -y upgrade &&   apt -y install \
	gettext cargo shfmt && \
	cargo install stylua
RUN cd neovim && \
	make CMAKE_BUILD_TYPE=Release && \
	make install

# typescript-language-server typescript typescript-deno-plugin は
# vim の LSPで使用
# vim で javascript を編集する際に deno
# などを使いたいが、nodejs14以上を要求するため、curlでレポジトリ追加
# curlの行をapt updateの行より上に持っていくと動作しなかった( 調査が必要 )
# vim-lsp は package.json か node_modules ディレクトリが無いと動作しない
# https://teratail.com/questions/371615
RUN curl -sL https://deb.nodesource.com/setup_16.x | bash -
RUN apt -y install nodejs npm
RUN npm install -g markdownlint-cli typescript-language-server typescript typescript-deno-plugin

# Python関連
RUN apt update && apt -y upgrade &&   apt -y install   \
	pipx
RUN apt -y remove python3-pynvim
RUN python3 -m pip install --break-system-packages pynvim

# Docker内にvncをたててアクセスする方法を試した
# RUN apt update && apt -y upgrade &&\
#   DEBIAN_FRONTEND=noninteractive   apt -y install\
# 	lxde   tigervnc-standalone-server   tigervnc-common   novnc   websockify

# RUN echo \"export LANG=ja_JP.UTF-8\" >> ~/.bashrc


# 下記は sudo 許可を試した
# containerd内のコンテナから
# nerdctlコマンドが使えないか試してみた時のもの。
# 数時間消化してもダメだった( いずれsystemd無しでも使えるようになると思うが )
# RUN apt -y install sudo
# RUN usermod -aG sudo jp30943
# RUN echo "jp30943        ALL=(ALL)       NOPASSWD: ALL" >> /etc/sudoers
