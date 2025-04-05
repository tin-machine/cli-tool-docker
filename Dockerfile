# neovimのmake時に DCMAKE_INSTALL_PREFIX を付けている理由
# マルチステージビルドを行う際に、/usr/local配下にインストールすると、どのファイルをCPOYすべきか完全に把握しづらいため
# (/opt/neovim配下にまとまっているとCOPYで扱いやすい)
# gettext はmakeの前にインストールされている必要がある
#  git gettext shfmt ninja-build gettext cmake unzip curl luajit libluajit-5.1-dev && \
FROM ubuntu:25.04 AS neovim-build
RUN apt-get update && \
    apt-get -y install \
      cmake \
      curl \
      git \
      gettext \
      ninja-build \
      shfmt \
      unzip &&\
    git clone https://github.com/neovim/neovim.git && \
    cd neovim && \
    git fetch origin && \
    git checkout release-0.10 && \
    make -j$(nproc) CMAKE_BUILD_TYPE=Release CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=/opt/neovim" && \
    make install

FROM ubuntu:25.04 AS tmux-build
RUN apt-get update && \
    apt-get -y install \
      autoconf \
      automake \
      bison \
      build-essential \
      git \
      libevent-dev \
      ncurses-dev \
      pkg-config
WORKDIR /build
RUN git clone https://github.com/tmux/tmux.git && \
    cd tmux && \
    sh autogen.sh && \
    ./configure --enable-sixel --prefix=/opt/tmux && \
    make -j$(nproc) && \
    make install

FROM ubuntu:25.04 AS lazygit
RUN apt-get update && \
    apt-get -y install curl
RUN LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | \grep -Po '"tag_name": *"v\K[^"]*') && \
    if [ -z "$LAZYGIT_VERSION" ]; then echo "Failed to get lazygit version"; exit 1; fi && \
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" && \
    tar xf lazygit.tar.gz lazygit

# FROM ubuntu:24.04 AS terraform-install
# # teraformインストール
# # 下記の方法だとlsb_releaseでエラーが起きるのでバイナリをダウンロードする
# # 	wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
# # 	echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list && \
# # 	apt-get update && apt install terraform && \
# # https://developer.hashicorp.com/terraform/install
# RUN	apt-get update && apt-get -y install curl unzip && \
#   curl -L https://releases.hashicorp.com/terraform/1.7.1/terraform_1.7.1_linux_arm64.zip -o terraform.zip && \
#   unzip terraform.zip

FROM ubuntu:25.04 AS nerdctl-install

RUN apt-get update && apt-get install -y \
    curl \
    jq \
    tar

# nerdctl のアーキテクチャ判定とインストール
RUN set -euo pipefail && \
    ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64) ARCH="amd64" ;; \
      aarch64) ARCH="arm64" ;; \
      armv7l) echo "⚠️  armv7l is not supported by nerdctl-full. Exiting." && exit 1 ;; \
      *) echo "❌ Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    OS="linux" && \
    echo "🔍 Fetching latest nerdctl version..." && \
    LATEST_VERSION=$(curl -s https://api.github.com/repos/containerd/nerdctl/releases/latest | jq -r .tag_name) && \
    FILENAME="nerdctl-full-${LATEST_VERSION#v}-${OS}-${ARCH}.tar.gz" && \
    URL="https://github.com/containerd/nerdctl/releases/download/${LATEST_VERSION}/${FILENAME}" && \
    TMPDIR=$(mktemp -d) && \
    echo "📁 Created temp directory: $TMPDIR" && \
    cd "$TMPDIR" && \
    echo "📦 Downloading $FILENAME..." && \
    curl -LO "$URL" && \
    echo "📂 Extracting archive..." && \
    tar -xzf "$FILENAME" && \
    echo "🚀 Installing nerdctl to /usr/local/bin/..." && \
    cp ./bin/* /usr/local/bin/ && \
    cd / && rm -rf "$TMPDIR"

FROM ubuntu:25.04 AS cni-install

ARG CNI_VERSION=v1.3.0

RUN apt-get update && apt-get install -y curl tar

# アーキテクチャ判定とCNIプラグインのダウンロード＆展開
RUN set -euo pipefail && \
    ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64) ARCH="amd64" ;; \
      aarch64) ARCH="arm64" ;; \
      armv7l) echo "❌ armv7l is not supported by CNI plugins" && exit 1 ;; \
      *) echo "❌ Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    OS="linux" && \
    URL="https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-${OS}-${ARCH}-${CNI_VERSION}.tgz" && \
    INSTALL_DIR="/opt/cni/bin" && \

    mkdir -p "$INSTALL_DIR" && \
    echo "📁 Installing CNI plugins to $INSTALL_DIR from $URL" && \
    curl -L "$URL" | tar -xz -C "$INSTALL_DIR" && \
    ls -1 "$INSTALL_DIR"

FROM ubuntu:25.04

ENV DEBIAN_FRONTEND=noninteractive

# unminimizeしている理由としては、manページ、ロケールを追加したいため
# locale-gen は language-pack-ja, language-pack-ja-base の後に実行する
# 以下は :checkhealth でのワーニングへの対応
# mason.nvim: openjdk-11-jre, php, npm
# neoconf.nvim
#   jsonc の解決方法がわからない
#   WARNING **TreeSitter jsonc** parser is not installed. Highlighting of jsonc files might be broken
#   WARNING **lspconfig jsonls** is not installed? You won't get any auto completion in your settings files
# WARNING tree-sitter executable not found (parser generator, only needed for :TSInstallFromGrammar, not required for :TSInstall)
#   :TSInstallFromGrammar を実行する
RUN apt-get update && \
    apt-get -y install \
      language-pack-ja \
      language-pack-ja-base \
      locales \
      tzdata && \
    locale-gen ja_JP.UTF-8 && \
    apt-get -y install \
      ansible \
      bat \
      cargo \
      cmake \
      composer \
      curl \
      direnv \
      dnsutils \
      docker.io \
      docker-compose-v2 \
      fd-find \
      fish \
      fzf \
      gh \
      git \
      golang \
      golang-docker-credential-helpers \
      gosu \
      hugo \
      iproute2 \
      iputils-ping \
      jq \
      libmysqlclient-dev \
      libsixel-bin \
      lv \
      luarocks \
      make \
      mutt \
      mosh \
      mysql-client \
      net-tools \
      nkf \
      node-typescript \
      openjdk-11-jre \
      passwd \
      php \
      python3-full \
      python3-pip \
      python3-pynvim \
      rbenv \
      ripgrep \
      ruby \
      screen \
      shellcheck \
      strace \
      sudo \
      terraform-switcher \
      tmux \
      tig \
      trash-cli \
      tree \
      w3m-img \
      wget \
      yamllint \
      zoxide && \
# gcloud cli のインストール
RUN apt-get update && apt-get install -y \
    gnupg \
    apt-transport-https && \
    echo "deb [signed-by=/etc/apt/trusted.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - && \
    apt-get update && \
    apt-get install -y google-cloud-sdk && \
    gcloud --version
# 独自のビルドオプションを付けたものをCOPYするので
# 既存のパッケージからインストールしたものは削除する
    apt-get -y remove neovim neovim-runtime tmux && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    cargo install stylua

ENV LC_ALL=ja_JP.UTF-8
ENV LANGUAGE=ja_JP.UTF-8
ENV LANG=ja_JP.UTF-8

RUN echo "export LANG=ja_JP.UTF-8" >> /etc/profile.d/locale.sh && \
    echo "export LANGUAGE=ja_JP.UTF-8" >> /etc/profile.d/locale.sh && \
    echo "export LC_ALL=ja_JP.UTF-8" >> /etc/profile.d/locale.sh

# # 関連するライブラリは次を参照 https://packages.debian.org/sid/source/neovim
# # 既存のneovimは削除する
# RUN apt-get update && \
#     apt-get -y remove neovim neovim-runtime && \
#     apt-get -y install \
#       git gettext shfmt unzip ninja-build gettext cmake curl build-essential \
#       python3-pynvim \
#       ca-certificates curl libcurl4-openssl-dev \
#       libacl1-dev libluajit-5.1-dev libmsgpack-dev libnss-wrapper libtermkey-dev libtree-sitter-dev libunibilium-dev libuv1-dev libvterm-dev \
#       lua-bitop lua-busted lua-coxpcall lua-filesystem lua-inspect lua-lpeg lua-luv-dev lua-mpack luajit \
#       tree-sitter-c-src tree-sitter-lua-src tree-sitter-query-src tree-sitter-vim-src tree-sitter-vimdoc-src
# RUN git clone https://github.com/neovim/neovim.git && \
#     cd neovim && \
#     git fetch origin && \
#     git checkout release-0.10 && \
#     make CMAKE_BUILD_TYPE=Release CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=/opt/neovim" && \
#     make install

# neovimに必要なパッケージと gcc-11のシンボリックリンクを作成している
# 下記のエラーが出るため
#  Failed to source `/Users/jp30943/.local/share/nvim/lazy/vim-illuminate/plugin/illuminate.vim`
#
#  vim/_editor.lua:0: BufReadPost Autocommands for "*"..script nvim_exec2() called at BufReadPost Autocommands for "*":0../Users/jp30943/.local/share/nvim/lazy/vim-illuminate/plugin/illuminate.vim, line 45: Vim(lua):No C compiler found! "gcc-11" are not executable.
RUN	cd /usr/bin/ && ln -s gcc-13 gcc-11

# RUN	curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip" && \
#   unzip awscliv2.zip && \
#   sudo ./aws/install && \
# 	rm -rf aws && \
#   curl -L "https://dl.k8s.io/release/$(curl -LS https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl" -o /usr/local/bin/kubectl && \
#   chmod +x /usr/local/bin/kubectl

# Neovimとその依存ファイルをコピー
COPY --from=neovim-build /opt/neovim /opt/neovim
COPY --from=tmux-build /opt/tmux /opt/tmux
COPY --from=nerdctl-install /usr/local/bin/ /usr/local/bin/
COPY --from=lazygit lazygit /usr/local/bin/lazygit
COPY --from=cni-install /opt/cni /opt/cni
ENV PATH="/opt/cni/bin:$PATH"
# COPY --from=terraform-install /terraform /usr/local/bin/
ENV PATH="/opt/neovim/bin:/opt/tmux/bin:$PATH"

# エントリーポイントスクリプトのコピー
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# エントリーポイントの設定
ENTRYPOINT ["stdbuf", "-oL", "/usr/local/bin/entrypoint.sh"]

# デフォルトのコマンド
# CMD ["bash", "-l"]
CMD ["tail", "-F", "/dev/null"]
